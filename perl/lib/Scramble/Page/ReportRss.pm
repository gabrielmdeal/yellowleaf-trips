package Scramble::Page::ReportRss;

use strict;

use Scramble::Misc ();

sub create {
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
    foreach my $report (Scramble::Model::Report::get_all()) {
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

1;
