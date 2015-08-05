package Scramble::XML;

use strict;

use XML::Simple ();
use Scramble::Logger;
use List::Util ();

sub new {
    my $arg0 = shift;
    my ($parsed_xml) = @_;

    return bless { %$parsed_xml }, ref($arg0) || $arg0;
}

sub _get_optional_content {
    my $self = shift;
    my ($name) = @_;

    return undef unless exists $self->{$name};
    return ref $self->{$name} eq 'ARRAY' ?  $self->{$name}[0] : $self->{$name};
}

sub _set_required {
  my $self = shift;

  $self->_set(1, @_);
}
sub _set_optional {
  my $self = shift;

  $self->_set(0, @_);
}

sub _set {
  my $self = shift;
  my ($is_required, @attrs) = @_;

  foreach my $attr (@attrs) {
    my $value = $self->_get_optional($attr);
    die "Missing required attribute '$attr': " . Data::Dumper::Dumper($self) if ! $value && $is_required;
    $self->{$attr} = $value;
  }
}

sub _get_required {
    my $self = shift;
    my (@keys) = @_;

    return $self->_get_optional(@keys) || die "Missing @keys: " . Data::Dumper::Dumper($self);
}
sub _get_optional {
    my $self = shift;
    my (@keys) = @_;

    my $hr = $self;
    foreach my $key (@keys) {
	return undef unless UNIVERSAL::isa($hr, 'HASH');
	return undef unless exists $hr->{$key};
	$hr = $hr->{$key};
    }

    return $hr;
}

sub set {
    my $self = shift;
    my ($key, $value) = @_;

    if (! ref $key) {
	$self->{$key} = $value;
    } elsif (@$key == 2) { # how to do generically?
	$self->{$key->[0]}{$key->[1]} = $value;
    } else {
	die "Not supported: " . Data::Dumper::Dumper($key);
    }
}

######################################################################
# shared between Scramble::Location and Scramble::Report
######################################################################

sub get_map_objects { @{ $_[0]->{'map-objects'} } }
sub get_picture_objects { @{ $_[0]->{'picture-objects'} } }
sub set_picture_objects { $_[0]->{'picture-objects'} = $_[1] }

sub get_areas_from_xml {
    my $self = shift;

    my $areas_xml = $self->_get_optional('areas');
    return unless $areas_xml;

    my @areas;
    foreach my $area_tag (@{ $areas_xml->{'area'} }) {
	push @areas, Scramble::Area::get_all()->find_one('id' => $area_tag->{'id'})
    }

    return @areas;
}

sub get_recognizable_areas_html {
    my $self = shift;
    my (%args) = @_;

    my @areas = $self->get_areas_collection()->find('is-recognizable-area' => 'true');
    return '' unless @areas;

    return Scramble::Misc::make_colon_line("In", join(", ", map { $args{'no-link'} ? $_->get_short_name() : $_->get_short_link_html() } @areas));
}

sub get_driving_directions_html {
    my $self = shift;

    my $directions = $self->_get_optional('driving-directions', 'directions');
    if (! $directions) {
	my $d = $self->_get_optional_content('driving-directions');
	if ($d) {
	    die(sprintf("%s has old style driving-directions\n", $self->get_name()));
	}
	return undef;
    }

    my $html;
    foreach my $direction (@$directions) {
	if (! ref $direction) {
	    $html .= Scramble::Misc::htmlify($direction) . "<p>";
	} elsif (exists $direction->{'from-location'}) {
	    my $location = Scramble::Location::find_location('name' => $direction->{'from-location'},
							     quad => $direction->{quad},
							     'include-unvisited' => 1,
							     );
	    $html .= $location->get_driving_directions_html();
	} else {
	    die "Got bad direction: " . Data::Dumper::Dumper($direction);
	}
    }

    return $html;
}

######################################################################
# static methods
######################################################################

sub open_documents {
    my (@paths) = @_;

    my @xmls;
    foreach my $path (@paths) {
	my $xml = parse($path);
	if ($xml->{'skip'}) {
	    Scramble::Logger::verbose "Skipping $path\n";
	    next;
	}

	push @xmls, $xml;
    }

    return @xmls;
}


sub parse {
    my ($path, %options) = @_;
    
    if (0 == scalar keys %options) {
	%options = ("forcearray" => [
				     'AKA',
				     'area',
                                     'attempted',
				     'comments', 
				     'description',
				     'directions',
				     'location', 
				     'map', 
                                     'member',
                                     'not',
                                     'party',
				     'picture',
				     'reference',
				     'route', 
                                     'rock-route',
				     'distance',
                                     'image',
				     ],
		    "keyattr" => []);
    }
    Scramble::Logger::verbose "Parsing $path\n";
    my $xs = XML::Simple->new();
    my $xml = eval { $xs->XMLin($path, %options) };
    if ($@) {
        die "Error parsing '$path': $@";
    }

    $xml->{'path'} = $path;

    $xml->{'directory'} = $path;
    $xml->{'directory'} =~ s,/[^/]+$,,;

    my ($ofilename) = ($path =~ m,/([^/]+).xml$,);
    $xml->{'filename'} = $ofilename . ".html";
    $xml->{'pager-filename'} = $ofilename . "_pager.html";

    return $xml;
}

1;
