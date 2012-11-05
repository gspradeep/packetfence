package pfappserver::Controller::Authentication::Source;

=head1 NAME

pfappserver::Controller::Authentication::Source - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=cut

use strict;
use warnings;

use HTTP::Status qw(:constants is_error is_success);
use Moose;
use namespace::autoclean;
use POSIX;

use pf::authentication;
use pfappserver::Form::Authentication::Source;
use pfappserver::Form::Authentication::Source::AD;
use pfappserver::Form::Authentication::Source::LDAP;
use pfappserver::Form::Authentication::Source::RADIUS;
use pfappserver::Form::Authentication::Source::Kerberos;
use pfappserver::Form::Authentication::Source::Htpasswd;
use pfappserver::Form::Authentication::Rule;

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
    my ($self, $c) = @_;

    $c->response->redirect($c->uri_for($c->controller('Admin')->action_for('configuration'), ('sources')));
    $c->detach();
}

=head2 create

Create a rule of the specified type

/authentication/create/*

=cut

sub create :Local :Args(1) {
    my ($self, $c, $type) = @_;

    $c->stash->{action_uri} = $c->req->uri;
    $c->stash->{source} = {};
    $c->stash->{source}->{type} = $type; # case-sensitive

    if ($c->request->method eq 'POST') {
        # Create the source from the update action
        $c->stash->{source}->{id} = $c->req->params->{id};
        $c->forward('update');
    }
    else {
        # Show an empty form
        $c->forward('read');
    }
}

=head2 object

Authentication source chained dispatcher

/authentication/*

=cut

sub object :Chained('/') :PathPart('authentication') :CaptureArgs(1) {
    my ($self, $c, $id) = @_;

    my $source = getAuthenticationSource($id);

    if (defined $source) {
        $c->stash->{source_id} = $id;
        $c->stash->{source} = $source;
    }
    else {
        $c->response->status(HTTP_NOT_FOUND);
        $c->stash->{status_msg} = $c->loc('The authentication source was not found.');
        $c->stash->{current_view} = 'JSON';
        $c->detach();
    }
}

=head2 read

/authentication/*/read

=cut

sub read :Chained('object') :PathPart('read') :Args(0) {
    my ($self, $c) = @_;

    my ($form_type, $form);

    if ($c->stash->{source}->{id} && !$c->stash->{action_uri}) {
        $c->stash->{action_uri} = $c->uri_for($self->action_for('update'), [$c->{stash}->{source}->{id}]);
    }

    $form_type = 'pfappserver::Form::Authentication::Source::' . $c->stash->{source}->{type};
    $form = $form_type->new(ctx => $c, init_object => $c->stash->{source});
    $form->process();
    $c->stash->{form} = $form;
    $c->stash->{template} = 'authentication/source/read.tt';
}

=head2 update

/authentication/*/update

=cut

sub update :Chained('object') :PathPart('update') :Args(0) {
    my ($self, $c) = @_;

    my ($form_type, $form, $status, $message);

    $form_type = 'pfappserver::Form::Authentication::Source::' . $c->stash->{source}->{type};
    $form = $form_type->new(ctx => $c, id => $c->stash->{source_id});
    $form->process(params => $c->request->params);
    if ($form->has_errors) {
        $status = HTTP_BAD_REQUEST;
        $message = $form->field_errors;
    }
    else {
        ($status, $message) = $c->model('Authentication::Source')->update($c->stash->{source}, $form->value);
    }

    if (is_error($status)) {
        $c->response->status($status);
        $c->stash->{status_msg} = $message; # TODO: localize error message    
        $c->stash->{current_view} = 'JSON';
    }
    else {
        if (!$c->stash->{source_id}) {
            # New source -- show the source and let the user add some rules
            $c->stash->{action_uri} = $c->uri_for($self->action_for('update'), [$form->value->{id}]);
            $c->stash->{form} = $form;
            $c->stash->{template} = 'authentication/source/read.tt';
        }
        else {
            # Existing source; return to the list of sources
            $c->forward('Configuration', 'authentication');
        }
        $c->stash->{message} = $message;
    }
}

=head2 delete

/authentication/*/delete

=cut

sub delete :Chained('object') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;

    my ($status, $message) = $c->model('Authentication::Source')->delete($c->stash->{source});
    if (is_error($status)) {
        $c->response->status($status);
        $c->stash->{status_msg} = $message;
    }

    $c->stash->{current_view} = 'JSON';
}



=head2 rule_create

/authentication/*/rule/create

=cut

sub rule_create :Chained('object') :PathPart('rule/create') :Args(0) {
    my ($self, $c) = @_;

    $c->stash->{action_uri} = $c->req->uri;
    if ($c->request->method eq 'POST') {
        $c->forward('rule_update');
    }
    else {
        $c->forward('rule_read');
    }
}

=head2 rule_object

Rule chained dispatcher

/authentication/*/rule/*

=cut

sub rule_object :Chained('object') :PathPart('rule') :CaptureArgs(1) {
    my ($self, $c, $id) = @_;

    my $rule = $c->stash->{source}->getRule($id);

    if (defined $rule) {
        $c->stash->{rule} = $rule;
    }
    else {
        $c->response->status(HTTP_NOT_FOUND);
        $c->stash->{status_msg} = $c->loc('The rule was not found.');
        $c->stash->{current_view} = 'JSON';
        $c->detach();
    }
}

=head2 rule_read

/authentication/*/rule/*/read

=cut

sub rule_read :Chained('rule_object') :PathPart('read') :Args(0) {
    my ($self, $c) = @_;

    my ($form);

    if ($c->stash->{rule} && !$c->stash->{action_uri}) {
        $c->stash->{action_uri} = $c->uri_for($self->action_for('rule_update'),
                                              [$c->{stash}->{source}->{id}, $c->{stash}->{rule}->{id}]);
    }

    $form = pfappserver::Form::Authentication::Rule->new(ctx => $c,
                                                         init_object => $c->stash->{rule},
                                                         attrs => $c->stash->{source}->available_attributes());
    if ($c->stash->{rule}) {
        # Update existing rule
        $form->process;
    }
    else {
        # New rule
        $form->field('actions')->add_extra;
    }

    $c->stash->{form} = $form;

    $c->stash->{template} = 'authentication/source/rule_read.tt';
}

=head2 rule_update

/authentication/*/rule/*/update

=cut

sub rule_update :Chained('rule_object') :PathPart('update') :Args(0) {
    my ($self, $c) = @_;

    my ($form, $status, $message);

    $form = pfappserver::Form::Authentication::Rule->new(ctx => $c,
                                                         attrs => $c->stash->{source}->available_attributes());
    $form->process(params => $c->request->params);
    if ($form->has_errors) {
        $status = HTTP_BAD_REQUEST;
        $message = $form->field_errors;
    }
    else {
        ($status, $message) =
          $c->model('Authentication::Source')->updateRule($c->stash->{source}->{id},
                                                          $c->stash->{rule}? $c->stash->{rule}->{id} : undef,
                                                          $form->value);
    }
    if (is_error($status)) {
        # Error -- return a JSON hash
        $c->response->status($status);
        $c->stash->{status_msg} = $message; # TODO: localize error message
        $c->stash->{current_view} = 'JSON';
    }
    else {
        # Success -- reload the source
        $c->stash->{action_uri} = undef;
        $c->forward('read');
    }
}

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