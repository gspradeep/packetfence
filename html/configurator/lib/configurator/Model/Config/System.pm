package configurator::Model::Config::System;

=head1 NAME

configurator::Model::Config::System - Catalyst Model

=head1 DESCRIPTION

Catalyst Model.

=cut

use Moose;
use namespace::autoclean;
use Net::Netmask;

use pf::error qw(is_error is_success);
use pf::util;

extends 'Catalyst::Model';

=head1 METHODS

=over

=item _get_gateway_interface

=cut
sub _get_gateway_interface {
    my ( $self, $interfaces_ref, $gateway ) = @_;
    my $logger = Log::Log4perl::get_logger(__PACKAGE__);

    foreach my $interface ( sort keys(%$interfaces_ref) ) {
        next if ( !($interfaces_ref->{$interface}->{'running'}) );

        my $network = $interfaces_ref->{$interface}->{'network'};
        my $netmask = $interfaces_ref->{$interface}->{'netmask'};
        my $subnet  = new Net::Netmask($network, $netmask);

        return $interface if ( $subnet->match($gateway) );
    }

    return;
}

=item _inject_default_route

=cut
sub _inject_default_route {
    my ( $self, $gateway ) = @_;
    my $logger = Log::Log4perl::get_logger(__PACKAGE__);

    my $status;

# Need to add error handling here...
    my $cmd = "route del default";
    pf_run($cmd);
    $cmd = "route add default gw $gateway";
    pf_run($cmd);
    return 1;
#    my $cmd = "route add default gw $gateway";
#    eval { $status = pf_run($cmd) };
#    if ( $@ || !$status ) {
#        return $STATUS::INTERNAL_SERVER_ERROR;
#    }
#
#    return $STATUS::OK;
}

=item write_network_persistent

=cut
sub write_network_persistent {
    my ( $self, $interfaces_ref, $gateway ) = @_;
    my $logger = Log::Log4perl::get_logger(__PACKAGE__);

    my ($status, $status_msg, $systemObj);

    # Check if gateway is valid
    my $gateway_interface = $self->_get_gateway_interface($interfaces_ref, $gateway);
    if ( !$gateway_interface ) {
        $status_msg = "Invalid gateway. Doesn't belong to any running and configured interface";
        $logger->error("$status_msg");
        return ($STATUS::INTERNAL_SERVER_ERROR, $status_msg);
    }

    # Inject gateway for live usage
    if ( !$self->_inject_default_route($gateway) ) {
        $status_msg = "Error while injecting gateway on system. See server side logs for details";
        $logger->error("$status_msg");
        return ($STATUS::INTERNAL_SERVER_ERROR, $status_msg);
    }
    
    # Instantiate an object for the correct OS
    ($status, $systemObj) = configurator::Model::Config::SystemFactory->getSystem();
    return ($status, $systemObj) if ( is_error($status) );

    # Write persistent network configurations
    ($status, $status_msg) = $systemObj->writeNetworkConfigs($interfaces_ref, $gateway, $gateway_interface);
    return ($status, $status_msg) if ( is_error($status) );

    $status_msg = "Persistent network configurations successfully written";
    $logger->info("$status_msg");
    return ($STATUS::OK, $status_msg);
}


package configurator::Model::Config::SystemFactory;

=back

=head2 NAME

configurator::Model::Config::SystemFactory

=head2 DESCRIPTION

Moose class.

=cut

use Moose;

=head2 METHODS

=over

=item _checkOs

Checks running operating system

=cut
sub _checkOs {
    my ( $self ) = @_;

    # Default to undef
    my $os;

    # RedHat and derivatives
    $os = "RHEL" if ( -e "/etc/redhat-release" );
    # Debian and derivatives
    $os = "Debian" if ( -e "/etc/debian_version" );

    return $os;        
}

=item getSystem

Obtain a system object suited for your system.

=cut
sub getSystem {
    my ( $self ) = @_;
    my $logger = Log::Log4perl::get_logger(__PACKAGE__);

    my $status_msg;

    my $os = $self->_checkOs();

    if (defined($os)) {
        my $system = "configurator::Model::Config::System::$os";
        my $systemObj = $system->new();
        $logger->info("Instantiate a new object of type $os");
        return ($STATUS::OK, $systemObj);
    }

    $status_msg = "This OS is not supported by PacketFence";
    $logger->error("$status_msg | Cannot instantiate an object of this type");

    return ($STATUS::NOT_IMPLEMENTED, $status_msg);
}


package configurator::Model::Config::System::Role;

