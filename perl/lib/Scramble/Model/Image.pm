package Scramble::Model::Image;

use strict;

use File::Basename ();
use Scramble::Collection ();
use Scramble::Template ();

my $g_pics_dir = "pics";
my $g_collection = Scramble::Collection->new();

sub _copy {
    my ($file1, $file2, $file3, $dir, $target_dir) = @_;

    foreach my $file ($file1, $file2, $file3) {
        next unless defined $file;
        my $source = "$dir/$file";
        my $target = "$target_dir/$file";
        my $source_size = (stat($source))[7] or die "Error getting size '$source': $!";
        my $target_size = (stat($target))[7];
        if (defined $target_size && $source_size == $target_size) {
            next;
        }
        Scramble::Logger::verbose("cp $source $target_dir\n");
        system("cp", $source, $target_dir) == 0 or die "Can't copy '$source' to '$target_dir': $!";
    }
}
sub copy {
    Scramble::Logger::verbose("Copying new images...");

    my $output_image_dir = Scramble::Misc::get_output_directory() . "/$g_pics_dir/";

    File::Path::mkpath([$output_image_dir], 0, 0755);
    foreach my $image (glob "images/*.{gif,ico,png,json}") {
        system("cp", $image, $output_image_dir) == 0 or die "Can't copy '$image' to '$output_image_dir': $!";
    }

    foreach my $image (get_all_images_collection()->get_all()) {
        my $target_dir = "$output_image_dir/" . $image->get_subdirectory();
        File::Path::mkpath([$target_dir], 0, 0755);
        _copy($image->get_filename(),
              $image->get_enlarged_filename(),
              $image->get_poster(),
              $image->get_source_directory(),
              $target_dir);
    }
}

sub new_from_attrs {
    my $arg0 = shift;
    my ($args) = @_;

    my $self = { %$args };
    bless $self, ref($arg0) || $arg0;

    $self->{'type'} = 'picture' unless exists $self->{'type'};
    $self->{'subdirectory'} = File::Basename::basename($self->{'source-directory'});
    $self->{'chronological-order'} = 0 unless exists $self->{'chronological-order'};
    foreach my $key (qw(subdirectory thumbnail-filename type source-directory)) {
        die "Missing '$key': ", Data::Dumper::Dumper($self)
            unless defined $self->{$key};
    }

    $self->{'description'} = $self->{'description'} ? ucfirst($self->{'description'}) : '';

    if (defined $self->{'date'}) {
	$self->{'date'} = Scramble::Time::normalize_date_string($self->{'date'});
    }

    return $self;
}

sub get_id { $_[0]->get_source_directory() . "|" . $_[0]->get_filename() }
sub get_chronological_order { $_[0]->{'chronological-order'} }
sub in_chronological_order { $_[0]->{'in-chronological-order'} }
sub get_source_directory { $_[0]->{'source-directory'} }
sub get_filename { $_[0]->{'thumbnail-filename'} }
sub get_enlarged_filename { $_[0]->{'large-filename'} }
sub get_subdirectory { $_[0]->{'subdirectory'} }
sub get_section_name { $_[0]->{'section-name'} }

sub get_date { $_[0]->{'date'} } # optional for maps that are not for a particular trip
sub get_datetime { $_[0]{'capture-timestamp'} }

sub get_description { $_[0]->{'description'} }
sub get_of { $_[0]->{'of'} } # undefined means we don't know. Empty string means it is not of any known location.
sub get_from { $_[0]->{'from'} || '' }
sub get_owner { $_[0]->{'owner'} }
sub get_url { sprintf("../../$g_pics_dir/%s/%s", $_[0]->get_subdirectory(), $_[0]->get_filename()) }
sub get_full_url { sprintf("https://yellowleaf.org/scramble/$g_pics_dir/%s/%s", $_[0]->get_subdirectory(), $_[0]->get_filename()) }
sub get_trip_url { $_[0]->{'trip-url'} }
sub set_trip_url { $_[0]->{'trip-url'} = $_[1] }
sub get_should_skip_trip { $_[0]->{'skip-trip'} }
sub get_type { $_[0]->{'type'} }
sub get_poster { $_[0]->{'poster'} }

