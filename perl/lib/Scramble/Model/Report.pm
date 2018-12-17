package Scramble::Model::Report;

use strict;

use XML::RSS ();
use MIME::Types ();
use DateTime ();
use DateTime::Format::Mail ();
use JSON ();
use Scramble::Model::Waypoints2 ();
use Scramble::Model::Image ();
use Scramble::Model::Reference ();
use Scramble::Page::ReportPage ();
use Scramble::Template ();
use Scramble::Time ();

our @ISA = qw(Scramble::Model);

my %location_to_reports_mapping;
my $g_report_collection = Scramble::Collection->new();
my $g_max_rating = 5;

sub new {
    my ($arg0, $path) = @_;

    my $self = Scramble::Model::parse($path);
    bless($self, ref($arg0) || $arg0);
    if ($self->{'skip'}) {
	return undef;
        print "Skipping $path because 'skip=true'\n";
    }

    $self->{'waypoints'} = Scramble::Model::Waypoints2->new($self->get_filename(),
						     $self->_get_optional('waypoints'));

    my @location_objects;
    foreach my $location_element ($self->get_locations()) {
	push @location_objects, Scramble::Model::Location::find_location('name' => $location_element->{'name'},
                                                                         'quad' => $location_element->{'quad'},
                                                                         'country' => $location_element->{country},
                                                                         'include-unvisited' => 1,
            );
    }
    $self->{'location-objects'} = \@location_objects;
    foreach my $location ($self->get_location_objects()) {
	$location->set_have_visited();
    }

    {
	my @areas;
	push @areas, map { $_->get_areas_collection->get_all() } $self->get_location_objects();
	push @areas, $self->get_areas_from_xml();
	@areas = Scramble::Misc::dedup(@areas);
	$self->{'areas-object'} = Scramble::Collection->new('objects' => \@areas);
    }

    $self->set('start-date', Scramble::Time::normalize_date_string($self->get_start_date()));
    if (defined $self->get_end_date()) {
	$self->set('end-date', Scramble::Time::normalize_date_string($self->get_end_date()));
    }

    my @images = Scramble::Model::Image::read_images_from_report(File::Basename::dirname($path), $self);
    my $image_collection = Scramble::Collection->new(objects => \@images);

    my $picture_objs = [
        $image_collection->find('type' => 'picture'),
        $image_collection->find('type' => 'movie'),
    ];

    if (@$picture_objs && $picture_objs->[0]->in_chronological_order()) {
        $picture_objs = [ sort { $a->get_chronological_order() <=> $b->get_chronological_order() } @$picture_objs ];
    }
    $self->set_picture_objects([ grep { ! $_->get_should_skip_report() } @$picture_objs]);

    $self->{'map-objects'} = [ $image_collection->find('type' => 'map') ];

    my @kmls = $image_collection->find('type' => 'kml');
    die "Too many KMLs" if @kmls > 1;
    $self->{'kml'} = $kmls[0] if @kmls;

    if ($self->should_show()) {
        foreach my $image (@$picture_objs, $self->get_map_objects()) {
            $image->set_report_url($self->get_report_page_url());
        }
    }

    return $self;
}

sub get_id { $_[0]->get_start_date() . "|" . ($_[0]->get_trip_id() || "") }
sub get_trip_id { $_[0]->_get_optional('trip-id') }
sub get_areas_collection { $_[0]->{'areas-object'} }
sub get_waypoints { $_[0]->{'waypoints'} }
sub get_type { $_[0]->_get_optional('type') || 'scramble' }
sub get_end_date { $_[0]->_get_optional('end-date') }
sub get_start_date { $_[0]->_get_required('start-date') }
sub get_name { $_[0]->_get_required('name') }
sub get_locations { @{ $_[0]->_get_optional('locations', 'location') || [] } }
sub get_location_objects { @{ $_[0]->{'location-objects'} } }
sub get_state { $_[0]->_get_optional('state') || "done" }
sub get_route { $_[0]->_get_optional_content('description') }
sub get_kml { $_[0]->{kml} }
sub get_map_objects { @{ $_[0]->{'map-objects'} } }
sub get_picture_objects { @{ $_[0]->{'picture-objects'} } }
sub set_picture_objects { $_[0]->{'picture-objects'} = $_[1] }


sub get_filename {
    my $self = shift;
    return $self->_get_required('filename') . ".html";
}

sub get_best_picture_object {
    my $self = shift;

    my $best_image;
    foreach my $image ($self->get_picture_objects()) {
        $best_image = $image if ! defined $best_image;
        $best_image = $image if $best_image->get_rating() >= $image->get_rating();
    }
    return $best_image;
}

