package ICalManager::Updater;
use strict;
use warnings;
use MT;
use MT::Util qw{epoch2ts};
use HTTP::Request;
use LWP::UserAgent;
use ICalManager::Utils qw{get_plugin_blog};

# main
# https://www.google.com/calendar/ical/shmuelfomberg%40gmail.com/public/basic.ics

# input1
# https://www.google.com/calendar/ical/r9lsqjpbu43pdv951uchi7qjjc%40group.calendar.google.com/private-f9c28b6e29dfc882b78c88e850f1765c/basic.ics
# input2
# https://www.google.com/calendar/ical/chknvtgjrtnv5a1dariuolatrk%40group.calendar.google.com/private-a3196475b9e469b6a3ff7288d2433976/basic.ics

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
                my $was_updated = fetch_cal($mt, $plugin, $cal);
                $cal->{last_query} = epoch2ts(undef, time, 1);
                next unless $was_updated;
                $update = 1;
            }
        }
    }
}

sub fetch_cal {
    my ($mt, $plugin, $cal) = @_;
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
    my $cal_file = $cal->cal_file($mt, $plugin);
    open my $fh, ">", $cal_file or die "failed to open $cal_file";
    print $fh $res->content();
    close $fh;
    return 1;
}

1;
