package ICalManager::Combiner;
use strict;
use warnings;
use Text::vFile::asData;

my $vFileParser = Text::vFile::asData->new();

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw{ combine_icals };

sub combine_icals {
    my ($incoming, $outgoing) = @_;

    my @in_cals;
    foreach my $ical (@$incoming) {
        next unless -e $ical->{filename};
        my $data = read_ical_file($ical->{filename});
        push @in_cals, $data;
    }

    my @inner_cals = grep { $_->{type} eq 'VCALENDAR' } map { @{ $_->{objects} } } @in_cals;
    my @objects = map { @{ $_->{objects} } } @inner_cals;
    my @time_objs = 
        sort { -1 * ( $a->{properties}{DTSTART}[0]{value} cmp $b->{properties}{DTSTART}[0]{value} ) } 
        grep { exists $_->{properties} and exists $_->{properties}{DTSTART} } 
        @objects;
    my @non_time_objs = 
        grep { not exists $_->{properties} or not exists $_->{properties}{DTSTART} } 
        @objects;

    my %new_cal_props = (
        type => 'VCALENDAR',
        properties => {  
            PRODID => [{ value => '-//Shmuel Fomberg//iCal Aggregator//EN' }],
            VERSION => [{ value => '2.0' }],
        },
    );

    foreach my $ical (@$outgoing) {
        if (my $filename = $ical->{private_file}) {
            my $new_cal = { 
                %new_cal_props, 
                objects => [ @time_objs, @non_time_objs ], 
            };
            write_ical_file($new_cal, $filename);
        }
        if (my $filename = $ical->{public_file}) {
            my $new_cal = { 
                %new_cal_props, 
                objects => privatize_cal_objs([ @time_objs, @non_time_objs ]), 
            };
            write_ical_file($new_cal, $filename);
        }
    }

    return 1;
}

sub privatize_cal_objs {
    my $inobjs = shift;
    my @out;
    foreach my $obj (@$inobjs) {
        if ($obj->{type} ne 'VEVENT') {
            push @out, $obj;
            next;
        }
        my %properties;
        foreach my $name (qw{DTSTART DTEND DTSTAMP UID}) {
            $properties{$name} = $obj->{properties}->{$name} if exists $obj->{properties}->{$name};
        }
        $properties{SUMMARY} = [{ value => 'Busy' }];
        my $new = {
            type => 'VFREEBUSY',
            properties => \%properties,
        };
        push @out, $new;
    }
    return \@out;
}

sub read_ical_file {
    my ($filename) = @_;
    open my $fh, "<", $filename or die "couldn't open ics: $!";
    my $data = $vFileParser->parse( $fh );
    close $fh;
    return $data;
}

sub write_ical_file {
    my ($new_cal, $filename) = @_;
    open my $fh, ">", $filename or die "couldn't open ics to write: $!";
    my @content = $vFileParser->generate_lines($new_cal);
    print $fh join("\n", @content), "\n";
    close $fh;
}

1;
