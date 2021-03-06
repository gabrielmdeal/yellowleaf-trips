package Scramble::Controller::TripRss;

use strict;

use DateTime ();
use DateTime::Format::Mail ();
use MIME::Types ();
use Scramble::Misc ();
use XML::RSS ();

sub create {
    my ($writer) = @_;

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
    foreach my $trip (Scramble::Model::Trip::get_all()) {
        last unless ++$count <= 15; 
        next unless $trip->should_show();
        my $best_picture = $trip->get_best_picture_object();
	next unless $best_picture;

	die Data::Dumper::Dumper($best_picture) . "\n\n\n\n" . Data::Dumper::Dumper($trip) unless $best_picture->get_enlarged_img_url();

	my $picture_url = sprintf(qq(https://yellowleaf.org/scramble/%s),
                                  $best_picture->get_enlarged_img_url());
	# The "../.." in the URL was stopping Feedly from displaying
	# an picture in the feed preview.
	$picture_url =~ s{\.\./\.\./}{};

        my $trip_url = sprintf("https://yellowleaf.org/scramble/%s",
				 $trip->get_trip_page_url());
	$trip_url =~ s{\.\./\.\./}{};

	my $picture_html = sprintf(qq(<a href="%s"><img src="%s" alt="%s"></a>),
                                   $trip_url,
                                   $picture_url,
                                   $best_picture->get_description());
	my $description = qq(<![CDATA[$picture_html]]>);

	$rss->add_item(title => $trip->get_name(),
		       link => $trip_url,
		       description => $description,
		       content => {
			   encoded => $description,
		       },
		       enclosure => { url => $picture_url,
				      type => $mime->mimeTypeOf($best_picture->get_filename()),
				  });
    }

    $writer->create("r/rss.xml", $rss->as_string());
}

1;
