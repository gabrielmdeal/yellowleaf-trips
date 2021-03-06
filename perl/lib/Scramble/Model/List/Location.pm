package Scramble::Model::List::Location;

use strict;

use Scramble::Collection ();

my $g_collection = Scramble::Collection->new;

sub new {
    my ($arg0, $data) = @_;

    my $self = { %$data };

    return bless($self, ref($arg0) || $arg0);
}

sub get_county { $_[0]{county} }
sub get_note { $_[0]{note} }
sub get_name { $_[0]{name} }
sub get_quad { $_[0]{quad} }
sub get_mvd { $_[0]{MVD} }
sub get_order { $_[0]{order} }
sub set_order { $_[0]{order} = $_[1] }

sub get_location_object {
    my $self = shift;

    return $self->{'location-object'} if defined $self->{'location-object'};

    my $location = eval {
        Scramble::Model::Location::find_location('name' => $self->get_name,
                                                 'quad' => $self->get_quad,
                                                 'include-unvisited' => 1);
    };
    if ($@) {
        $location = 0;
    }

    $self->{'location-object'} = $location;

    return $location;
}

sub get_elevation {
    my ($self) = @_;

    local $Data::Dumper::Maxdepth = 2;

    my $location = $self->get_location_object;
    if ($location) {
	return $location->get_elevation() || die "No elevation: " . Data::Dumper::Dumper($self);
    }

    return $self->{'elevation'} || die "No elevation: " . Data::Dumper::Dumper($self);
}

1;
