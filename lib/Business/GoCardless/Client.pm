package Business::GoCardless::Client;

use Moo;
with 'Business::GoCardless::Utils';
with 'Business::GoCardless::Version';

use Business::GoCardless::Exception;
use Business::GoCardless::Bill;
use Business::GoCardless::Merchant;
use Business::GoCardless::Payout;
use Business::GoCardless::Subscription;

use Carp qw/ confess /;
use POSIX qw/ strftime /;
use MIME::Base64 qw/ encode_base64 /;
use LWP::UserAgent;
use JSON ();

has token => (
    is       => 'ro',
    required => 1,
);

has base_url => (
    is       => 'ro',
    required => 0,
    default  => sub { 'https://gocardless.com' },
);

has api_path => (
    is       => 'ro',
    required => 0,
    default  => sub { '/api/' . $Business::GoCardless::API_VERSION },
);

has app_id => (
    is       => 'ro',
    default  => sub {
        $ENV{'GOCARDLESS_APP_ID'}
            or confess( "Missing required argument: app_id" );
    }
);

has app_secret => (
    is       => 'ro',
    default  => sub {
        $ENV{'GOCARDLESS_APP_SECRET'}
            or confess( "Missing required argument: app_secret" );
    }
);

has merchant_id => (
    is       => 'ro',
    default  => sub {
        $ENV{'GOCARDLESS_MERCHANT_ID'}
            or confess( "Missing required argument: merchant_id" );
    }
);

sub new_bill_url {
    my ( $self,$params ) = @_;
    return $self->new_limit_url( 'bill',$params );
}

sub new_pre_authorization_url {
    my ( $self,$params ) = @_;
    return $self->new_limit_url( 'pre_authorization',$params );
}

sub new_subscription_url {
    my ( $self,$params ) = @_;
    return $self->new_limit_url( 'subscription',$params );
}

sub new_limit_url {
    my ( $self,$type,$limit_params ) = @_;

    $limit_params->{merchant_id} = $self->merchant_id;

    my $params = {
        nonce     => $self->generate_nonce,
        timestamp => strftime( "%Y-%m-%dT%H:%M:%SZ",gmtime ),
        client_id => $self->app_id,
        ( map { ( $limit_params->{$_}
            ? ( $_ => delete( $limit_params->{$_} ) ) : ()
        ) } qw/ redirect_uri cancel_uri cancel_uri state / ),
        $type     => $limit_params,
    };

    $params->{signature} = $self->sign_params( $params,$self->app_secret );

    return sprintf(
        "%s/connect/%ss/new?%s",
        $self->base_url,
        $type,
        $self->normalize_params( $params )
    );
}

sub confirm_resource {
    my ( $self,$params ) = @_;

    if ( ! $self->signature_valid( $params,$self->app_secret ) ) {
        Business::GoCardless::Exception->throw({
            message => "Invalid signature for confirm_resource"
        });
    }

    my $data = {
        resource_id   => $params->{resource_id},
        resource_type => $params->{resource_type},
    };

    my $credentials = encode_base64( $self->app_id . ':' . $self->app_secret );
    $credentials    =~ s/\s//g;

    my $ua = LWP::UserAgent->new;
    $ua->agent( $self->_user_agent );

    my $req = HTTP::Request->new(
        POST => join( '/',$self->base_url . $self->api_path,'confirm' )
    );

    $req->header( 'Authorization' => "Basic $credentials" );
    $req->header( 'Accept' => 'application/json' );

    $req->content_type( 'application/x-www-form-urlencoded' );
    $req->content( $self->normalize_params( $data ) );

    my $res = $ua->request( $req );

    if ( $res->is_success ) {
        
        my $class_suffix = ucfirst( $params->{resource_type} );
        $class_suffix    =~ s/_([A-z])/uc($1)/ge;
        my $class = "Business::GoCardless::$class_suffix";
        my $obj   = $class->new(
            client => $self,
            id     => $params->{resource_id}
        );
        return $obj->find_with_client;
    }
    else {
        Business::GoCardless::Exception->throw({
            message  => $res->content,
            code     => $res->code,
            response => $res->status_line,
        });
    }
}

sub _user_agent {
    my ( $self ) = @_;

    # probably want more infoin here, version of perl, platform, and such
    return "business-gocardless/perl/v" . $Business::GoCardless::VERSION;
}

sub api_get {
    my ( $self,$path,$params ) = @_;
    return $self->api_request( 'GET',$path,$params );
}

sub api_post {
    my ( $self,$path,$params ) = @_;
    return $self->api_request( 'POST',$path,$params );
}

sub api_put {
    my ( $self,$path,$params ) = @_;
    return $self->api_request( 'PUT',$path,$params );
}

sub api_delete {
    my ( $self,$path,$params ) = @_;
    return $self->api_request( 'DELETE',$path,$params );
}

sub api_request {
    my ( $self,$method,$path,$params ) = @_;

    my $ua = LWP::UserAgent->new;
    $ua->agent( $self->_user_agent );

    my $req = HTTP::Request->new(
        # passing through the absolute URL means we don't build it
        $method => $path =~ /^http/
            ? $path : join( '/',$self->base_url . $self->api_path . $path ),
    );

    $req->header( 'Authorization' => "bearer " . $self->token );
    $req->header( 'Accept' => 'application/json' );

    if ( $method =~ /POST|PUT/ ) {
      $req->content_type( 'application/x-www-form-urlencoded' );
      $req->content( $self->normalize_params( $params ) );
    }

    my $res = $ua->request( $req );

    if ( $res->is_success ) {
        my $data  = JSON->new->decode( $res->content );
        my $links = $res->header( 'link' );
        my $info  = $res->header( 'x-pagination' );
        return wantarray ? ( $data,$links,$info ) : $data;
    }
    else {
        Business::GoCardless::Exception->throw({
            message  => $res->content,
            code     => $res->code,
            response => $res->status_line,
        });
    }
}

1;

# vim: ts=4:sw=4:et
