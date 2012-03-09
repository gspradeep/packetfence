package pf::pfcmd::report;
=head1 NAME

pf::pfcmd::report - all about reports

=cut

=head1 DESCRIPTION

TBD

=head1 CONFIGURATION AND ENVIRONMENT

Read the F<pf.conf> configuration file.

=cut

use strict;
use warnings;
use Log::Log4perl;

use constant REPORT => 'pfcmd::report';

BEGIN {
    use Exporter ();
    our ( @ISA, @EXPORT );
    @ISA    = qw(Exporter);
    @EXPORT = qw(
        $report_db_prepared
        report_db_prepare

        report_os_all
        report_os_active
        report_osclass_all
        report_osclass_active
        report_active_all
        report_inactive_all
        report_unregistered_active
        report_unregistered_all
        report_active_reg
        report_registered_all
        report_registered_active
        report_openviolations_all
        report_openviolations_active
        report_connectiontype_all
        report_connectiontype_active
        report_connectiontypereg_all
        report_connectiontypereg_active
        report_ssid_all
        report_ssid_active
        report_statics_all
        report_statics_active
        report_unknownprints_all
        report_unknownprints_active
        report_unknownuseragents_all
        report_unknownuseragents_active

        translate_connection_type
    );
}

use pf::config;
use pf::db;
use pf::util;

# The next two variables and the _prepare sub are required for database handling magic (see pf::db)
our $report_db_prepared = 0;
# in this hash reference we hold the database statements. We pass it to the query handler and he will repopulate
# the hash if required
our $report_statements = {};

=head1 SUBROUTINES

TODO: list incomplete

=over

