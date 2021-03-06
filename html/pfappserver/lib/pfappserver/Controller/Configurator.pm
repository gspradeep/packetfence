package pfappserver::Controller::Configurator;

=head1 NAME

pfappserver::Controller::Configurator - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=cut

use strict;
use warnings;

use HTML::Entities;
use HTTP::Status qw(:constants is_error is_success);
use JSON;
use Moose;
use namespace::autoclean;

BEGIN {extends 'Catalyst::Controller'; }

# Define the order of the configurator steps.
# The id must match an action name.
my @steps = (
    { id          => 'enforcement',
      title       => 'Enforcement',
      description => 'Choose your enforcement mechanisms' },
    { id          => 'networks',
      title       => 'Networks',
      description => 'Configure network interfaces' },
    { id          => 'database',
      title       => 'Database',
      description => 'Configure MySQL' },
    { id          => 'configuration',
      title       => 'PacketFence',
      description => 'Configure various options' },
    { id          => 'admin',
      title       => 'Administration',
      description => 'Configure access to the admin interface' },
    { id          => 'services',
      title       => 'Confirmation',
      description => 'Start the services' }
);

=head1 SUBROUTINES

=head2 begin

Set the default view to pfappserver::View::Configurator.

=cut
sub begin :Private {
    my ( $self, $c ) = @_;
    $c->stash->{current_view} = 'Configurator';
}

=head2 index

=cut
sub index :Path :Args(0) {
    my ( $self, $c ) = @_;

    $c->response->redirect($c->uri_for($self->action_for($steps[0]->{id})));
}

=head2 object

Configurator controller dispatcher

=cut
sub object :Chained('/') :PathPart('configurator') :CaptureArgs(0) {
    my ( $self, $c ) = @_;

    $c->stash->{installation_type} = $c->model('Configurator')->checkForUpgrade();
    if( $c->stash->{installation_type} eq 'configuration' ) {
        my $admin_ip    = $c->model('PfConfigAdapter')->getWebAdminIp();
        my $admin_port  = $c->model('PfConfigAdapter')->getWebAdminPort();
        $c->log->info("Redirecting to admin interface https://$admin_ip:$admin_port");
        $c->response->redirect("https://$admin_ip:$admin_port");
    }

    $c->stash->{steps} = \@steps;
    $self->_next_step($c);

    if ($c->action->name() ne 'enforcement' &&
        (!exists($c->session->{enforcements}) || scalar($c->session->{enforcements}) == 0)) {
        # Defaults to inline mode if no mechanism has been chosen so far
        $c->session->{enforcements}->{inline} = 1;
    }
}

=head2 _next_step

Set the next step with respect to the current action.

