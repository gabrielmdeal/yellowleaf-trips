package Scramble::SpellCheck;

use strict;

use Scramble::Logger ();
use Spell ();

sub check_spelling {
    my ($dictionary_dir) = @_;

    Spell::initialize($dictionary_dir);
    _add_words();

    my @misspelled = _check_spelling_in_all_documents();

    if (@misspelled) {
        die join("\n", @misspelled) . "\n";
    }
}

sub _add_words {
    Scramble::Logger::verbose("Adding words to the dictionary...");
    my $location_collection = Scramble::Model::Location::get_all();
    foreach my $location ($location_collection->get_all()) {
        Spell::add_words($location->get_name());
        foreach my $aka ($location->get_aka_names()) {
            Spell::add_words($aka);
        }
    }

    foreach my $id (Scramble::Model::Reference::get_ids()) {
        Spell::add_words($id);
    }
}

sub _check_spelling_in_all_documents {
    Scramble::Logger::verbose("Checking spelling...");

    my @misspelled;

    foreach my $report (Scramble::Model::Report::get_all()) {
        my @texts;
        push @texts, $report->get_route() if defined $report->get_route();
        push @texts, $report->get_name();
        push @texts, $report->get_type();
        foreach my $text (@texts) {
            push @misspelled, _check_spelling_in_text($text, $report->get_filename(), $report->get_start_date());
        }
    }

    foreach my $image (Scramble::Model::Image::get_all_images_collection()->get_all()) {
        foreach my $text ($image->get_description(), $image->get_of(), $image->get_from(), $image->get_section_name()) {
            push @misspelled, _check_spelling_in_text($text, $image->get_source_directory(), $image->get_date());
        }
    }

    return @misspelled;
}

sub _check_spelling_in_text {
    my ($text, $name, $date) = @_;

    return unless defined $text;

    my @misspelled = Spell::check($text);
    return unless @misspelled;

    my $message = "Misspelled in " . $name . ": @misspelled.";
    if (defined $date && $date gt '2007/07/01') {
        return ($message);
    } else {
        print "$message\n";
        return ();
    }
}

1;
