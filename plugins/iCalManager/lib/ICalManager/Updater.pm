package ICalManager::Updater;
use strict;
use warnings;
use MT;
use MT::Util qw{epoch2ts};
use HTTP::Request;
use LWP::UserAgent;
use ICalManager::Utils qw{get_plugin_blog};
use ICalManager::Combiner qw{combine_icals};

# iCal validetor
# http://severinghaus.org/projects/icv/

# main
# https://www.google.com/calendar/ical/shmuelfomberg%40gmail.com/public/basic.ics

# input1
# https://www.google.com/calendar/ical/r9lsqjpbu43pdv951uchi7qjjc%40group.calendar.google.com/private-f9c28b6e29dfc882b78c88e850f1765c/basic.ics
# input2
# https://www.google.com/calendar/ical/chknvtgjrtnv5a1dariuolatrk%40group.calendar.google.com/private-a3196475b9e469b6a3ff7288d2433976/basic.ics

# Exmaple YAML data:
# incoming:
#   - last_update: datetime string, as got from the request header
#     url: source ical position
#     last_status: last request status
#     id: numaric id inside this group
#     filename: full path name
# outgoing:
#   - private_file: full path filename for full calendar
#     public_file: full path filename contains only freebusy info
#     private_token: token for private_file
#     public_token: token for public_file
#     id: numerical id inside this group
# max_index: the current max calendar index

my $ua = LWP::UserAgent->new( 
    agent => 'iCalendar Collector', 
    timeout => MT->config->HTTPTimeout,
    keep_alive => 10, 
);

sub update_all_cals {
    my $mt      = MT->instance;
    my $plugin  = $mt->component('icalmanager');
    my $blog_id = get_plugin_blog(plugin => $plugin);
    require MT::Util::YAML;

    my $authors_iter = $mt->model('author')->load_iter({ type => 1 });
    while (my $author = $authors_iter->()) {
        my $entries = $mt->model('entry')->load_iter({ blog_id => $blog_id, author_id => $author->id });
        while (my $entry = $entries->()) {
            my $data = MT::Util::YAML::Load( $entry->text );
            my $update = 0;
            foreach my $cal (@{ $data->{incoming} }) {
                my $was_updated = fetch_cal($plugin, $entry, $cal);
                $cal->{last_query} = epoch2ts(undef, time, 1);
                next unless $was_updated;
                $update = 1;
            }
            if ($update) {
                combine_icals($data->{incoming}, $data->{outgoing});
            }
            $entry->text(MT::Util::YAML::Dump($data));
            $entry->save();
        }
    }
}

sub fetch_cal {
    my ($plugin, $entry, $cal) = @_;
    if ($cal->{last_update}) {
        my $req  = HTTP::Request->new( HEAD => $cal->{url} );
        # If-Modified-Since:Fri, 18 Oct 2013 04:40:51 GMT
        # Cache-Control:max-age=0
        $req->headers->header('If-Modified-Since' => $cal->{last_update});
        my $res = $ua->request($req);
        return 0 if $res->code == 304;
    }

    my $req  = HTTP::Request->new( GET => $cal->{url} );
    my $res = $ua->request($req);
    $cal->{last_status} = $res->code . "," . $res->message;
    return 0 unless $res->is_success;
    $cal->{last_update} = $res->headers->header('Date');
    if (not $cal->{filename}) {
        require File::Spec;
        $cal->{filename} = File::Spec->catdir(
                $plugin->get_config_value('incoming_dir', 'system'),  
                $entry->author_id, $entry->id, $cal->{id} . '.ics');
    }
    open my $fh, ">", $cal->{filename} or die "failed to open $cal->{filename}";
    print $fh $res->content();
    close $fh;
    return 1;
}

1;