=cut
sub report_db_prepare {
    my $logger = Log::Log4perl::get_logger('pf::pfcmd::report');

    $report_statements->{'report_inactive_all_sql'} = get_db_handle()->prepare(
        qq [ select n.mac,pid,detect_date,regdate,lastskip,status,user_agent,computername,notes,last_arp,last_dhcp,o.description as os from node n LEFT JOIN dhcp_fingerprint d ON n.dhcp_fingerprint=d.fingerprint LEFT JOIN os_type o ON o.os_id=d.os_id where n.mac not in (select i.mac from iplog i where i.end_time=0 or i.end_time > now()) ]);

    $report_statements->{'report_active_all_sql'} = get_db_handle()->prepare(
        qq [ select n.mac,ip,start_time,pid,detect_date,regdate,lastskip,status,user_agent,computername,notes,last_arp,last_dhcp,o.description as os from (node n,iplog i) LEFT JOIN dhcp_fingerprint d ON n.dhcp_fingerprint=d.fingerprint LEFT JOIN os_type o ON o.os_id=d.os_id where i.mac=n.mac and (i.end_time=0 or i.end_time > now()) ]);

    $report_statements->{'report_unregistered_all_sql'} = get_db_handle()->prepare(
        qq [ select n.mac,pid,detect_date,regdate,lastskip,status,user_agent,computername,notes,last_arp,last_dhcp,o.description as os FROM node n LEFT JOIN dhcp_fingerprint d ON n.dhcp_fingerprint=d.fingerprint LEFT JOIN os_type o ON o.os_id=d.os_id where n.status='unreg' ]);

    $report_statements->{'report_unregistered_active_sql'} = get_db_handle()->prepare(
        qq [ select n.mac,pid,detect_date,regdate,lastskip,status,user_agent,computername,notes,last_arp,last_dhcp,o.description as os FROM (node n,iplog i) LEFT JOIN dhcp_fingerprint d ON n.dhcp_fingerprint=d.fingerprint LEFT JOIN os_type o ON o.os_id=d.os_id where n.status='unreg' and i.mac=n.mac and (i.end_time=0 or i.end_time > now()) ]);

    $report_statements->{'report_registered_all_sql'} = get_db_handle()->prepare(
        qq [ select n.mac,pid,detect_date,regdate,lastskip,status,user_agent,computername,notes,last_arp,last_dhcp,o.description as os FROM node n LEFT JOIN dhcp_fingerprint d ON n.dhcp_fingerprint=d.fingerprint LEFT JOIN os_type o ON o.os_id=d.os_id where n.status='reg' ]);

    $report_statements->{'report_registered_active_sql'} = get_db_handle()->prepare(
        qq [ select n.mac,pid,detect_date,regdate,lastskip,status,user_agent,computername,notes,last_arp,last_dhcp,o.description as os FROM (node n,iplog i) LEFT JOIN dhcp_fingerprint d ON n.dhcp_fingerprint=d.fingerprint LEFT JOIN os_type o ON o.os_id=d.os_id where n.status='reg' and i.mac=n.mac and (i.end_time=0 or i.end_time > now()) ]);

    $report_statements->{'report_os_active_sql'} = get_db_handle()->prepare(
        qq [ select o.description,n.dhcp_fingerprint,count(*) as count,ROUND(COUNT(*)/(SELECT COUNT(*) FROM node)*100,1) as percent FROM (node n,iplog i) LEFT JOIN dhcp_fingerprint d ON n.dhcp_fingerprint=d.fingerprint LEFT JOIN os_type o ON o.os_id=d.os_id where n.mac=i.mac and (i.end_time=0 or i.end_time > now()) group by o.description order by percent desc ]);

    $report_statements->{'report_os_all_sql'} = get_db_handle()->prepare(
        qq [select o.description,n.dhcp_fingerprint,count(*) as count,ROUND(COUNT(*)/(SELECT COUNT(*) FROM node)*100,1) as percent FROM node n LEFT JOIN dhcp_fingerprint d ON n.dhcp_fingerprint=d.fingerprint LEFT JOIN os_type o ON o.os_id=d.os_id group by o.description order by percent desc ]);

    $report_statements->{'report_osclass_all_sql'} = get_db_handle()->prepare(
        qq [ select c.description,count(*) as count,ROUND(COUNT(*)/(SELECT COUNT(*) FROM node)*100,1) as percent from node n LEFT JOIN dhcp_fingerprint d ON n.dhcp_fingerprint=d.fingerprint left join os_mapping m on m.os_type=d.os_id left join os_class c on m.os_class=c.class_id group by c.description order by percent desc ]);

    $report_statements->{'report_osclass_active_sql'} = get_db_handle()->prepare(
        qq [ select c.description,count(*) as count,ROUND(COUNT(*)/(SELECT COUNT(*) FROM node,iplog where node.mac=iplog.mac and (iplog.end_time=0 or iplog.end_time > now()))*100,1) as percent from (node n,iplog i) LEFT JOIN dhcp_fingerprint d ON n.dhcp_fingerprint=d.fingerprint left join os_mapping m on m.os_type=d.os_id left join os_class c on m.os_class=c.class_id where n.mac=i.mac and (i.end_time=0 or i.end_time > now()) group by c.description order by percent desc ]);

    $report_statements->{'report_unknownprints_all_sql'} = get_db_handle()->prepare(
        qq [SELECT mac,dhcp_fingerprint,computername,user_agent FROM node WHERE dhcp_fingerprint NOT IN (SELECT fingerprint FROM dhcp_fingerprint) and dhcp_fingerprint!=0 ORDER BY dhcp_fingerprint, mac ]);

    $report_statements->{'report_unknownprints_active_sql'} = get_db_handle()->prepare(
        qq [SELECT node.mac,dhcp_fingerprint,computername,user_agent FROM node,iplog WHERE dhcp_fingerprint NOT IN (SELECT fingerprint FROM dhcp_fingerprint) and dhcp_fingerprint!=0 and node.mac=iplog.mac and (iplog.end_time=0 or iplog.end_time > now()) ORDER BY dhcp_fingerprint, mac]);

    $report_statements->{'report_statics_all_sql'} = get_db_handle()->prepare(
        qq [SELECT * FROM node WHERE dhcp_fingerprint="" OR dhcp_fingerprint IS NULL]);

    $report_statements->{'report_statics_active_sql'} = get_db_handle()->prepare(
        qq [SELECT * FROM node,iplog WHERE (dhcp_fingerprint="" OR dhcp_fingerprint IS NULL) AND node.mac=iplog.mac and (iplog.end_time=0 or iplog.end_time > now()) ]);

    $report_statements->{'report_openviolations_all_sql'} = get_db_handle()->prepare(
        qq [SELECT n.pid as owner, n.mac as mac, v.status as status, v.start_date as start_date, c.description as violation from violation v LEFT JOIN node n ON v.mac=n.mac LEFT JOIN class c on c.vid=v.vid WHERE v.status="open" order by n.pid ]);

    $report_statements->{'report_openviolations_active_sql'} = get_db_handle()->prepare(
        qq [SELECT n.pid as owner, n.mac as mac, v.status as status, v.start_date as start_date, c.description as violation from (violation v, iplog i) LEFT JOIN node n ON v.mac=n.mac LEFT JOIN class c on c.vid=v.vid WHERE v.status="open" and n.mac=i.mac and (i.end_time=0 or i.end_time > now()) order by n.pid ]);

    $report_statements->{'report_unknownuseragents_all_sql'} = get_db_handle()->prepare(qq[
        SELECT n.user_agent, nu.browser, nu.os, n.computername, o.description, n.dhcp_fingerprint
        FROM node as n
            JOIN node_useragent AS nu USING (mac) 
            LEFT JOIN dhcp_fingerprint d ON n.dhcp_fingerprint=d.fingerprint 
            LEFT JOIN os_type o ON o.os_id=d.os_id
        WHERE (nu.browser IS NULL OR nu.os IS NULL) AND n.user_agent != ''
    ]);

    $report_statements->{'report_unknownuseragents_active_sql'} = get_db_handle()->prepare(qq[
        SELECT n.user_agent, nu.browser, nu.os, n.computername, o.description, n.dhcp_fingerprint
        FROM node as n
            JOIN node_useragent AS nu USING (mac) 
            LEFT JOIN dhcp_fingerprint d ON n.dhcp_fingerprint=d.fingerprint 
            LEFT JOIN os_type o ON o.os_id=d.os_id
            LEFT JOIN iplog USING (mac)
        WHERE (nu.browser IS NULL OR nu.os IS NULL) AND n.user_agent != '' 
            AND (iplog.end_time=0 OR iplog.end_time > now())
    ]);

    $report_statements->{'report_connectiontype_all_sql'} = get_db_handle()->prepare(qq [
        SELECT connection_type, count(*) as connections, ROUND(COUNT(*)/
            (SELECT COUNT(*) FROM locationlog 
                INNER JOIN node ON node.mac=locationlog.mac WHERE locationlog.end_time IS NULL)*100,1
            ) AS percent 
        FROM locationlog INNER JOIN node ON node.mac=locationlog.mac 
        WHERE locationlog.end_time IS NULL
        GROUP BY connection_type
    ]);

    $report_statements->{'report_connectiontype_active_sql'} = get_db_handle()->prepare(qq[
        SELECT connection_type,count(*) as connections, 
            ROUND( COUNT(*) / 
                (SELECT COUNT(*) FROM locationlog INNER JOIN node ON node.mac=locationlog.mac 
                    INNER JOIN iplog ON node.mac=iplog.mac 
                    WHERE iplog.end_time = 0 OR iplog.end_time > now() AND locationlog.end_time IS NULL
                )*100,1
            ) AS percent 
        FROM locationlog INNER JOIN node ON node.mac=locationlog.mac INNER JOIN iplog ON node.mac=iplog.mac 
        WHERE iplog.end_time = 0 OR iplog.end_time > now() AND locationlog.end_time IS NULL 
        GROUP BY connection_type
    ]);
   
    $report_statements->{'report_connectiontypereg_all_sql'} = get_db_handle()->prepare(qq[
        SELECT connection_type, count(*) as connections, 
            ROUND( COUNT(*) / 
                (SELECT COUNT(*) FROM locationlog INNER JOIN node ON node.mac=locationlog.mac 
                    WHERE node.status = "reg" AND locationlog.end_time IS NULL
                )*100,1
            ) AS percent 
        FROM locationlog INNER JOIN node ON node.mac=locationlog.mac 
        WHERE node.status = "reg" AND locationlog.end_time IS NULL 
        GROUP BY connection_type
    ]);

    $report_statements->{'report_connectiontypereg_active_sql'} = get_db_handle()->prepare(qq[
        SELECT connection_type, count(*) as connections, 
            ROUND( COUNT(*) / 
                (SELECT COUNT(*) FROM locationlog 
                    INNER JOIN node ON node.mac=locationlog.mac INNER JOIN iplog ON node.mac=iplog.mac 
                    WHERE node.status = "reg" AND (iplog.end_time =0 OR iplog.end_time > now()) 
                        AND locationlog.end_time IS NULL
                )*100,1
            ) AS percent 
        FROM locationlog INNER JOIN node ON node.mac=locationlog.mac INNER JOIN iplog ON node.mac=iplog.mac 
        WHERE node.status = "reg" AND (iplog.end_time = 0 OR iplog.end_time > now()) AND locationlog.end_time IS NULL 
        GROUP BY connection_type
    ]);

    $report_statements->{'report_ssid_all_sql'} = get_db_handle()->prepare(qq [
        SELECT ssid,count(*) as nodes, ROUND(COUNT(*)/
            (SELECT COUNT(*) 
                FROM locationlog
                    INNER JOIN node ON node.mac=locationlog.mac AND locationlog.end_time IS NULL
                WHERE ssid != "")
            *100,1) as percent 
        FROM locationlog 
           INNER JOIN node ON node.mac=locationlog.mac AND locationlog.end_time IS NULL
        WHERE ssid != ""
        GROUP BY ssid 
        ORDER BY nodes
    ]);

    $report_statements->{'report_ssid_active_sql'} = get_db_handle()->prepare(qq [
       SELECT ssid,count(*) as nodes, ROUND(COUNT(*)/
           (SELECT COUNT(*) 
                FROM locationlog 
                    INNER JOIN node ON node.mac=locationlog.mac AND locationlog.end_time IS NULL
                    INNER JOIN iplog ON node.mac=iplog.mac 
                WHERE ssid != "" AND (iplog.end_time=0 OR iplog.end_time > now())
           )*100,1) as percent 
       FROM locationlog 
           INNER JOIN node ON node.mac=locationlog.mac AND locationlog.end_time IS NULL
           INNER JOIN iplog ON node.mac=iplog.mac 
       WHERE ssid != "" AND (iplog.end_time=0 OR iplog.end_time > now()) 
       GROUP BY ssid 
       ORDER BY nodes
    ]);

    $report_db_prepared = 1;
    return 1;
}

