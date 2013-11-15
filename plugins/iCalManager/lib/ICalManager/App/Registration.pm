package ICalManager::App::Registration;
use strict;
use warnings;

use MT::Util
    qw( remove_html multi_iter encode_js is_url encode_url decode_url epoch2ts ts2epoch format_ts dirify encode_html );

sub public_login {
    my $app = shift;
    my $q   = $app->param;
    my %opt = @_;

    require MT::Lockout;
    if ( MT::Lockout->is_locked_out( $app, $app->remote_ip ) ) {
        $app->{hide_goback_button} = 1;
        return $app->errtrans("Invalid request.");
    }

    $opt{error} = encode_html( $q->param('error') )
        if defined $q->param('error');

    my $blog = $app->blog();

    my $return_to = $q->param('return_to') || $q->param('return_url');
    if ($return_to) {
        $return_to = remove_html($return_to);
        return $app->errtrans('Invalid request.')
            unless is_url($return_to);
    }

    my $tmpl = $app->plugin->load_tmpl('login.tmpl')
        or return $app->errtrans("No login form template defined");
    my $param = {
        blog_id   => $blog->id,
        return_to => $return_to,
    };
    my $cfg = $app->config;
    if ( my $registration = $cfg->CommenterRegistration ) {
        if ( $cfg->AuthenticationModule eq 'MT' ) {
            $param->{registration_allowed} = $registration->{Allow} ? 1 : 0;
            $param->{registration_allowed} = 0
                if ( $blog && !$blog->allow_commenter_regist );
        }
    }
    $param->{ 'auth_mode_' . $cfg->AuthenticationModule } = 1;
    require MT::Auth;
    $param->{can_recover_password} = MT::Auth->can_recover_password;
    $param->{error} = $opt{error} if exists $opt{error};
    $param->{message} = $app->param('message') if $app->param('message');
    $param->{error}   = $param->{error};
    $param->{message} = encode_html( $param->{message} );
    $param->{system_template} = 1;

    if ( !$blog ) {
        require MT::Blog;
        $blog = MT::Blog->new();
        $blog->commenter_authenticators( MT->config('DefaultCommenterAuth') );
    }

    my $external_authenticators
        = $app->external_authenticators( $blog, $param );

    if (@$external_authenticators) {
        $param->{auth_loop}      = $external_authenticators;
        $param->{default_signin} = $external_authenticators->[0]->{key}
            unless exists $param->{default_signin};
    }

    $tmpl->param($param);
    $tmpl;
}