=cut
sub _next_step :Private {
    my ( $self, $c ) = @_;

    my $i;
    for ($i = 0; $i <= $#steps; $i++) {
        last if ($steps[$i]->{id} eq $c->action->name);
    }

    $c->stash->{step_index} = $i + 1;
    $i++ if ($i < $#steps);
    $c->stash->{next_step} = $c->uri_for($steps[$i]->{id});
}

=head2 enforcement

Enforcement mechanisms (step 1)

=cut
sub enforcement :Chained('object') :PathPart('enforcement') :Args(0) {
    my ( $self, $c ) = @_;

    if ($c->request->method eq 'POST') {
        # Save parameters in user session
        my $data = decode_json($c->request->params->{json});
        $c->session(enforcements => {});
        map { $c->session->{enforcements}->{$_} = 1 } @{$data->{enforcements}};

        if (scalar @{$data->{enforcements}} == 0) {
            # Make sure at least one enforcement method is selected
            $c->response->status(HTTP_PRECONDITION_FAILED);
            $c->stash->{status_msg} = $c->loc("You must choose at least one enforcement mechanism.");
            delete $c->session->{completed}->{$c->action->name};
        }
        else {
            # Step passed validation
            $c->session->{completed}->{$c->action->name} = 1;
        }

        $c->stash->{current_view} = 'JSON';
    }
    elsif (!exists($c->session->{enforcements})) {
        # Detect chosen mechanisms from networks.conf
        my $interfaces_ref = $c->model('Interface')->get('all');
        my ($status, $interfaces_types) = $c->model('Config::Networks')->get_types($interfaces_ref);
        if (is_success($status)) {
            # If some interfaces are associated to a type, find the corresponding mechanism
            my @active_types = values %{$interfaces_types};
            $c->session(enforcements => {});
            my $mechanisms_ref = $c->model('Enforcement')->getAvailableMechanisms();
            foreach my $mechanism (@{$mechanisms_ref}) {
                my $mechanism_types = $c->model('Enforcement')->getAvailableTypes($mechanism);
                my %types_lookup;
                @types_lookup{@{$mechanism_types}} = (); # built lookup table
                foreach my $type (@active_types) {
                    if (exists $types_lookup{$type}) {
                        $c->session->{enforcements}->{$mechanism} = 1;
                        last;
                    }
                }
            }
        }

        if (exists($c->session->{enforcements}) && keys(%{$c->session->{enforcements}}) > 0) {
            $c->log->info("Detected mechanisms: " . join(', ', keys %{$c->session->{enforcements}}));
        }
        else {
            # Defaults to inline mode if no mechanism has been detected
            $c->session->{enforcements}->{inline} = 1;
        }
    }

}

=head2 networks

Network interfaces (step 2)

=cut
sub networks :Chained('object') :PathPart('networks') :Args(0) {
    my ( $self, $c ) = @_;

    if ($c->request->method eq 'POST') {
        # Save parameters in user session
        my $data = decode_json($c->request->params->{json});
        $c->session(gateway => $data->{gateway},
                    dns => $data->{dns});
        $c->stash(interfaces_types => $data->{interfaces_types});

        # Make sure all types for each enforcement is assigned to an interface
        # TODO: Shall we ignore disabled interfaces?
        my @selected_types = values %{$data->{interfaces_types}};
        my %seen;
        my @missing = ();
        @seen{@selected_types} = ( ); # build lookup table

        foreach my $enforcement (keys %{$c->session->{enforcements}}) {
            my $types_ref = $c->model('Enforcement')->getAvailableTypes($enforcement);
            foreach my $type (@{$types_ref}) {
                unless (exists $seen{$type} ||
                        $type eq 'other' ||
                        grep {$_ eq $c->loc($type)} @missing) {
                    push(@missing, $c->loc($type));
                }
            }
        }

        if (scalar @missing > 0) {
            $c->response->status(HTTP_PRECONDITION_FAILED);
            $c->stash->{status_msg} = $c->loc("You must assign an interface to the following types: [_1]", join(", ", @missing));
            delete $c->session->{completed}->{$c->action->name};
        }
        else {
            # Step passed validation
            $c->session->{completed}->{$c->action->name} = 1;
        }
        # TODO move IP validation to something provided by core (once in model I guess)
# XXX needs to check each interfaces in a loop for inline
#        elsif ($data->{interfaces_types}->{$interface} =~ /^inline$/i && $data->{dns} =~ /\d{1,3}\.\d{1,3}\.\d{1,3}.\d{1,3}/) {
#            # DNS must be set if in inline enforcement
#            $c->response->status(HTTP_PRECONDITION_FAILED);
#            $c->stash->{status_msg} = $c->loc(
#                "A valid DNS server must be provided for Inline enforcement. "
#                . "If you are unsure you can always put in your ISP's DNS or a global DNS like 4.2.2.1."
#            );
#            delete $c->session->{completed}->{$c->action->name};
#        }

        # Update networks.conf and pf.conf
        my $networksModel = $c->model('Config::Networks');
        my $configModel = $c->model('Config::Pf');
        foreach my $interface (keys %{$data->{interfaces_types}}) {
            my $interface_ref = $c->model('Interface')->get($interface)->{$interface};

            # we ignore interface type 'Other' (it basically means unsupported in configurator)
            next if ( $data->{interfaces_types}->{$interface} =~ /^other$/i );

            # we delete interface type 'None'
            if ( $data->{interfaces_types}->{$interface} =~ /^none$/i ) {
                $networksModel->delete($interface_ref->{network}) if ($networksModel->exist($interface_ref->{network}));
                $configModel->delete_interface($interface) if ($configModel->exist_interface($interface));
            }
            # otherwise we update pf.conf and networks.conf
            else {
                # we willingly silently ignore errors if interface already exists
                # TODO have a wrapper that does both?
                $configModel->create_interface($interface);
                $configModel->update_interface(
                    $interface,
                    $self->_prepare_interface_for_pfconf($interface, $interface_ref, $data->{interfaces_types}->{$interface})
                );

                # FIXME refactor that!
                # and we must create a network portion for the following types
                if ( $data->{interfaces_types}->{$interface} =~ /^vlan-isolation$|^vlan-registration$/i ) {
                    $networksModel->create($interface_ref->{network});
                    $networksModel->update(
                        $interface_ref->{network}, {
                            type => $data->{interfaces_types}->{$interface},
                            netmask => $interface_ref->{'netmask'},
                            # FIXME push these default values further down in the stack
                            # (into pf::config, pf::services, etc.)
                            gateway => $interface_ref->{'ipaddress'},
                            dns => $interface_ref->{'ipaddress'},
                            dhcp_start => Net::Netmask->new(@{$interface_ref}{qw(ipaddress netmask)})->nth(10),
                            dhcp_end => Net::Netmask->new(@{$interface_ref}{qw(ipaddress netmask)})->nth(-10),
                            dhcp_default_lease_time => 30,
                            dhcp_max_lease_time => 30,
                            named => 'enabled',
                            dhcpd => 'enabled',
                        }
                    );
                }
                elsif ( $data->{interfaces_types}->{$interface} =~ /^inline$/i ) {
                    $networksModel->create($interface_ref->{network});
                    $networksModel->update(
                        $interface_ref->{network}, {
                            type => $data->{interfaces_types}->{$interface},
                            netmask => $interface_ref->{'netmask'},
                            # FIXME push these default values further down in the stack 
                            # (into pf::config, pf::services, etc.)
                            gateway => $interface_ref->{'ipaddress'},
                            dns => $data->{'dns'},
                            dhcp_start => Net::Netmask->new(@{$interface_ref}{qw(ipaddress netmask)})->nth(10),
                            dhcp_end => Net::Netmask->new(@{$interface_ref}{qw(ipaddress netmask)})->nth(-10),
                            dhcp_default_lease_time => 24 * 60 * 60,
                            dhcp_max_lease_time => 24 * 60 * 60,
                            named => 'enabled',
                            dhcpd => 'enabled',
                        }
                    );
                }
                elsif ( $data->{interfaces_types}->{$interface} =~ /^management$/ ) {
                    # management interfaces must not appear in networks.conf
                    $networksModel->delete($interface_ref->{network}) if ($networksModel->exist($interface_ref->{network}));
                }
            }

            # Update the network interface configurations on system
            $c->model('Config::System')->write_network_persistent($c->model('Interface')->get('all'),
                                                                  $data->{'gateway'});
        }

        $c->stash->{current_view} = 'JSON';
    }
    else {
        $c->session->{gateway} = $c->model('Config::System')->getDefaultGateway if (!defined($c->session->{gateway}));

        my $interfaces_ref = $c->model('Interface')->get('all');
        $c->stash(interfaces => $interfaces_ref);
        $c->stash(types => $c->model('Enforcement')->getAvailableTypes([ keys %{$c->session->{'enforcements'}} ]));
        my ($status, $interfaces_types) = $c->model('Config::Networks')->get_types($interfaces_ref);
        if (is_success($status)) {
            $c->stash->{interfaces_types} = $self->_prepare_types_for_display($c, $interfaces_ref, $interfaces_types);
        }
        # $c->stash(gateway => ?)
        # $c->stash(dns => ?)
    }
}

=head2 _prepare_interface_for_pfconf

Process parameters to build a proper pf.conf interface section.

=cut
# TODO push hardcoded strings as constants (or re-use core constants)
# this might imply a rework of this out of the controller into the model
sub _prepare_interface_for_pfconf :Private {
    my ($self, $int, $int_model, $type) = @_;

    my $int_config_ref = {
        ip => $int_model->{'ipaddress'},
        mask => $int_model->{'netmask'},
    };

    # logic to match our awkward relationship between pf.conf's type and 
    # enforcement with networks.conf's type
    if ($type =~ /^vlan/i) {
        $int_config_ref->{'type'} = 'internal';
        $int_config_ref->{'enforcement'} = 'vlan';
    }
    elsif ($type =~ /^inline$/i) {
        $int_config_ref->{'type'} = 'internal';
        $int_config_ref->{'enforcement'} = 'inline';
    }
    else {
        # here we oversimplify a bit, type supports multivalues but it's 
        # out of scope for now
        $int_config_ref->{'type'} = $type;
    }

    return $int_config_ref;
}

=head2 _prepare_types_for_display

Process pf.conf's interface type and enforcement and networks.conf's type 
and present something that is friendly to the user.

=cut
# TODO push hardcoded strings as constants (or re-use core constants)
# this might imply a rework of this out of the controller into the model
sub _prepare_types_for_display :Private {
    my ($self, $c, $interfaces_ref, $interfaces_types_ref) = @_;

    my $display_int_types_ref;
#$DB::single=1;
    foreach my $interface (keys %$interfaces_ref) {
        # if the interface is in interfaces_types then take that value
        if (defined($interfaces_types_ref->{$interface})) {
            $display_int_types_ref->{$interface} = $interfaces_types_ref->{$interface};
        }
        # if the interface is not defined in networks.conf
        else {
            my ($status, $type) = $c->model('Config::Pf')->read_interface_value($interface, 'type');
            # if the interface is not defined in pf.conf
            if ( is_error($status) ) {
                $type = 'none';
            }
            # rely on pf.conf's info
            else {
                $type = ($type =~ /management|managed/i) ? 'management' : 'other';
            }
            $display_int_types_ref->{$interface} = $type;
        }
    }
    return $display_int_types_ref;
}

=head2 database

Database setup (step 3)

=cut
# FIXME this is not like we built the rest of pfappserver.. re-architect?
# the GET is expected to fail on first run, then the javascript calls it again and it should pass...
sub database :Chained('object') :PathPart('database') :Args(0) {
    my ( $self, $c ) = @_;
    
    # Default username if nothing else have already been entered (provide a pre-filled field)
    $c->session->{root_user} = 'root' if (!defined($c->session->{root_user}));

    # Check MySQLd status by fetching pid
    $c->stash->{mysqld_running} = 1 if ($c->model('Config::System')->check_mysqld_status() ne 0);

    if ($c->request->method eq 'GET') {
        # Check if the database and user exist
        my ($status, $result_ref) = $c->model('Config::Pf')->read_value(
            ['database.user', 'database.pass', 'database.db']
        );
        if (is_error($status)) {
            delete $c->session->{completed}->{$c->action->name};
            $c->log->warn("Could not read configuration: $result_ref");
            $c->detach();
        }

        $c->stash->{'db'} = $result_ref;
        # hash-slice assigning values to the list
        my ($pf_user, $pf_pass, $pf_db) = @{$result_ref}{qw/database.user database.pass database.db/};
        if ($pf_user && $pf_pass && $pf_db) {
            # throwing away result since we don't use it
            ($status) = $c->model('DB')->connect($pf_db, $pf_user, $pf_pass);
            if (is_error($status)) {
                delete $c->session->{completed}->{$c->action->name};
                $c->detach();
            }
        }

        # everything has been done successfully
        $c->session->{completed}->{$c->action->name} = 1;
    }
}

=head2 config

PacketFence minimal configuration (step 4)

=cut
sub configuration :Chained('object') :PathPart('configuration') :Args(0) {
    my ( $self, $c ) = @_;

    if ($c->request->method eq 'GET') {
        my ($status, $result_ref) = $c->model('Config::Pf')->read_value(
            ['general.domain', 'general.hostname', 'general.dhcpservers', 'alerting.emailaddr']
        );
        if (is_success($status)) {
            $c->stash->{'config'} = $result_ref;
        }
    }
    elsif ($c->request->method eq 'POST') {
        # Save configuration
        my ( $status, $message ) = (HTTP_OK);
        my $general_domain      = $c->request->params->{'general.domain'};
        my $general_hostname    = $c->request->params->{'general.hostname'};
        my $general_dhcpservers = $c->request->params->{'general.dhcpservers'};
        my $alerting_emailaddr  = $c->request->params->{'alerting.emailaddr'};

        unless ($general_domain && $general_hostname && $general_dhcpservers && $alerting_emailaddr) {
            ($status, $message) = ( HTTP_BAD_REQUEST, 'Some required parameters are missing.' );
        }
        if (is_success($status)) {
            my ( $status, $message ) = $c->model('Config::Pf')->update({
                'general.domain'      => $general_domain,
                'general.hostname'    => $general_hostname,
                'general.dhcpservers' => $general_dhcpservers,
                'alerting.emailaddr'  => $alerting_emailaddr
            });
            if (is_error($status)) {
                delete $c->session->{completed}->{$c->action->name};
            }

            # Update networks.conf file with correct domain-names for each networks
            my $networks_ref;
            ($status, $networks_ref) = $c->model('Config::Networks')->list_networks();
            foreach my $network ( @$networks_ref ) {
                my $type = $c->model('Config::Networks')->read_value($network, 'type');
                $c->model('Config::Networks')->update($network, {'domain-name' => $type . "." . $general_domain});
            }

        }
        if (is_error($status)) {
            $c->response->status($status);
            $c->stash->{status_msg} = $message;
        }
        else {
            $c->session->{completed}->{$c->action->name} = 1;
        }
        $c->stash->{current_view} = 'JSON';
    }
}

=head2 admin

Administrator account (step 5)

=cut
sub admin :Chained('object') :PathPart('admin') :Args(0) {
    my ( $self, $c ) = @_;

    if ($c->request->method eq 'POST') {
        my ($status, $message) = ( HTTP_OK );
        my $admin_user      = $c->request->params->{admin_user};
        my $admin_password  = $c->request->params->{admin_password};

        unless ( $admin_user && $admin_password ) {
            ($status, $message) = ( HTTP_BAD_REQUEST, 'Some required parameters are missing.' );
        }
        if ( is_success($status) ) {
            ($status, $message) = $c->model('Configurator')->createAdminUser($admin_user, $admin_password);
        }
        if ( is_success($status) ) {
            $c->session(admin_user => $admin_user);
            $c->session->{completed}->{$c->action->name} = 1;
        } else {
            delete $c->session->{admin_user};
            delete $c->session->{completed}->{$c->action->name};
            $c->response->status($status);
        }

        $c->stash->{status_msg} = $message;
        $c->stash->{current_view} = 'JSON';
    }
}

=head2 services

Confirmation and services launch (step 6)

=cut
sub services :Chained('object') :PathPart('services') :Args(0) {
    my ( $self, $c ) = @_;

    if ($c->request->method eq 'GET') {

        my $completed = $c->session->{completed};
        $c->stash->{completed} = 1;
        foreach my $step (@steps) {
            next if ($step->{id} eq $c->action->name); # Don't test the current action
            unless ($completed->{$step->{id}}) {
                $c->stash->{completed} = 0;
                last;
            }
        }
        if ($c->stash->{completed}) {
            my ($status, $error) = $c->model('PfConfigAdapter')->reloadConfiguration();
            if ( is_error($status) ) {
                $c->log->error("an error trying to reload the configuration");
                $c->response->status($status);
                $c->stash->{'error'} = $error;
                $c->detach();
            }
            $c->stash->{'admin_ip'} = $c->model('PfConfigAdapter')->getWebAdminIp();
            $c->stash->{'admin_port'} = $c->model('PfConfigAdapter')->getWebAdminPort();
        }

        my ($status, $services_status) = $c->model('Services')->status();
        if ( is_success($status) ) {
            $c->log->info("successfully listed services");
            $c->stash->{'services_status'} = $services_status;
        }
        if ( is_error($status) ) {
            $c->log->error("an error trying to list the services");
            $c->response->status($status);
            $c->stash->{'error'} = $services_status;
        }
    }

    # Start the services
    elsif ($c->request->method eq 'POST') {

        # actually try to start the services
        my ($status, $service_start_output) = $c->model('Services')->start();
        # if we detect an error later, we will be able to display the output
        # this will be done on the client side
        $c->stash->{'error'} = encode_entities($service_start_output);
        if ( is_error($status) ) {
            $c->response->status($status);
            $c->stash->{status_msg} = $service_start_output;
        }
        # success: list the services
        else {
            my ($status, $services_status) = $c->model('Services')->status();
            if ( is_success($status) ) {
                $c->log->info("successfully listed services");
                $c->stash->{'services'} = $services_status;
                # a service has failed to start if its status is 0
                my $start_failed = scalar(grep {$_ == 0} values %{$services_status}) > 0;
                if ($start_failed) {
                    $c->log->warn("some services were not started");
                }
                else {
                    $c->model('Configurator')->update_currently_at();
                }
            }
            else {
                $c->response->status($status);
                $c->log->info('problem trying to list the services');
                $c->stash->{status_msg} = $services_status;
            }
        }
        $c->stash->{current_view} = 'JSON';
    }
}

=head2 reset_password

Reset the root password (database)

=cut
sub reset_password :Path('reset_password') :Args(0) {
    my ( $self, $c ) = @_;

    my ($status, $message) = ( HTTP_OK );
    my $root_user      = $c->request->params->{root_user};
    my $root_password  = $c->request->params->{root_password_new};

    unless ( $root_user && $root_password ) {
        ($status, $message) = ( HTTP_BAD_REQUEST, 'Some required parameters are missing.' );
    }
    if ( is_success($status) ) {
        ($status, $message) = $c->model('DB')->secureInstallation($root_user, $root_password);
    }
    if ( is_error($status) ) {
        $c->response->status($status);
    }

    $c->stash->{status_msg} = $message;
    $c->stash->{current_view} = 'JSON';
}

=head1 AUTHORS

Derek Wuelfrath <dwuelfrath@inverse.ca>

Francis Lachapelle <flachapelle@inverse.ca>

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
