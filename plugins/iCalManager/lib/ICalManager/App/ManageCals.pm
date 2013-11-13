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
    require ICalManager::Utils;
    my $name = $app->param('name');
    my $entry = $app->model('entry')->new();
    $entry->author_id( $user->id );
    $entry->title( $name );
    my $public_token = ICalManager::Utils::create_rand_token();
    my $private_token = ICalManager::Utils::create_rand_token();
    my $path = ICalManager::Utils::get_outgoing_ical_path($entry, undef, { app=>$app });
    require File::Spec;
    my $out_cal = {
        private_token => $private_token,
        public_token => $public_token,
        id => 1,
        private_file => File::Spec->catdir($path, "pr_1_$private_token.ics"),
        public_file => File::Spec->catdir($path, "pu_1_$public_token.ics"),
    };
    my $data = {
        max_index => 1,
        incoming => [],
        outgoing => [ $out_cal ],
    };
    require MT::Util::YAML;
    $entry->text(MT::Util::YAML::Dump($data));
    $entry->save();
    my $baseurl = join('/', $blog->siteurl, 'icals', $entry->author_id, $entry->id);
    return $app->json_result({ 
        new_id => $entry->id,
        name => $name,
        url_public => "$baseurl/pu_1_$public_token.ics",
        url_private => "$baseurl/pu_1_$private_token.ics",
    });
}

sub delete_group {
    my $app = shift;
    my $user = $app->get_loggedin_user('approved')
        or return;
    my $blog = $app->blog();
    require MT::Util::YAML;
    my $entry_id = $app->param('group_id');
    my $entry = $app->model('entry')->load($entry_id)
        or return $app->json_error('Invalid Request.');
    $entry->author_id == $user->id
        or return $app->json_error('Invalid Request.');
    $entry->delete();
    return $app->json_result({status => 'success'});
}

sub add_incoming {
    my $app = shift;
    my $user = $app->get_loggedin_user('approved')
        or return;
    my $blog = $app->blog();
    require MT::Util::YAML;
    my $entry_id = $app->param('group_id');
    my $entry = $app->model('entry')->load($entry_id)
        or return $app->json_error('Invalid Request.');
    $entry->author_id == $user->id
        or return $app->json_error('Invalid Request.');

    my $data = MT::Util::YAML::Load( $entry->text );
    my $url = $app->param('url');
    my $cal_id = $data->{max_index} + 1;
    $data->{max_index} = $cal_id;
    my $filename = File::Spec->catdir( 
        $app->plugin->get_config_value('managed_blog', 'system'),
        $user->id, $entry->id, $cal_id . '.ics' );
    my $rec = {
        url => $url,
        id => $cal_id,
        filename => $filename,
    };
    push @{ $data->{incoming} }, $rec;
    $entry->text(MT::Util::YAML::Dump($data));
    $entry->save();
    return $app->json_result({status => 'success'});
}

sub remove_incoming {
    my $app = shift;
    my $user = $app->get_loggedin_user('approved')
        or return;
    my $blog = $app->blog();
    require MT::Util::YAML;
    my $entry_id = $app->param('group_id');
    my $entry = $app->model('entry')->load($entry_id)
        or return $app->json_error('Invalid Request.');
    $entry->author_id == $user->id
        or return $app->json_error('Invalid Request.');
    my $cal_id = $app->param('cal_id');

    my $data = MT::Util::YAML::Load( $entry->text );

    if (not grep { $_->{id} == $cal_id } @{$data->{incoming}}) {
        return $app->json_error('Can not find the calendar to delete');
    }
    my @new_incals = grep { $_->{id} == $cal_id } @{$data->{incoming}};
    $data->{incoming} = \@new_incals;

    $entry->text(MT::Util::YAML::Dump($data));
    $entry->save();
    return $app->json_result({status => 'success'});
}

1;
