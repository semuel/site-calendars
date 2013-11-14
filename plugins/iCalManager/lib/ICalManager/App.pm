package ICalManager::App;
use strict;
use warnings;
use base qw( MT::App );

my $plugin;

sub id {'icalmanager'}

sub script_name { MT->config->PluginDirectoryScript }

sub app_uri {
    my $app = shift;
    $app->base . $app->app_path . $app->script . $app->uri_params(@_);
}

sub blog {
	my $self = shift;
	require ICalManager::Utils;
	return ICalManager::Utils::get_plugin_blog({plugin => $plugin});
}

sub init {
    my $app = shift;
    $app->SUPER::init(@_);
    $app->{default_mode}         = 'login';
    $app->{plugin_template_path} = '';
    $app->{component} = 'icalmanager';
    $app->plugin();
    return $app;
}

sub plugin {
    my $app = shift;
    $plugin ||= $app->component('icalmanager')
        or die $app->translate("Cannot keep a plugin reference");
    return $plugin;
}

sub validate_magic {
    my $app = shift;
    return 1
        if $app->param('username')
        && $app->param('password')
        && $app->request('fresh_login');
    return undef
        unless ( $app->current_magic || '' ) eq
        ( $app->param('magic_token') || '' );
    1;
}

sub json_result {
    my $app = shift;
    my ( $result, $format ) = @_;
    my $jsonp;
    if ( defined $format and $format eq 'jsonp' ) {
        $jsonp = $app->param('jsonp');
        return $app->errtrans("Invalid request.")
            unless defined $jsonp and $jsonp =~ m/^\w+$/;
    }
    $app->{no_print_body} = 1;
    my $json = MT::Util::to_json($result);
    if ( defined $jsonp ) {
        $app->send_http_header("text/javascript");
        $app->print_encode("$jsonp($json);");
    }
    else {
        $app->send_http_header("application/json");
        $app->print_encode("$json");
    }
    return undef;
}

sub json_error {
    my $app = shift;
    my ( $error, $format ) = @_;
    return $app->json_result( { error => $error }, $format );
}

sub get_user {
    my ( $app, $is_post ) = @_;

    # Check if commenter is logged in
    my %cookies     = $app->cookies();
    my $cookie_name = $app->commenter_session_cookie_name;
    return unless $cookies{$cookie_name};

    my $state
        = $app->unbake_user_state_cookie( $cookies{$cookie_name}->value() );
    my $session_key = $state->{sid} || '';
    $session_key =~ y/+/ /;
    require MT::Session;
    my $sess_obj = MT::Session->load( { id => $session_key } );
    return unless $sess_obj;

    my $timeout = $app->config->CommentSessionTimeout;
    $timeout += 60 * 60 if $is_post;

    if ( $sess_obj->start() + $timeout < time ) {
        $app->_invalidate_commenter_session( \%cookies );
        return;
    }

    my $user = $app->model('author')->load( { name => $sess_obj->name } );
    return unless $user;
    return ( $user, $sess_obj );
}

sub get_loggedin_user {
    my $app           = shift;
    my @options       = @_;
    my $blog_id       = $app->param('blog_id');
    my %avail_options = map { ( $_ => 1 ) } 'http post';
    if ( my ($opt) = grep { not exists $avail_options{$_} } @options ) {
        die $plugin->translate( 'Illigal option in [_1]: [_2].',
            'get_loggedin_user', $opt );
    }

    my $is_post = $app->request_method eq 'POST' ? 1 : 0;
    if ( grep { $_ eq 'http post' } @options ) {
        die $plugin->translate("Expected POST request.") unless $is_post;
    }

    my $failed_redirect = sub {
        my $return_to;
        if ($is_post) {
            $return_to = $app->param('return_to');
        }
        else {
            $return_to
                = $app->app_path . $app->script . '?' . $app->query_string();
            if ( $return_to =~ m!^/! ) {
                my $site = $app->blog->site_url;
                my ($host) = $site =~ m!^(https?://[^/]+)!;
                $return_to = $host . $return_to;
            }
        }
        return $app->redirect(
            $app->app_uri(
                mode => 'login',
                args => { blog_id => $blog_id, return_to => $return_to }
            )
        );
    };

    my ( $user, $sess_obj ) = $app->get_user($is_post)
        or return $failed_redirect->();

    $app->{session} = $sess_obj;

    if ( $is_post
        and ( ( $app->param('magic_token') || '' ) ne $sess_obj->id ) )
    {
        return $failed_redirect->();
    }

    $app->user($user);
    return $user;
}

sub start_recover {
    my ( $app, $params ) = @_;
    require MT::CMS::Tools;
    return MT::CMS::Tools::start_recover( $app, $params );
}

1;