# mostly copied over from MT::App::Community
sub do_login {
    my $app     = shift;
    my $q       = $app->param;
    my $name    = $q->param('username');
    my $blog_id = $q->param('blog_id');
    my $blog    = MT::Blog->load($blog_id);
    my $auths   = $blog->commenter_authenticators;
    if ( $blog && $auths !~ /MovableType/ ) {
        $app->log(
            {   message => $app->translate(
                    'Invalid commenter login attempt from [_1] to blog [_2](ID: [_3]) which does not allow Movable Type native authentication.',
                    $name, $blog->name, $blog_id
                ),
                level    => MT::Log::WARNING(),
                category => 'login_commenter',
            }
        );
        return $app->login_form( error => $app->translate('Invalid login.') );
    }

    require MT::Auth;
    my $ctx = MT::Auth->fetch_credentials( { app => $app } );
    $ctx->{blog_id} = $blog_id;
    my $result = MT::Auth->validate_credentials($ctx);

    $app->run_callbacks( 'post_signin.app', $app, $result );

    my ( $message, $error );
    if (   ( MT::Auth::NEW_LOGIN() == $result )
        || ( MT::Auth::NEW_USER() == $result )
        || ( MT::Auth::SUCCESS() == $result ) )
    {
        my $user = $app->user;
        if ( $q->param('external_auth') && !$user ) {
            $app->param( 'name', $name );
            if ( MT::Auth::NEW_USER() == $result ) {
                $user = $app->_create_commenter_assign_role(
                    $q->param('blog_id') );
                return $app->login_form(
                    error => $app->translate('Invalid login') )
                    unless $user;
            }
            elsif ( MT::Auth::NEW_LOGIN() == $result ) {
                my $registration = $app->config->CommenterRegistration;
                unless (
                       $registration
                    && $registration->{Allow}
                    && ( $app->config->ExternalUserManagement
                        || ( $blog && $blog->allow_commenter_regist ) )
                    )
                {
                    return $app->login_form(
                        error => $app->translate(
                            'Successfully authenticated but signing up is not allowed.  Please contact system administrator.'
                        )
                    ) unless $user;
                }
                else {
                    return $app->login_form( error =>
                            $app->translate('You need to sign up first.') )
                        unless $user;
                }
            }
        }
        MT::Auth->new_login( $app, $user );
        my $status = $user->status;
        if ( $status == MT::Author::APPROVED() ) {
            my $return_to = commenter_loggedin( $app, $user, $blog_id );
            if ( !$return_to ) {
                return $app->load_tmpl(
                    'error.tmpl',
                    {   error              => $app->errstr,
                        hide_goback_button => 1,
                    }
                );
            }

            return $app->redirect($app->app_uri(mode => 'list'));
        }
        $error   = $app->translate("Permission denied.");
        $message = $app->translate(
            "Login failed: permission denied for user '[_1]'", $name );
    }
    elsif ( MT::Auth::PENDING() == $result ) {
        my $user = $app->user;
        my $return_to = commenter_loggedin( $app, $user, $blog_id );
        if ( !$return_to ) {
            return $app->load_tmpl(
                'error.tmpl',
                {   error              => $app->errstr,
                    hide_goback_button => 1,
                }
            );
        }
        return $app->redirect( $app->app_uri(mode => 'request_payment'));

    }
    elsif (MT::Auth::INVALID_PASSWORD() == $result
        || MT::Auth::SESSION_EXPIRED() == $result )
    {
        $message = $app->translate(
            "Login failed: password was wrong for user '[_1]'", $name );
    }
    elsif ( MT::Auth::INACTIVE() == $result ) {
        my ($user) = $app->model('author')->search(
            {   name      => $name,
                type      => MT::Author::AUTHOR,
                auth_type => 'MT',
                status    => MT::Author::INACTIVE(),
            }
        );
        require MT::Session;
        my $sess
            = MT::Session->load(
            { kind => 'CR', email => $user->email, name => $user->id },
            );
        if ($sess) {
            my $url = $app->app_uri(
                mode => 'resend_auth',
                args => { blog_id => $blog_id, id => $user->id }
            );
            $error = $app->translate(
                'Before you can sign in, you must authenticate your email address. <a href="[_1]">Click here</a> to resend the verification email.',
                $url
            );
        }
        else {
            $message
                = $app->translate(
                "Failed login attempt by disabled user '[_1]'", $name );
        }
    }
    elsif ( MT::Auth::LOCKED_OUT() == $result ) {
        $message = $app->translate('Invalid login.');
    }
    else {
        $message
            = $app->translate( "Failed login attempt by unknown user '[_1]'",
            $name );
    }
    $app->log(
        {   message  => $message,
            level    => MT::Log::SECURITY(),
            category => 'login_commenter',
        }
    ) if $message;
    $ctx->{app} ||= $app;
    MT::Auth->invalidate_credentials($ctx);
    return public_login( $app,
        error => $error || $app->translate("Invalid login") );
}