sub report_os_all {

    my @data    = db_data(REPORT, $report_statements, 'report_os_all_sql');
    my $statics = scalar(db_data(REPORT, $report_statements, 'report_statics_all_sql'));
    my $total   = 0;
    my @return_data;

    foreach my $record (@data) {
        $total += $record->{'count'};
    }
    foreach my $record (@data) {
        if ( !$record->{'description'} ) { #this includes static and unknown prints
            $record->{'description'} = 'Unknown DHCP Fingerprint';
            if ( $statics > 0 ) {
                $record->{'count'} -= $statics;
                $record->{'percent'} = sprintf("%.1f", ( $record->{'count'} / $total ) * 100 );

                my $static_percent = sprintf( "%.1f", ( $statics / $total ) * 100 );
                push @return_data,
                    {
                    description => "Probable Static IP(s)",
                    percent     => $static_percent,
                    count       => $statics
                    };
                
            }
        }
        if ( $record->{'count'} > 0 ) {
            push @return_data, $record;
        }
    }

    push @return_data, { description => "Total", percent => "100", count => $total };
    return (@return_data);
}

sub report_os_active {
    my @data    = db_data(REPORT, $report_statements, 'report_os_active_sql');
    my $statics = scalar(db_data(REPORT, $report_statements, 'report_statics_active_sql'));
    my $total   = 0;
    my @return_data;

    foreach my $record (@data) {
        $total += $record->{'count'};
    }

    foreach my $record (@data) {
        if ( !$record->{'description'} ) { #this includes static and unknown prints
            $record->{'description'} = 'Unknown DHCP Fingerprint';
            if ( $statics > 0 ) {
                $record->{'count'} -= $statics;
                $record->{'percent'} = sprintf("%.1f", ( $record->{'count'} / $total ) * 100 );

                my $static_percent = sprintf( "%.1f", ( $statics / $total ) * 100 );
                push @return_data,
                    {
                    description => "Probable Static IP(s)",
                    percent     => $static_percent,
                    count       => $statics
                    };

            }
        }
        if ( $record->{'count'} > 0 ) {
            push @return_data, $record;
        }
    }

    push @return_data, { description => "Total", percent => "100", count => $total };
    return (@return_data);
}

