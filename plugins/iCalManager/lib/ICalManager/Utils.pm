package ICalManager::Utils;
use strict;
use warnings;

require Exporter;
our @EXPORT = qw{get_plugin_blog};

sub get_plugin_blog {
    my %opts = @_;
    my $plugin;
    if (exists $opts{plugin}) {
        $plugin = $opts{plugin};
    }
    else {
        my $mt = $opts{app} || MT->instance;
        $plugin = $mt->component('icalmanager');
    }
    return $plugin->get_config_value('managed_blog', 'system');
}

1;