sub commenter_loggedin {
    my $app = shift;
    my $q   = $app->param;
    my ( $user, $blog_id ) = @_;

    my $blog = $app->model('blog')->load($blog_id)
        or return $app->errtrans("Invalid parameter");

    my $return_to = $q->param('return_to') || $q->param('return_url');
    if ($return_to and index($return_to, $blog->site_url) == 0) {
        $return_to = remove_html($return_to);
        $return_to =~ s/#.*//;
        return $app->errtrans('Invalid request.')
            unless is_url($return_to);
    }
    else {
        $return_to = $blog->site_url;
        $q->param( 'return_to', $return_to );
    }

    # If the target of the login is inside the app, we can't use the
    # commenter way, and need to bake cookie
    my $internal_login;
    if ( index( $return_to, $app->script ) == 0 ) {
        $internal_login = 1;
    }
    elsif ( index( $return_to, $app->app_path . $app->script ) == 0 ) {
        $internal_login = 1;
    }
    elsif ( $app->app_path =~ m!^/! ) {
        my $site = $app->blog->site_url;
        my ($host) = $site =~ m!^(https?://[^/]+)!;
        if ( index( $return_to, $host . $app->app_path . $app->script ) == 0 )
        {
            $internal_login = 1;
        }
    }

    my $sess = $app->make_commenter_session($user);

    my $url;
    if ($internal_login) {
        my $timeout
            = $app->param('remember')
            ? '+3650d'
            : '+' . $app->config->CommentSessionTimeout . 's';
        my $string = '';
        $string .= "name:'" . $user->nickname . "';";
        $string .= "email:'" . $user->email . "';";
        $string .= "is_authenticated:'1';";
        $string .= "userpic:'" . scalar( $user->userpic_url ) . "';";
        $string .= "sid:'" . $sess . "';";
        $string
            .= "is_trusted:'1';is_author:'1';is_banned:'0';can_post:'1';can_comment:'1'";
        $string = MT::Util::escape_unicode($string);
        my %kookee = (
            -name    => "mt_blog_user",
            -value   => $string,
            -path    => '/',
            -expires => $timeout,
        );
        $app->bake_cookie(%kookee);
        $url = $return_to;
    }
    else {
        my $ott = MT->model('session')->new();
        $ott->kind('OT');    # One time Token
        $ott->id( MT::App::make_magic_token() );
        $ott->start(time);
        $ott->duration( time + 5 * 60 );
        $ott->set( sid => $sess );
        $ott->save
            or return $app->error(
            $app->translate(
                "The login could not be confirmed because of a database error ([_1])",
                $ott->errstr
            )
            );
        $url = $return_to . '#_login_' . $ott->id;
    }

    unless ( $app->is_valid_redirect_target ) {
        return $app->error(
            $app->translate(
                q{You are trying to redirect to external resources: [_1]},
                encode_html($return_to)
            )
        );
    }

    return $url;
}

sub logout {
    my $app = shift;

    $app->MT::App::logout();

    return $app->redirect( $app->blog->site_url );
}

sub register {
    my $app  = shift;
    my %opts = @_;
    my $q    = $app->param;
    my $blog = $app->blog;

    my $param = {
        %opts,
    };

    my $cfg          = $app->config;
    my $registration = $cfg->CommenterRegistration
        or return $app->errtrans("Invalid parameter");

    return $app->errtrans('Signing up is not allowed.')
        unless $registration->{Allow}
        && ( !$blog || ( $blog && $blog->allow_commenter_regist ) );

    if (my $provider = MT->effective_captcha_provider(
            $blog ? $blog->captcha_provider : undef
        )
        )
    {
        $param->{captcha_fields}
            = $provider->form_fields( $blog ? $blog->id : undef );
    }
    $param->{ 'auth_mode_' . $cfg->AuthenticationModule } = 1;

  # $param->{field_loop} = field_loop( object_type => 'author', simple => 1 );

    my $tmpl = $app->load_blogsys_tmpl('register_form')
        or return $app->errtrans("No register form template defined");

    $param->{system_template} = 1;
    $tmpl->param($param);
    return $tmpl;
}

sub do_register {
    my $app = shift;
    my $q   = $app->param;

    return $app->error( $app->translate("Invalid request.") )
        if $app->request_method() ne 'POST';

    my $cfg   = $app->config;
    my $param = {};
    $param->{$_} = $q->param($_) foreach qw(email url username nickname);
    $param->{ 'auth_mode_' . $cfg->AuthenticationModule } = 1;

    my $blog = $app->blog;
    my $blog_id = $blog->id;

    # Willingness of the Movable Type instance and the blog itself
    # to allow users to register must be checked before a pending
    # user is created.
    my $registration = $cfg->CommenterRegistration;

    return $app->errtrans("Invalid parameter")
        unless $registration;

    return $app->errtrans('Signing up is not allowed.')
        unless $registration->{Allow}
        && ( !$blog || ( $blog && $blog->allow_commenter_regist ) );

    my $filter_result = $app->run_callbacks( 'api_save_filter.author', $app );

    $app->param( 'name', $q->param('username') )
        ;    # using 'name' for checking user
    $app->param( 'pass', $q->param('password') )
        ;    # using 'pass' for matching password
    if ( lc( $cfg->AuthenticationModule ) eq 'mt' ) {
        my $error
            = $app->verify_password_strength( scalar $q->param('username'),
            scalar $q->param('pass') );
        $error ||= MT::Auth->sanity_check($app);
        if ($error) {
            $param->{error} = encode_html($error);
            return $app->forward( 'register', %$param );
        }
    }

    my $user;
    $user = $app->create_user_pending($param) if $filter_result;
    unless ($user) {
        $param->{error} = encode_html( $app->errstr );
        return $app->forward( 'register', %$param );
    }
    $user->save;

    ## Assign default role
    # $user->add_default_roles;

    MT::Util::start_background_task(
        sub {
            my $plugin = $app->plugin;

            my $subject = $plugin->translate('Welcome to the Calendar aggregator service');

            _send_email_confirmation(
                $app,
                'account_confirm_email',
                $user,
                $subject,
                {
                    reg_username => $user->name,
                    reg_displayname => $user->nickname,
                    reg_email => $user->email,
                    reg_website_url => $user->url,
                },
            );
        }
    );


    my $original = $user->clone();
    $app->run_callbacks( 'api_post_save.author', $app, $user, $original );

    $app->log(
        {   message => $app->plugin->translate(
                "New user \'[_2]\' (ID:[_1]) has been registred.",
                $user->id, $user->name
            ),
            level    => MT::Log::INFO(),
            class    => 'system',
            category => 'create_user',
        }
    );
    return $app->redirect( $app->app_uri(mode => 'request_payment', args => { newuser => 1 }));
}

sub resend_auth {
    my $app = shift;
    my $q   = $app->param;

    my $blog = $app->blog();

    my $return_to = $q->param('return_to');
    if ($return_to) {
        $return_to = remove_html($return_to);
        return $app->errtrans('Invalid request.')
            unless is_url($return_to);
    }
    else {
        $return_to = $app->config->ReturnToURL || q();
    }

    my $id   = $q->param('id');
    my $user = $app->model('author')->load($id)
        or return $app->errtrans("Invalid parameter");
    return $app->errtrans("Invalid parameter")
        if MT::Author::INACTIVE() != $user->status;

    require MT::Session;
    my $sess
        = MT::Session->load(
        { kind => 'CR', email => $user->email, name => $user->id } )
        or return $app->errtrans("Invalid parameter");

    my $cgi_path = $app->config('CGIPath');
    $cgi_path .= '/' unless $cgi_path =~ m!/$!;
    my $url
        = $cgi_path
        . $app->config->PluginDirectoryScript
        . $app->uri_params(
        'mode' => 'do_confirm',
        args   => {
            'token'   => $sess->id,
            'email'   => $user->email,
            'id'      => $user->id,
            'blog_id' => $blog->id,
        },
        );

    if ( ( $url =~ m!^/! ) && $blog ) {
        my ($blog_domain) = $blog->site_url =~ m|(.+://[^/]+)|;
        $url = $blog_domain . $url;
    }
    ## Send confirmation email in the background.
    MT::Util::start_background_task(
        sub {
            my $old_lang = $app->current_language;
            my $lang = $user->preferred_language();
            $lang = $lang eq 'ja' ? 'ja' : 'en_US';
            $app->set_language( $lang );
            my $plugin = $app->component('PluginDirectory');

            my $subject = $plugin->translate('Movable Type Account Confirmation');

            $app->set_language($old_lang);

            _send_email_confirmation(
                $app, 'account_verify_email', $user,
                $subject,
                { confirm_url => $url },
            );
        }
    );

    my $error
        = $app->plugin->translate(
        'Account confirm mail was re-sent. Please check again.'
        );
    return public_login( $app, error => $error );
}

sub do_confirm {
    my $app = shift;

    my $token   = $app->param('token');
    my $user_id = $app->param('id');
    my $sess    = $app->model('session')
        ->load( { id => $token, kind => 'CR', name => $user_id } );
    return $app->errtrans("Your session has been expired.") unless $sess;
    $sess->remove();

    if ( time - $sess->start > 7 * 24 * 60 * 60 ) {

        # one week
        return $app->errtrans("Your session has been expired.");
    }
    my $user = $app->model('author')->load($user_id);
    return $app->errtrans("Your session has been expired.") unless $user;
    my $blog_id = $sess->get('blog_id');
    my $blog    = $app->blog();
    return $app->errtrans("Your session has been expired.") unless $blog->id eq $blog_id;

    $user->save();

    my $user_sess = $app->make_commenter_session($user);

    return $app->redirect( $app->app_uri(mode => 'main') );
}

sub userinfo {
    my $app = shift;

    my $errmsg = 'Failed to get Commenter Information';
    require MT::Session;

    my $sess;
    if ( my $sid = $app->param('sid') ) {
        $sess
            = MT::Session::get_unexpired_value(
            MT->config->UserSessionTimeOut,
            { id => $sid, kind => 'SI' } );
    }
    elsif ( my $ot = $app->param('ott') ) {
        my $ott
            = MT::Session::get_unexpired_value( 5 * 60,
            { id => $ot, kind => 'OT' } )
            or return $app->json_error( $errmsg, 'jsonp' );
        $sess
            = MT::Session::get_unexpired_value(
            MT->config->UserSessionTimeOut,
            { id => $ott->get('sid'), kind => 'SI' } );
        $ott->remove();
    }
    return $app->json_error( $errmsg, 'jsonp' ) unless $sess;

    my $user_id   = $sess->thaw_data->{author_id};
    my $commenter = MT->model('author')->load($user_id)
        or return $app->json_error( $errmsg, 'jsonp' );
    my $status = $commenter->status();
    my $is_active = $status == MT::Author::ACTIVE() ? 1 : 0;

    my $out = {
        sid  => $sess->id,
        name => $commenter->nickname
            || $app->translate('(Display Name not set)'),
        url => $commenter->url
            || '',
        email => $commenter->email
            || '',
        userpic          => scalar $commenter->userpic_url,
        profile          => "",                             # profile link url
        is_authenticated => 1,
        is_author    => ( $commenter->type == MT::Author::AUTHOR() ? 1 : 0 ),
        is_trusted   => $is_active,
        is_anonymous => 0,
        can_post     => $is_active,
        can_comment  => $is_active,
        is_banned    => 0,
    };

    return $app->json_result( $out, 'jsonp' );
}

sub verify_session {
    my $app = shift;

    my $sid = $app->param('sid');
    my $sess
        = MT::Session::get_unexpired_value( MT->config->UserSessionTimeOut,
        $sid );
    my $commenter;
    if ($sess) {
        my $commenter_id = $sess->thaw_data->{author_id};
        $commenter = MT->model('author')->load($commenter_id);
    }
    my $out
        = $commenter
        ? { verified => 1 }
        : { error => 'Failed to get Commenter Information' };

    return $app->json_result( $out, 'jsonp' );
}

1;
