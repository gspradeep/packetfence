package pfappserver::Controller::Configuration;

=head1 NAME

pfappserver::Controller::Configuration - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=cut

use strict;
use warnings;

use Date::Parse;
use HTTP::Status qw(:constants is_error is_success);
use Moose;
use namespace::autoclean;
use POSIX;

use pf::authentication;
use pf::os;
# imported only for the $TIME_MODIFIER_RE regex. Ideally shouldn't be 
# imported but it's better than duplicating regex all over the place.
use pf::config;
use pfappserver::Form::Config::Pf;

BEGIN {extends 'Catalyst::Controller'; }

=head1 METHODS

=cut

=head2 auto

Allow only authenticated users

=cut

sub auto :Private {
    my ($self, $c) = @_;

    unless ($c->user_exists()) {
        $c->response->status(HTTP_UNAUTHORIZED);
        $c->response->location($c->req->referer);
        $c->stash->{template} = 'admin/unauthorized.tt';
        $c->detach();
        return 0;
    }

    return 1;
}

=head2 _format_section

=cut

sub _format_section :Private {
    my ($self, $entries_ref) = @_;

    for (my $i = 0; $i < scalar @{$entries_ref}; $i++) {
        my $entry_ref = $entries_ref->[$i];

        # Try to be smart. Description that refers to a comma-delimited list must be bigger.
        if ($entry_ref->{type} eq "text" && $entry_ref->{description} =~ m/comma-delimite/i) {
            $entry_ref->{type} = 'text-large';
        }

        # Value should always be defined for toggles (checkbox and select)
        elsif ($entry_ref->{type} eq "toggle") {
            $entry_ref->{value} = $entry_ref->{default_value} unless ($entry_ref->{value});
        }

        elsif ($entry_ref->{type} eq "date") {
            my $time = str2time($entry_ref->{value} || $entry_ref->{default_value});
            # Match date format of Form::Widget::Theme::Pf
            $entry_ref->{value} = POSIX::strftime("%Y-%m-%d", localtime($time));
        }

        # Limited formatting from text to html
        $entry_ref->{description} =~ s/</&lt;/g; # convert < to HTML entity
        $entry_ref->{description} =~ s/>/&gt;/g; # convert > to HTML entity
        $entry_ref->{description} =~ s/(\S*(&lt;|&gt;)\S*)\b/<code>$1<\/code>/g; # enclose strings that contain < or >
        $entry_ref->{description} =~ s/(\S+\.(html|tt|pm|pl|txt))\b(?!<\/code>)/<code>$1<\/code>/g; # enclose strings that ends with .html, .tt, etc
        $entry_ref->{description} =~ s/^ \* (.+?)$/<li>$1<\/li>/mg; # create list elements for lines beginning with " * "
        $entry_ref->{description} =~ s/(<li>.*<\/li>)/<ul>$1<\/ul>/s; # create lists from preceding substitution
        $entry_ref->{description} =~ s/\"([^\"]+)\"/<i>$1<\/i>/mg; # enclose strings surrounded by double quotes
        $entry_ref->{description} =~ s/(https?:\/\/\S+)/<a href="$1">$1<\/a>/g;
    }
}

=head2 _update_section

=cut

sub _update_section :Private {
    my ($self, $c, $form) = @_;

    my $entries_ref = $c->model('Config::Pf')->read($c->action->name);
    my $data = {};

    foreach my $section (keys %$form) {
        foreach my $field (keys %{$form->{$section}}) {
            $data->{$section.'.'.$field} = $form->{$section}->{$field};
        }
    }

    my ($status, $message) = $c->model('Config::Pf')->update($data);

    if (is_error($status)) {
        $c->response->status($status);
    }
    $c->stash->{status_msg} = $message;
    $c->stash->{current_view} = 'JSON';
}

=head2 _process_section

=cut

sub _process_section :Private {
    my ($self, $c) = @_;

    my ($params, $form);

    $c->stash->{section} = $c->action->name;
    $c->stash->{template} = 'configuration/section.tt';

    $params = $c->model('Config::Pf')->read($c->action->name);
    $self->_format_section($params);

    if ($c->request->method eq 'POST') {
        $form = pfappserver::Form::Config::Pf->new(ctx => $c,
                                                   section => $params);
        $form->process(params => $c->req->params);
        if ($form->has_errors) {
            $c->response->status(HTTP_BAD_REQUEST);
            $c->stash->{status_msg} = $form->field_errors; # TODO: localize error message
        }
        else {
            $self->_update_section($c, $form->value);
        }
    }
    else {
        $form = pfappserver::Form::Config::Pf->new(ctx => $c,
                                                   section => $params);
        $form->process;
        $c->stash->{form} = $form;
    }
}

=head2 index

=cut

