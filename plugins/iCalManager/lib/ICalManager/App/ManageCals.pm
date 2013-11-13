package ICalManager::App::ManageCals;
use strict;
use warnings;

sub list {
    my $app = shift;
    my $user = $app->get_loggedin_user('approved')
        or return;
    my $blog = $app->blog();
    require MT::Util::YAML;

    my $entries = $app->model('entry')->load_iter({ blog_id => $blog->id, author_id => $user->id });
    my @cal_groups;
    while (my $entry = $entries->()) {
        my $data = MT::Util::YAML::Load( $entry->text );
        my $rec = {
            title => $entry->title();
            incoming => $data->{incoming};
            outgoing => $data->{outgoing};
        };
        push @cal_groups, $rec;
    }
    my $params = {
        nickname => $user->nickname(),
        cal_groups => \@cal_groups,
        token => $app->{session}->id,
    };
    return $app->plugin->load_tmpl('cal_list.tmpl', $params);
}

sub new_group {
    my $app = shift;
    my $user = $app->get_loggedin_user('approved')
        or return;
    my $blog = $app->blog();
    require MT::Util::YAML;
    my $name = $app->param('name');
    my $entry = $app->model('entry')->new();
    $entry->author_id( $user->id );
    $entry->title( $name );
    my $data = {
        max_index => 1,
        incoming => [],
        outgoing => [ $out_cal ],
    };
    require MT::Util::YAML;
    $entry->text(MT::Util::YAML::Dump($data));
    $entry->save();
    return $app->json_result({ 
        new_id => $entry->id,
        name => $name,
        url_public => $url_public,
        url_private => $url_private,
    });
}

1;
