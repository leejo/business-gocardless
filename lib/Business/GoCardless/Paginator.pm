package Business::GoCardless::Paginator;

use Moo;
extends 'Business::GoCardless::Resource';
use JSON ();

use Business::GoCardless::Bill;
use Business::GoCardless::PreAuthorization;
use Business::GoCardless::Payout;
use Business::GoCardless::User;
use Business::GoCardless::Paginator;

has [ qw/
    client
    objects
    class
/ ] => (
    is => 'rw'
);

has info => (
    is       => 'rw',
    required => 1,
    coerce   => sub {
        my ( $info ) = @_;

        return {} if ! $info;

        if ( $info =~ /^[{\[]/ ) {
            # defensive decoding
            eval { $info = JSON->new->decode( $info ) };
            $@ && do { return "Failed to parse JSON response ($info): $@"; };
        }
        return $info;
    }
);

has links => (
    is       => 'rw',
    required => 1,
    coerce   => sub {
        my ( $links ) = @_;

        my $links_hash = {};
        return $links_hash if ! $links;

        foreach my $link ( split( /, /,$links ) ) {
            my ( $rel,$url ) = reverse split( />; /,$link );
            $url =~ s/^<//;
            $rel =~ s/^.*?"([A-z]+)"/$1/;
            $links_hash->{$rel} = $url;
        }

        return $links_hash;
    },
);

sub next {
    my ( $self ) = @_;

    if ( my @objects = @{ $self->objects // [] } ) {
        # get the next chunk and return the current chunk
        $self->objects( $self->_objects_from_page( 'next' ) );
        return @objects;
    }

    return;
}

sub previous {
    my ( $self ) = @_;
    return @{ $self->_objects_from_page( 'previous' ) };
}

sub first {
    my ( $self ) = @_;
    return @{ $self->_objects_from_page( 'first' ) };
}

sub last {
    my ( $self ) = @_;
    return @{ $self->_objects_from_page( 'last' ) };
}

sub _objects_from_page {

    my ( $self,$page ) = @_;

    # see if we have more data to get
    if ( my $url = $self->links->{$page} ) {

        my ( $data,$links,$info ) = $self->client->api_get( $url );

        my $class = $self->class;
        my @objects = map { $class->new( client => $self->client,%{ $_ } ) }
            @{ $data };

        $self->links( $links );
        $self->info( $info );
        return [ @objects ];
    }

    return [];
}

1;