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
        'last_update'       => 'datetime',
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

1;
