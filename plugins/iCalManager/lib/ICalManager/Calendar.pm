package ICalManager::Calendar;
use strict;
use warnings;

use base qw( MT::Object );

__PACKAGE__->install_properties ({
    column_defs => {
        'id'                => 'integer not null auto_increment',
        'author_id'         => 'integer not null',
        'url'               => 'string(255) not null',
        'name'              => 'string(255) not null',
        'is_active'         => 'boolean not null',
        'last_update'       => 'string(255)', # as got from the website
        'last_status'       => 'string(255)',
        'last_query'        => 'datetime',
        'group_id'          => 'integer not null',
    },
    indexes => {
        group => { columns => [qw{ author_id group_id }] }, 
    },
    datasource  => 'ical_cal',
    primary_key => 'id',
    class_type  => 'ical_cal',
});

sub cal_file {
    my ($self, $mt, $plugin) = @_;
    require File::Spec;
    my $user_dir = File::Spec->catdir( $mt->static_file_path, 'calendars', $self->author_id );
    if (not -d $user_dir) {
        require File::Path;
        File::Path::make_path($user_dir);
    }
    return File::Spec->catdir( $user_dir, $self->id) . ".ics";
}

1;
