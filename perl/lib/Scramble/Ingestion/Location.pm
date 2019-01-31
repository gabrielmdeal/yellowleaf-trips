package Scramble::Ingestion::Location;

use strict;

use Getopt::Long ();
use IO::File;
use Scramble::Misc ();
use Scramble::Ingestion::PeakList::ListsOfJohn ();

my @g_options = qw(
    name=s
    output-directory=s
    );
my %g_options = ();

sub create {
    get_options();

    my @peaks;
    foreach my $name (keys %Scramble::Ingestion::PeakList::ListsOfJohn::Peaks) {
        next unless $name =~ /$g_options{name}/i;
        push @peaks, values %{ $Scramble::Ingestion::PeakList::ListsOfJohn::Peaks{$name} };
    }
    if (! @peaks) {
        printf("Lists of John has no such peak '%s'", $g_options{name});
        return 1;
    }

    my @choices = map {
        {
            name => "$_->{name} ($_->{quad})",
            value => $_,

        }
    } @peaks;
    my $peak = Scramble::Misc::choose_interactive(@choices);

    my $filename = Scramble::Misc::sanitize_for_filename($peak->{name});
    $filename = $g_options{'output-directory'} . "/$filename.xml";
    die "$filename already exists" if -e $filename;

    my $xml = make_location_xml($peak);

    my $fh = IO::File->new($filename, "w") or die "Can't open $filename: $!";
    $fh->print($xml);
    $fh->close;

    print "Created $filename\n";

    return 0;
}

sub usage {
    my ($prog) = ($0 =~ /([^\/]+)$/);
    print("Usage: $prog [ OPTIONS ]\nOptions:\n\t--"
          . join("\n\t--", @g_options));
}

sub get_options {
    local $SIG{__WARN__};
    if (! Getopt::Long::GetOptions(\%g_options, @g_options)
        || $g_options{'help'})
    {
        print usage();
        exit 1;
    }

    foreach my $required (qw(name output-directory)) {
        die "Missing --$required" unless exists $g_options{$required};
    }
}

sub make_location_xml {
    my ($peak) = @_;

    my $unofficial_name = $peak->{'unofficial-name'} ? 1 : 0;

    return <<EOT;
<location
    type="peak"
    elevation="$peak->{elevation}"
    prominence="$peak->{prominence}"
>

    <name value="$peak->{name}"
          unofficial-name="$unofficial_name"
    />

    <coordinates datum="WGS84"
                 latitude="$peak->{coordinates}{latitude}"
    	     longitude="$peak->{coordinates}{longitude}"
    />

    <areas>
        <area id="WA"/>
        <area id="$peak->{quad}"/>
    </areas>

</location>
EOT
}

1;