sub get_poster_url {
    my $self = shift;

    if (!$self->get_poster) {
        return '';
    }

    return sprintf("../../$g_pics_dir/%s/%s", $self->get_subdirectory(), $self->get_poster());
}

sub get_capture_date {
    my $self = shift;

    my $capture_date = $self->{'capture-timestamp'};
    return undef unless defined $capture_date;

    my ($date) = ($capture_date =~ m,^(\d\d\d\d/\d\d/\d\d),);
    return $date;
}

sub get_rating {
  my $self = shift;

  # Rating v3:
  # 1 - One of my favorites
  # 2 - Pretty
  # 3 - Part of the story

  # Rating v2:
  # 1 - One of my best photos ever.  Very few photos in this category.
  # 2 - Great photo that stands on its own.
  # 3 - Used to distinguish my favorite pics from a trip, where most of the pics in the trip are 3.1.
  # 3.1 - Nice photo, but needs the story to be useful.  Most photos are in this category.
  # 4 - Included only for the story.

  # Rating v1:
  # 1 best
  # 100 worst

  if (defined $self->{rating}) {
    return $self->{rating};
  }
  return 3;
}

sub get_best_images {
    my @images = @_;

    @images = Scramble::Misc::dedup(@images);
    @images = sort { Scramble::Model::Image::cmp($a, $b) } @images;

    my $max = 50;
    if (@images > $max) {
        @images = @images[0 .. $max-1];
    }

    return @images;
}

sub get_enlarged_img_url {
    my $self = shift;

    return undef unless defined $self->get_enlarged_filename();

    return sprintf("../../$g_pics_dir/%s/%s",
                   $self->get_subdirectory,
                   $self->get_enlarged_filename());
}

sub get_map_reference {
    my $self = shift;

    return { 'name' => $self->get_description(),
	     'URL' => $self->get_url(),
	     'id' => 'routeMap', # used by Scramble::Model::Reference
	     'type' => ($self->{'noroute'} 
			? "Online map"
			: "Online map with route drawn on it"),
	 };
}

sub cmp {
  my ($a, $b) = @_;

  if (! defined $a->get_rating() && ! defined $b->get_rating()) {
    return 0;
  }
  if (! defined $a->get_rating()) {
    return -1;
  }
  if (! defined $b->get_rating()) {
    return 1;
  }
  if ($a->get_rating() == $b->get_rating()) {
    return cmp_date($b, $a); # Newest first
  }
  return $a->get_rating() <=> $b->get_rating();
}

######################################################################
# Statics
######################################################################

sub get_all_images_collection { $g_collection }

sub read_images_from_trip {
    my ($directory, $trip) = @_;

    my $date = $trip->get_start_date();
    my ($year, $month, $day) = Scramble::Time::parse_date($date);

    my $in_chronological_order = $trip->_get_optional('files', 'in-chronological-order');
    if (defined($in_chronological_order) && '' eq $in_chronological_order) {
	die "images.in-chronological-order is empty";
    }

    my @images;
    my $chronological_order = 0;
    foreach my $image_xml (@{ $trip->_get_optional('files', "file") || [] }) {
        next if $image_xml->{skip};
        push @images, Scramble::Model::Image->new_from_attrs({ 'date' => "$year/$month/$day",
                                                                   'source-directory' => $directory,
                                                                   'chronological-order' => $chronological_order++,
                                                                   'in-chronological-order' => $in_chronological_order,
                                                                   %$image_xml,
                                                             });
    }

    $g_collection->add(@images);
    return @images;
}

sub cmp_date {
  my ($image_a, $image_b) = @_;

  my $date_a = $image_a->get_date();
  my $date_b = $image_b->get_date();
  if ($image_a->get_datetime() && $image_b->get_datetime()) {
      $date_a = $image_a->get_datetime();
      $date_b = $image_b->get_datetime();
  }

  if (! defined $date_a) {
    if (! defined $date_b) {
      return 0;
    } else {
      return -1;
    }
  }
  if (! defined $date_b) {
    return 1;
  }

  return $date_a cmp $date_b;
}

1;