sub get_num_days {
  my $self = shift;

  if (! defined $self->get_end_date()) {
    return 1;
  }

  my ($syear, $smonth, $sday) = Scramble::Time::parse_date($self->get_start_date());
  my ($eyear, $emonth, $eday) = Scramble::Time::parse_date($self->get_end_date());

  if (! defined $syear) {
    return 1;
  }

  my $start = Date::Manip::Date_DaysSince1BC($smonth, $sday, $syear);
  my $end = Date::Manip::Date_DaysSince1BC($emonth, $eday, $eyear);

  return 1 + $end - $start;
}

sub should_show {
    my $self = shift;
    if ($self->_get_optional('should-not-show')) {
	return 0;
    }
    return 1;
}

sub link_if_should_show {
    my $self = shift;
    my ($html) = @_;

    return ($self->should_show() 
            ? sprintf(qq(<a href="%s">%s</a>), $self->get_report_page_url(), $html) 
            : $html);
}

sub get_parsed_start_date {
    my $self = shift;

    my @date = split('/', $self->get_start_date());
    @date == 3 or die sprintf("Bad start date '%s'", $self->get_start_date());
    return @date;
}

sub get_maps { 
    my $self = shift;

    my @maps;
    push @maps, map { $_->get_map_reference() } $self->get_map_objects();
    push @maps, @{ $self->_get_optional('maps', 'map') || [] };

    return grep { ! $_->{'skip-map'} } @maps;
}

sub get_report_page_url {
    my $self = shift;

    return sprintf("../../g/r/%s", $self->get_filename());
}

sub get_summary_date {
    my $self = shift;

    my $date = $self->get_start_date();
    if (defined $self->get_end_date()) {
        my $start_day = Scramble::Time::get_days_since_1BC($self->get_start_date());
        my $end_day = Scramble::Time::get_days_since_1BC($self->get_end_date());
        my $num_days = 1 + $end_day - $start_day;
        $date .= " ($num_days days)";
    }

    return $date;
}

sub get_summary_name {
    my $self = shift;
    my ($name) = @_;

    $name = $self->get_name() unless $name;
    $name = $self->link_if_should_show($name);
    if ($self->get_state() ne 'done') {
	$name .= sprintf(" (%s)", $self->get_state());
    }

    return $name;
}

sub get_sorted_images {
    my $self = shift;

    return () unless $self->should_show();
    return sort { $a->get_rating() <=> $b->get_rating() } $self->get_picture_objects();
}

sub get_summary_images {
    my $self = shift;
    my %options = @_;

    my $size = $options{size} || 125;

    my @image_htmls;
    foreach my $image_obj ($self->get_sorted_images()) {
        if ($image_obj) {
            my $image_html = sprintf(qq(<img width="$size" onload="Yellowleaf_main.resizeThumbnail(this, $size)" src="%s">),
                                     $image_obj->get_url());
            $image_html = $self->link_if_should_show($image_html);
            push @image_htmls, $image_html;
        }
    }

    return @image_htmls;
}

sub get_link_html {
    my $self = shift;

    my $date = $self->get_summary_date();
    my $name = $self->get_summary_name();
    my $image_html = ($self->get_summary_images())[0] || '';
    my $type = $self->get_type();

    return <<EOT;
<div class="report-thumbnail">
    <div class="report-thumbnail-image">$image_html</div>
    <div class="report-thumbnail-title">$name</div>
    <div class="report-thumbnail-date">$date</div>
    <div class="report-thumbnail-type">$type</div>
</div>
EOT
}

sub get_embedded_google_map_html {
    my $self = shift;

    return '' if $self->get_map_objects();

    my @locations = $self->get_location_objects();
    my $kml_url = $self->get_kml() ? $self->get_kml()->get_full_url() : undef;
    return '' unless $kml_url or grep { defined $_->get_latitude() } @locations;

    my %options = ('kml-url' => $kml_url);
    return Scramble::Misc::get_multi_point_embedded_google_map_html(\@locations, \%options);
}

sub get_distances_html {
    my $self = shift;

    my $distances = $self->_get_optional('round-trip-distances', 'distance');
    if (! $distances) {
        return '';
    }

    my @parenthesis_htmls;
    my $total_miles = 0;
    foreach my $distance (@$distances) {
	$total_miles += $distance->{'miles'};
	push @parenthesis_htmls, sprintf("%s %s on %s",
					 $distance->{'miles'},
					 Scramble::Misc::pluralize($distance->{'miles'}, "mile"),
					 $distance->{'type'});
    }

    return sprintf("<b>Round-trip distance:</b> approx. %s %s%s<br>",
		   $total_miles,
		   Scramble::Misc::pluralize($total_miles, 'mile'),
		   (@parenthesis_htmls == 1 ? '' : " (" . join(", ", @parenthesis_htmls) . ")"));
}