sub index :Path :Args(0) {
    my ( $self, $c ) = @_;

    $c->response->redirect($c->uri_for($c->controller('Admin')->action_for('configuration'), ('general')));
    $c->detach();
}

=head2 general

=cut

sub general :Local {
    my ($self, $c) = @_;

    $self->_process_section($c);
}

=head2 network

=cut

sub network :Local {
    my ($self, $c) = @_;

    $self->_process_section($c);
}

=head2 proxies

=cut

sub proxies :Local {
    my ($self, $c) = @_;

    $self->_process_section($c);
}

=head2 trapping

=cut

sub trapping :Local {
    my ($self, $c) = @_;

    $self->_process_section($c);
}

=head2 registration

=cut

sub registration :Local {
    my ($self, $c) = @_;

    $self->_process_section($c);
}

=head2 authentication

=cut

sub authentication :Local {
    my ($self, $c) = @_;

    $c->forward('Controller::Authentication', 'index');
}


=head2 violations

=cut

sub violations :Local {
    my ( $self, $c ) = @_;

    $c->stash->{template} = 'configuration/violations.tt';

    my ($status, $result) = $c->model('Config::Violations')->read_violation('all');
    if (is_success($status)) {
        $c->stash->{violations} = $result;
    }
    if (is_error($status)) {
        $c->response->status($status);
        $c->stash->{status_msg} = $result;
        $c->stash->{current_view} = 'JSON';
    }
}

=head2 soh

=cut

sub soh :Local {
    my ( $self, $c ) = @_;

    $c->stash->{template} = 'configuration/soh.tt';

    my ($status, $result) = $c->model('SoH')->filters();
    if (is_success($status)) {
        $c->stash->{filters} = $result;

        ($status, $result) = $c->model('Config::Violations')->read_violation('all');
        if (is_success($status)) {
            $c->stash->{violations} = $result;
        }
    }
    if (is_error($status)) {
        $c->stash->{error} = $result;
    }
}


=head2 fingerprints

=cut
sub fingerprints : Local :Args(0) {
    my ( $self, $c ) = @_;
    my $action = $c->request->params->{'action'} || "";
    if($action eq 'update') {
        my ($status,$version_msg,$total) = update_dhcp_fingerprints_conf();
        $c->stash->{status_message} = "DHCP fingerprints updated via $dhcp_fingerprints_url to $version_msg\n" .  "$total DHCP fingerprints reloaded\n";
    } elsif ($action eq 'upload') {
    }
    $self->_list_items($c,'OS');
}

=head2 useragents

=cut
sub useragents :Local :Args(0) {
    my ( $self, $c ) = @_;
    $self->_list_items($c,'UserAgent');
}


sub _list_items {
    my ( $self, $c, $model_name ) = @_;
    my ($filter, $orderby, $orderdirection, $status, $result, $items_ref, $count);
    my $model = $c->model($model_name); 
    my $field_names = $model->field_names(); 
    my $page_num = $c->request->params->{'page_num'} || 1;
    my $per_page = $c->request->params->{'per_page'} || 25;
    my $limit_clause = "LIMIT " . (($page_num-1)*$per_page) . "," . $per_page;
    my %params = ( limit => $limit_clause );
    
    if (exists($c->req->params->{'filter'})) {
        $filter = $c->req->params->{'filter'};
        $params{'where'} = { type => 'any', like => $filter };
        $c->stash->{filter} = $filter;
    }
    if (exists($c->request->params->{'by'})) {
        $orderby = $c->request->params->{'by'};
        if (grep {$_ eq $orderby} (@$field_names)) {
            $orderdirection = $c->request->params->{'direction'};
            unless (grep {$_ eq $orderdirection} ('asc', 'desc')) {
                $orderdirection = 'asc';
            }
            $params{'orderby'} = "ORDER BY $orderby $orderdirection";
            $c->stash->{by} = $orderby;
            $c->stash->{direction} = $orderdirection;
        }
    }

    ($status, $result) = $model->search(%params);
    if (is_success($status)) {
        $items_ref = $result;
        ($status, $result) = $model->countAll(%params);
    }
    if (is_success($status)) {
        $count = $result;
        $c->stash->{page_num} = $page_num;
        $c->stash->{per_page} = $per_page;
        $c->stash->{by} = $orderby || $field_names->[0];
        $c->stash->{direction} = $orderdirection || 'asc';
        $c->stash->{items} = $items_ref;
        $c->stash->{field_names} = $field_names;
        $c->stash->{count} = $count;
        $c->stash->{pages_count} = ceil($count/$per_page);
    }
    else {
        $c->response->status($status);
        $c->stash->{status_msg} = $result;
        $c->stash->{current_view} = 'JSON';
    }
}


=head1 AUTHOR

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
