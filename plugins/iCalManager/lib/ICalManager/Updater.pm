package ICalManager::Updater;
use strict;
use warnings;
use MT;
use HTTP::Request;
use LWP::UserAgent;

# https://www.google.com/calendar/ical/shmuelfomberg%40gmail.com/public/basic.ics

my $ua = LWP::UserAgent->new( 
    agent => 'iCalendar Collector', 
    timeout => MT->config->HTTPTimeout,
    keep_alive => 10, 
);

sub update_all_cals {
    my $mt      = MT->instance;
    my $plugin  = $mt->component('icalmanager');
    my $authors_iter = $mt->model('author')->load_iter({ type => 1 });
    while (my $author = $authors_iter->()) {
        my $groups = $author->meta( 'groups' );
        next unless defined $groups and @$groups > 0;
        foreach my $group (@$groups) {
            my ($group_id, $name) = split ',', $group, 2;
            my $update = 0;
            my @g_cals = $mt->model('ical_cal')->load( 
                { author_id => $author->id, group_id => $group_id } );
            foreach my $cal ($g_cals) {
                my $was_updated = fetch_cal($mt, $plugin, $cal);
                next unless $was_updated;
                $update = 1;
            }
        }
    }
}

sub fetch_cal {
    my ($mt, $plugin, $cal) = @_;
    if ($cal->last_update) {
        my $req  = HTTP::Request->new( HEAD => $cal->url );
        # If-Modified-Since:Fri, 18 Oct 2013 04:40:51 GMT
        # Cache-Control:max-age=0
        $req->headers->header('If-Modified-Since' => 0)
        my $res = $ua->request($req);
    }
}

1;