sub get_references {
    my $self = shift;

    my @references = @{ $self->_get_optional('references', 'reference') || [] };
    @references = sort { Scramble::Model::Reference::cmp_references($a, $b) } @references;

    return @references;
}

sub get_reference_html {
    my $self = shift;

    my @references = map { Scramble::Model::Reference::get_page_reference_html($_) } $self->get_references();
    @references = Scramble::Misc::dedup(@references);

    return '' unless @references;

    return '<ul><li>' . join('</li><li>', @references) . '</li></ul>';
}

sub get_map_summary_html {
    my $self = shift;

    return '' if defined $self->_get_optional('maps') && ! defined $self->_get_optional('maps', 'map');

    my $type = 'USGS quad';
    my %maps;

    foreach my $map ($self->get_maps()) {
        my $map_type = Scramble::Model::Reference::get_map_type($map);
        next unless defined $map_type && $type eq $map_type;
        my $name = Scramble::Model::Reference::get_map_name($map);
        $maps{$name} = 1;
    }

    if ($type eq 'USGS quad') {
        foreach my $location ($self->get_location_objects()) {
            foreach my $quad ($location->get_quad_objects()) {
                $maps{$quad->get_short_name()} = 1;
            }
        }

        foreach my $area ($self->get_areas_collection()->find('type' => 'USGS quad')) {
            $maps{$area->get_short_name()} = 1;
        }
    }

    my @maps = keys %maps;
    return '' unless @maps;
    return '' if @maps > 15;

    my $title = Scramble::Misc::pluralize(scalar(@maps), $type);
    return Scramble::Misc::make_colon_line($title, join(", ", @maps));
}

sub get_copyright_html {
    my $self = shift;

    my $copyright_year = $self->get_end_date() ? $self->get_end_date() : $self->get_start_date();
    ($copyright_year) = Scramble::Time::parse_date($copyright_year);

    return $copyright_year;
}

sub get_title_html {
    my $self = shift;

    return $self->get_name();
}

sub split_pictures_into_sections {
    my $self = shift;

    my @picture_objs = $self->get_picture_objects();
    return ({ name => '', pictures => []}) unless @picture_objs;

    my @sections;
    if (!@picture_objs[0]->get_section_name()) {
        my $split_picture_objs = $self->split_by_date(@picture_objs);
        return $self->add_section_names($split_picture_objs);
    }

    return $self->split_by_section_name(@picture_objs);
}

sub split_by_section_name {
    my $self = shift;
    my @picture_objs = @_;

    my @sections;
    my %current_section = (name => '', pictures => []);
    foreach my $picture_obj (@picture_objs) {
        if ($picture_obj->get_section_name() && $picture_obj->get_section_name() ne $current_section{name}) {
            push @sections, { %current_section } if @{ $current_section{pictures} };
            %current_section = ( name => $picture_obj->get_section_name(),
                                 pictures => [] );
        }
        push @{ $current_section{pictures} }, $picture_obj;
    }
    push @sections, \%current_section if %current_section;

    return @sections;
}

sub split_by_date {
    my $self = shift;
    my @picture_objs = @_;

    return [] if !@picture_objs;

    my $curr_date = $picture_objs[0]->get_capture_date();
    return [\@picture_objs] unless defined $curr_date;

    my @splits;
    my $split = [];
    foreach my $picture_obj (@picture_objs) {
        if ($curr_date eq $picture_obj->get_capture_date()) {
            push @$split, $picture_obj;
        } else {
            push @splits, $split;
            $split = [ $picture_obj ];
            $curr_date = $picture_obj->get_capture_date();
        }
    }
    push @splits, $split;

    return \@splits;
}

# Return: an array of hashes. Each hash is { name => "", pictures => [] }
sub add_section_names {
    my $self = shift;
    my ($split_picture_objs) = @_; # each element is an array of picture objects

    my $start_days = Scramble::Time::get_days_since_1BC($self->get_start_date());
    my @sections;
    foreach my $picture_objs (@$split_picture_objs) {
        my $section_name = '';
        # Handle trips where I don't take a picture every day:
        if (@$picture_objs && defined $picture_objs->[0]->get_capture_date()) {
            my $picture_days = Scramble::Time::get_days_since_1BC($picture_objs->[0]->get_capture_date());
            my $day = $picture_days - $start_days + 1;
            $section_name = "Day $day";
        }
        push @sections, { name => $section_name,
                          pictures => $picture_objs };
    }

    return @sections;
}