sub report_osclass_all {

    my @data    = db_data(REPORT, $report_statements, 'report_osclass_all_sql');
    my $statics = scalar(db_data(REPORT, $report_statements, 'report_statics_all_sql'));
    my $total   = 0;
    my @return_data;

    foreach my $record (@data) {
        $total += $record->{'count'};
    }

    foreach my $record (@data) {
        if ( !$record->{'description'} ) { #this includes static and unknown prints
            $record->{'description'} = 'Unknown DHCP Fingerprint';
            if ( $statics > 0 ) {
                $record->{'count'} -= $statics;
                $record->{'percent'} = sprintf("%.1f", ( $record->{'count'} / $total ) * 100 );

                my $static_percent = sprintf( "%.1f", ( $statics / $total ) * 100 );
                push @return_data,
                    {
                    description => "Probable Static IP(s)",
                    percent     => $static_percent,
                    count       => $statics
                    };

            }
        }
        if ( $record->{'count'} > 0 ) {
            push @return_data, $record;
        }
    }

    push @return_data, { description => "Total", percent => "100", count => $total };
    return (@return_data);
}

sub report_osclass_active {

    my @data    = db_data(REPORT, $report_statements, 'report_osclass_active_sql');
    my $statics = scalar(db_data(REPORT, $report_statements, 'report_statics_active_sql'));
    my $total   = 0;
    my @return_data;

    foreach my $record (@data) {
        $total += $record->{'count'};
    }

    foreach my $record (@data) {
        if ( !$record->{'description'} ) { #this includes static and unknown prints
            $record->{'description'} = 'Unknown DHCP Fingerprint';
            if ( $statics > 0 ) {
                $record->{'count'} -= $statics;
                $record->{'percent'} = sprintf("%.1f", ( $record->{'count'} / $total ) * 100 );

                my $static_percent = sprintf( "%.1f", ( $statics / $total ) * 100 );
                push @return_data,
                    {
                    description => "Probable Static IP(s)",
                    percent     => $static_percent,
                    count       => $statics
                    };

            }
        }
        if ( $record->{'count'} > 0 ) {
            push @return_data, $record;
        }
    }
    return (@return_data);
}

