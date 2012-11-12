package pfappserver::Controller::Node;

=head1 NAME

pfappserver::Controller::Node - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=cut

use strict;
use warnings;

use HTTP::Status qw(:constants is_error is_success);
use Moose;
use namespace::autoclean;
use POSIX;

use pfappserver::Form::Node;

BEGIN {extends 'Catalyst::Controller'; }

=head1 SUBROUTINES

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

=head2 index

=cut
sub index :Path :Args(0) {
    my ( $self, $c ) = @_;

    $c->response->redirect($c->uri_for($c->controller('Node')->action_for('search')));
}

=head2 search

=cut
sub search :Path('search') :Args(0) {
    my ( $self, $c ) = @_;
    my ($filter, $orderby, $orderdirection, $status, $result, $nodes_ref, $count);

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
        if (grep {$_ eq $orderby} ('mac', 'pid', 'dhcp_fingerprint')) {
            $orderdirection = $c->request->params->{'direction'};
            unless (grep {$_ eq $orderdirection} ('asc', 'desc')) {
                $orderdirection = 'asc';
            }
            $params{'orderby'} = "ORDER BY $orderby $orderdirection";
            $c->stash->{by} = $orderby;
            $c->stash->{direction} = $orderdirection;
        }
    }

    ($status, $result) = $c->model('Node')->search(%params);
    if (is_success($status)) {
        $nodes_ref = $result;
        ($status, $result) = $c->model('Node')->countAll(%params);
    }
    if (is_success($status)) {
        $count = $result;
        $c->stash->{page_num} = $page_num;
        $c->stash->{per_page} = $per_page;
        $c->stash->{by} = $orderby || 'mac';
        $c->stash->{direction} = $orderdirection || 'asc';
        $c->stash->{nodes} = $nodes_ref;
        $c->stash->{count} = $count;
        $c->stash->{pages_count} = ceil($count/$per_page);
    }
    else {
        $c->response->status($status);
        $c->stash->{status_msg} = $result;
        $c->stash->{current_view} = 'JSON';
    }
}

=head2 object

Node controller dispatcher

=cut
sub object :Chained('/') :PathPart('node') :CaptureArgs(1) {
    my ( $self, $c, $mac ) = @_;

    my ($status, $node_ref) = $c->model('Node')->exists($mac);
    if ( is_error($status) ) {
        $c->response->status($status);
        $c->stash->{status_msg} = $node_ref;
        $c->stash->{current_view} = 'JSON';
        $c->detach();
    }

    $c->stash->{mac} = $mac;
}

=head2 get

=cut
sub get :Chained('object') :PathPart('get') :Args(0) {
    my ($self, $c) = @_;

    my ($nodeStatus, $result);
    my ($form, $status, $roles);

    # Form initialization :
    # Retrieve node details, categories and status

    ($status, $result) = $c->model('Node')->get($c->stash->{mac});
    if (is_success($status)) {
        $c->stash->{node} = $result;
    }
    ($status, $result) = $c->model('Roles')->list();
    if (is_success($status)) {
        $roles = $result;
    }
    $nodeStatus = $c->model('Node')->availableStatus();
    $form = pfappserver::Form::Node->new(ctx => $c,
                                         init_object => $c->stash->{node},
                                         status => $nodeStatus,
                                         roles => $roles);
    $form->process();
    $c->stash->{form} = $form;

#    my @now = localtime;
#    $c->stash->{now} = { date => POSIX::strftime("%Y-%m-%d", @now),
#                         time => POSIX::strftime("%H:%M", @now) };
}

=head2 update

=cut
sub update :Chained('object') :PathPart('update') :Args(0) {
    my ( $self, $c ) = @_;

    my ($status, $message);
    my ($form, $nodeStatus);

    $nodeStatus = $c->model('Node')->availableStatus();
    $form = pfappserver::Form::Node->new(ctx => $c,
                                         status => $nodeStatus);
    $form->process(params => $c->request->params);
    if ($form->has_errors) {
        $status = HTTP_BAD_REQUEST;
        $message = $form->field_errors;
    }
    else {
        ($status, $message) = $c->model('Node')->update($c->stash->{mac}, $form->value);
    }
    if (is_error($status)) {
        $c->response->status($status);
        $c->stash->{status_msg} = $message; # TODO: localize error message
    }
    $c->stash->{current_view} = 'JSON';
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