=back

=head2 NAME

configurator::Model::Config::System::Role

=head2 DESCRIPTION

Moose class implemeting roles.

=cut

use Moose::Role;

requires qw(writeNetworkConfigs);


package configurator::Model::Config::System::RHEL;

=head3 NAME

configurator::Model::Config::System::RHEL

=head3 DESCRIPTION

Moose class derivated from role for OS specific methods

=cut

use Moose;

with 'configurator::Model::Config::System::Role';

our $_network_conf_dir    = "/etc/sysconfig/";
our $_interfaces_conf_dir = "network-scripts/";
our $_network_conf_file   = "network";
our $_interface_conf_file = "ifcfg-";

=head3 METHODS

=over

=item writeNetworkConfigs

=cut
sub writeNetworkConfigs {
    my ( $this, $interfaces_ref, $gateway, $gateway_interface ) = @_;
    my $logger = Log::Log4perl::get_logger(__PACKAGE__);

    my $status_msg;

    foreach my $interface ( sort keys(%$interfaces_ref) ) {
        next if ( !($interfaces_ref->{$interface}->{'running'}) );

        my $vars = {
            logical_name    => $interface,
            vlan_device     => $interfaces_ref->{$interface}->{'vlan'},
            hwaddr          => $interfaces_ref->{$interface}->{'hwaddress'},
            ipaddr          => $interfaces_ref->{$interface}->{'ipaddress'},
            netmask         => $interfaces_ref->{$interface}->{'netmask'},
        };

        my $template = Template->new({
            INCLUDE_PATH    => "/usr/local/pf/html/configurator/root/interface",
            OUTPUT_PATH     => $_network_conf_dir.$_interfaces_conf_dir,
        });
        $template->process( "interface_rhel.tt", $vars, $_interface_conf_file.$interface );

        if ( $template->error() ) {
            $status_msg = "Error while writing system network interfaces configuration";
            $logger->error("$status_msg");
            return ($STATUS::INTERNAL_SERVER_ERROR, $status_msg);
        } 
    }

    if ( !(-e $_network_conf_dir.$_network_conf_file) ) {
        $status_msg = "Error while writing system's default gateway";
        $logger->error($status_msg ." | ". $_network_conf_dir.$_network_conf_file ." don't exists");
        return ($STATUS::INTERNAL_SERVER_ERROR, $status_msg);
    }

    open IN, '<', $_network_conf_dir.$_network_conf_file;
    my @content = <IN>;
    close IN;

    @content = grep !/^GATEWAY=/, @content;

    open OUT, '>', $_network_conf_dir.$_network_conf_file;
    print OUT @content;
    print OUT "GATEWAY=$gateway";
    close OUT;

    $logger->info("System network configurations successfully written");
    return $STATUS::OK;
}


package configurator::Model::Config::System::Debian;

=back

=head3 NAME

configurator::Model::Config::System::Debian

=head3 DESCRIPTION

Moose class derivated from role for OS specific methods

=cut

use Moose;

with 'configurator::Model::Config::System::Role';

our $_network_conf_dir    = "/etc/network/";
our $_network_conf_file   = "interfaces";

=head3 METHODS

=over

=item writeNetworkConfigs

=cut
sub writeNetworkConfigs {
    my ( $this, $interfaces_ref, $gateway, $gateway_interface ) = @_;
    my $logger = Log::Log4perl::get_logger(__PACKAGE__);

    my $status_msg;

    my $vars = {
        interfaces          => $interfaces_ref,
        gateway             => $gateway,
        gateway_interface   => $gateway_interface,
    };

    my $template = Template->new({
        INCLUDE_PATH    => "/usr/local/pf/html/configurator/root/interface",
        OUTPUT_PATH     => $_network_conf_dir,
    });
    $template->process( "interface_debian.tt", $vars, $_network_conf_file ) || $logger->error($template->error());

    if ( $template->error() ) {
        $status_msg = "Error while writing system network interfaces configuration";
        $logger->error("$status_msg");
        return ($STATUS::INTERNAL_SERVER_ERROR, $status_msg);
    }

    $logger->info("System network configurations successfully written");
    return $STATUS::OK;
}

=back

=head1 AUTHORS

Olivier Bilodeau <obilodeau@inverse.ca>

Derek Wuelfrath <dwuelfrath@inverse.ca>

=head1 COPYRIGHT

Copyright (C) 2012 Inverse inc.

=head1 LICENSE

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301,
USA.

=cut

__PACKAGE__->meta->make_immutable;

1;