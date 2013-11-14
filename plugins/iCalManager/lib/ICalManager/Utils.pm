package ICalManager::Utils;
use strict;
use warnings;

require Exporter;
our @EXPORT = qw{get_plugin_blog};

sub get_plugin {
    my ($opts) = @_;
    if (exists $opts->{plugin}) {
        return $opts->{plugin};
    }
    if (not exists $opts->{app}) {
        $opts->{app} = MT->instance;
    }
    my $mt = $opts->{app};
    my $plugin = $opts->{plugin} = $mt->component('icalmanager');
    return $plugin;
}

sub get_plugin_blog {
    my ($opts) = @_;
    my $plugin = get_plugin($opts);
    my $mt = $opts->{app} ||= MT->instance;
    my $blog_id = $plugin->get_config_value('managed_blog', 'system');
    my $blog = $mt->model('blog')->load($blog_id);
    return $blog;
}

sub get_incoming_ical_path {

}

sub get_outgoing_ical_path {
    my ($entry, undef, $opts) = @_;
    my $blog = get_plugin_blog($opts);
    require File::Spec;
    return File::Spec->catdir($blog->sitepath,  'icals', $entry->author_id, $entry->id);
}

my @chars = ('a'..'z', 'A'..'Z', '0'..'9');

sub create_rand_token {
    my $token = join '', map $chars[int(rand(scalar(@chars)))], 1..12;
    return $token; 
}

1;