sub report_active_all {
    return db_data(REPORT, $report_statements, 'report_active_all_sql');
}

sub report_inactive_all {
    return db_data(REPORT, $report_statements, 'report_inactive_all_sql');
}

sub report_unregistered_active {
    return db_data(REPORT, $report_statements, 'report_unregistered_active_sql');
}

sub report_unregistered_all {
    return db_data(REPORT, $report_statements, 'report_unregistered_all_sql');
}

sub report_active_reg {
    return db_data(REPORT, $report_statements, 'report_registered_active_sql');
}

sub report_registered_all {
    return db_data(REPORT, $report_statements, 'report_registered_all_sql');
}

sub report_registered_active {
    return db_data(REPORT, $report_statements, 'report_registered_active_sql');
}

sub report_openviolations_all {
    return db_data(REPORT, $report_statements, 'report_openviolations_all_sql');
}

sub report_openviolations_active {
    return db_data(REPORT, $report_statements, 'report_openviolations_active_sql');
}

sub report_statics_all {
    return translate_connection_type(db_data(REPORT, $report_statements, 'report_statics_all_sql'));
}

sub report_statics_active {
    return translate_connection_type(db_data(REPORT, $report_statements, 'report_statics_active_sql'));
}

sub report_unknownprints_all {
    my @data = db_data(REPORT, $report_statements, 'report_unknownprints_all_sql');
    foreach my $datum (@data) {
        $datum->{'vendor'} = oui_to_vendor( $datum->{'mac'} );
    }
    return (@data);
}

sub report_unknownprints_active {
    my @data = db_data(REPORT, $report_statements, 'report_unknownprints_active_sql');
    foreach my $datum (@data) {
        $datum->{'vendor'} = oui_to_vendor( $datum->{'mac'} );
    }
    return (@data);
}

sub report_unknownuseragents_all {
    return db_data(REPORT, $report_statements, 'report_unknownuseragents_all_sql');
}

sub report_unknownuseragents_active {
    return db_data(REPORT, $report_statements, 'report_unknownuseragents_active_sql');
}

=item * report_connectiontype_all

Reporting - Connections by connection type and user status for all nodes

=cut
sub report_connectiontype_all {
    my @data    = db_data(REPORT, $report_statements, 'report_connectiontype_all_sql');
    my $total   = 0;
    my @return_data;

    foreach my $record (@data) {
        $total += $record->{'connections'};
 
        if ( $record->{'connections'} > 0 ) {
            push @return_data, $record;
        }

    }
    @return_data = translate_connection_type(@return_data);
    push @return_data, { connection_type => "Total", percent => "100", connections => $total };
    return (@return_data);
}

=item * report_connectiontype_active

