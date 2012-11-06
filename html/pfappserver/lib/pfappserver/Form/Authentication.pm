package pfappserver::Form::Authentication;

=head1 NAME

pfappserver::Form::Authentication - authentication sources

=head1 DESCRIPTION

Sortable list of authentication sources.

=cut

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
with 'pfappserver::Form::Widget::Theme::Pf';

has '+field_name_space' => ( default => 'pfappserver::Form::Field' );
has '+widget_name_space' => ( default => 'pfappserver::Form::Widget' );
has '+language_handle' => ( builder => 'get_language_handle_from_ctx' );

# Form fields
has_field 'sources' =>
  (
   type => 'Repeatable',
   num_when_empty => 0,
  );
has_field 'sources.id' =>
  (
   type => 'Hidden',
   widget_wrapper => 'None',
  );
has_field 'sources.description' =>
  (
   type => 'Text',
  );
has_field 'sources.type' =>
  (
   type => 'Text',
  );

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