######################################################################
# statics
######################################################################

sub equals {
    my $self = shift;
    my ($report) = @_;

    return $report->get_id() eq $self->get_id();
}

sub cmp_by_duration {
    my ($report1, $report2) = @_;

    return $report1->get_waypoints()->get_car_to_car_delta() <=> $report2->get_waypoints()->get_car_to_car_delta();
}

sub cmp {
    my ($report1, $report2) = @_;

    if ($report1->get_start_date() ne $report2->get_start_date()) {
        return $report1->get_start_date() cmp $report2->get_start_date();
    }

    if (! defined $report1->get_trip_id() || ! defined $report2->get_trip_id()) {
        return defined $report1->get_trip_id() ? 1 : -1;
    }

    return $report1->get_trip_id() cmp $report2->get_trip_id();
}

sub open_specific {
    my ($path) = @_;

    $path = "$path/report.xml" if !-f $path && -f "$path/report.xml";

    my $report = Scramble::Model::Report->new($path);
    $g_report_collection->add($report) if defined $report;
    return $report;
}

sub open_all {
    my ($directory) = @_;

    die "No such directory '$directory'" unless -d $directory;

    foreach my $path (reverse(sort(glob("$directory/*/report.xml")))) {
	open_specific($path);
    }
}

sub get_all {
    return $g_report_collection->get_all();
}

sub make_rss {
    # http://feedvalidator.org/
    # http://www.w3schools.com/rss/default.asp

    my $rss = XML::RSS->new(version => '1.0');
    my $now = DateTime::Format::Mail->format_datetime(DateTime->now());
    $rss->channel(title => 'yellowleaf.org',
		  link => 'https://yellowleaf.org/scramble/g/m/home.html',
		  language => 'en',
		  description => 'Mountains and pictures. Pictures and mountains.',
		  copyright => 'Copyright 2013, Gabriel Deal',
		  pubDate => $now,
		  lastBuildDate => $now,
	      );
    $rss->image(title => 'yellowleaf.org',
		url => 'https://yellowleaf.org/scramble/pics/favicon.jpg',
		link => 'https://yellowleaf.org/scramble/g/m/home.html',
		width => 16,
		height => 16,
		description => "It's a snowy mountain and the sun!"
	    );

    my $count = 0;
    my $mime = MIME::Types->new(only_complete => 1);
    foreach my $report (get_all()) {
        last unless ++$count <= 15; 
        next unless $report->should_show();
        my $best_image = $report->get_best_picture_object();
	next unless $best_image;

	die Data::Dumper::Dumper($best_image) . "\n\n\n\n" . Data::Dumper::Dumper($report) unless $best_image->get_enlarged_img_url();

	my $image_url = sprintf(qq(https://yellowleaf.org/scramble/%s),
				$best_image->get_enlarged_img_url());
	# The "../.." in the URL was stopping Feedly from displaying
	# an image in the feed preview.
	$image_url =~ s{\.\./\.\./}{};

        my $report_url = sprintf("https://yellowleaf.org/scramble/%s",
				 $report->get_report_page_url());
	$report_url =~ s{\.\./\.\./}{};

	my $image_html = sprintf(qq(<a href="%s"><img src="%s" alt="%s"></a>),
				 $report_url,
				 $image_url,
				 $best_image->get_description());
	my $description = qq(<![CDATA[$image_html]]>);

	$rss->add_item(title => $report->get_name(),
		       link => $report_url,
		       description => $description,
		       content => {
			   encoded => $description,
		       },
		       enclosure => { url => $image_url,
				      type => $mime->mimeTypeOf($best_image->get_filename()),
				  });
    }

    Scramble::Misc::create("r/rss.xml", $rss->as_string());
}

sub get_reports_for_location {
    my ($location) = @_;

    my @retval;
    foreach my $report (get_all()) {
	push @retval, $report if grep { $location->equals($_) } $report->get_location_objects();
    }
    return @retval;
}

sub get_shorter_than {
    my ($hours) = @_;

    my @reports;
    foreach my $report (get_all()) {
        my $minutes = $report->get_waypoints()->get_car_to_car_delta();
        next unless defined $minutes;
        next unless $minutes < $hours * 60;
        push @reports, $report;
    }

    return \@reports;
}

######################################################################
# end statics
######################################################################

1;