Reporting - Connections by connection type and user status for all active nodes

=cut
sub report_connectiontype_active {
    my @data    = db_data(REPORT, $report_statements, 'report_connectiontype_active_sql');
    my $total   = 0;
    my @return_data;

    foreach my $record (@data) {
        $total += $record->{'connections'};

        if ( $record->{'connections'} > 0 ) {
            push @return_data, $record;
        }

    }
    @return_data = translate_connection_type(@return_data);
    push @return_data, { connection_type => "Total", percent => "100", connections => $total };
    return (@return_data);
}

=item * report_connectiontypereg_all

Reporting - Connections by connection type and user status for all nodes (registered users)

=cut
sub report_connectiontypereg_all {
    my @data    = db_data(REPORT, $report_statements, 'report_connectiontypereg_all_sql');
    my $total   = 0;
    my @return_data;

    foreach my $record (@data) {
        $total += $record->{'connections'};

        if ( $record->{'connections'} > 0 ) {
            push @return_data, $record;
        }

    }
    @return_data = translate_connection_type(@return_data);
    push @return_data, { connection_type => "Total", percent => "100", connections => $total };
    return (@return_data);
}

=item * report_connectiontypereg_active

Reporting - Connections by connection type and user status for all active nodes (registered users)

=cut
sub report_connectiontypereg_active {
    my @data    = db_data(REPORT, $report_statements, 'report_connectiontypereg_active_sql');
    my $total   = 0;
    my @return_data;

    foreach my $record (@data) {
        $total += $record->{'connections'};

        if ( $record->{'connections'} > 0 ) {
            push @return_data, $record;
        }

    }
    @return_data = translate_connection_type(@return_data);
    push @return_data, { connection_type => "Total", percent => "100", connections => $total };
    return (@return_data);
}

=item * report_ssid_all

Reporting - Connections by SSID for all nodes regardless of the status

=cut
sub report_ssid_all {
    my @data    = db_data(REPORT, $report_statements, 'report_ssid_all_sql');
    my $total   = 0;
    my @return_data;

    foreach my $record (@data) {
        $total += $record->{'nodes'};

        if ( $record->{'nodes'} > 0 ) {
            push @return_data, $record;
        }

    }

    push @return_data, { ssid => "Total", percent => "100", nodes => $total };
    return (@return_data);
}

=item * report_ssid_active

Reporting - Connections by SSID for all active nodes (reg/unreg)

=cut
sub report_ssid_active {
    my @data    = db_data(REPORT, $report_statements, 'report_ssid_active_sql');
    my $total   = 0;
    my @return_data;

    foreach my $record (@data) {
        $total += $record->{'nodes'};

        if ( $record->{'nodes'} > 0 ) {
            push @return_data, $record;
        }

    }

    push @return_data, { ssid => "Total", percent => "100", nodes => $total };
    return (@return_data);
}

=item * translate_connection_type

Translates connection_type database string into a human-understandable string

=cut
# TODO we can probably be more efficient than that by passing references and stuff
sub translate_connection_type {
    my (@data) = @_;
    my $logger = Log::Log4perl::get_logger('pf::pfcmd::report');

    # determine if we are translating connection_type or last_connection_type
    my $field;
    $field = 'connection_type' if (exists($data[0]->{'connection_type'}));
    $field = 'last_connection_type' if (exists($data[0]->{'last_connection_type'}));
    if (!defined($field)) {
        $logger->info("nothing to translate");
        return @data;
    }

    # change connection_type into its meaningful to humans counterpart
    foreach my $datum (@data) {

        my $conn_type = str_to_connection_type($datum->{$field});
        if (defined($conn_type)) {
            $datum->{$field} = $connection_type_explained{$conn_type};
        } else {
            $datum->{$field} = "UNKNOWN";
        }
    }
    return (@data);
}

=back

=head1 AUTHOR

David LaPorte <david@davidlaporte.org>

Kevin Amorin <kev@amorin.org>

Olivier Bilodeau <obilodeau@inverse.ca>

Francois Gaudreault <fgaudreault@inverse.ca>

=head1 COPYRIGHT

Copyright (C) 2005 David LaPorte

Copyright (C) 2005 Kevin Amorin

Copyright (C) 2010-2011 Inverse inc.

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

1;
# vim: set shiftwidth=4:
# vim: set expandtab:
# vim: set backspace=indent,eol,start: