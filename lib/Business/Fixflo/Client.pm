package Business::Fixflo::Client;

=head1 NAME

Business::Fixflo::Client

=head1 DESCRIPTION

This is a class for the lower level requests to the fixflo API. generally
there is nothing you should be doing with this.

=cut

use Moo;
with 'Business::Fixflo::Utils';
with 'Business::Fixflo::Version';

use Business::Fixflo::Exception;
use Business::Fixflo::Paginator;
use Business::Fixflo::Issue;
use Business::Fixflo::Agency;
use Business::Fixflo::Property;
use Business::Fixflo::PropertyAddress;
use Business::Fixflo::QuickViewPanel;

use MIME::Base64 qw/ encode_base64 /;
use LWP::UserAgent;
use JSON ();
use Carp qw/ carp confess /;

=head1 ATTRIBUTES

=head2 username

Your Fixflo username (required if api_key not supplied)

=head2 password

Your Fixflo password (required if api_key not supplied)

=head2 api_key

Your Fixflo API Key (required if username and password not supplied)

=head2 custom_domain

Your Fixflo custom domain

=head2 user_agent

The user agent string used in requests to the Fixflo API, defaults to
business-fixflo/perl/v . $version_of_this_library.

=head2 url_suffix

The url suffix to use after the custom domain, defaults to fixflo.com

=head2 base_url

The full url to use in calling the Fixflo API, defaults to:

    value of $ENV{FIXFLO_URL}
    or https:// $self->custom_domain . $self->url_suffix

=head2 api_path

The version of the Fixflo API to use, defaults to:

    /api/$Business::Fixflo::API_VERSION

=cut

has [ qw/ custom_domain / ] => (
    is       => 'ro',
    required => 1,
);

has [ qw/ username password api_key / ] => (
    is       => 'ro',
    required => 0,
);

has user_agent => (
    is      => 'ro',
    default => sub {
        # probably want more info in here, version of perl, platform, and such
        return "business-fixflo/perl/v" . $Business::Fixflo::VERSION;
    }
);

has url_suffix => (
    is       => 'ro',
    required => 0,
    default  => sub { 'fixflo.com' },
);

has url_scheme => (
    is       => 'ro',
    required => 0,
    default  => sub { 'https' },
);

has 'base_url' => (
    is       => 'ro',
    required => 0,
    lazy     => 1,
    default  => sub {
        my ( $self ) = @_;
        return $ENV{FIXFLO_URL}
            ? $ENV{FIXFLO_URL}
            : $self->url_scheme . '://' . $self->custom_domain . '.' . $self->url_suffix;
    }
);

has api_path => (
    is       => 'ro',
    required => 0,
    default  => sub { '/api/' . $Business::Fixflo::API_VERSION },
);

sub BUILD {
    my ( $self ) = @_;

    if (
        ! $self->api_key
        && !( $self->username && $self->password )
    ) {
        confess( "api_key or username + password required" );
    }
}


sub _get_issues {
    my ( $self,$params ) = @_;
    my $issues = $self->_api_request( 'GET','Issues' );

    my $Paginator = Business::Fixflo::Paginator->new(
        links  => {
            next     => $issues->{NextURL},
            previous => $issues->{PreviousURL},
        },
        client  => $self,
        class   => 'Business::Fixflo::Issue',
        objects => [ map { Business::Fixflo::Issue->new(
            client => $self,
            url    => $_,
        ) } @{ $issues->{Items} } ],
    );

    return $Paginator;
}

sub _get_agencies {
    my ( $self,$params ) = @_;
    my $agencies = $self->_api_request( 'GET','Agencies' );

    my $Paginator = Business::Fixflo::Paginator->new(
        links  => {
            next     => $agencies->{NextURL},
            previous => $agencies->{PreviousURL},
        },
        client  => $self,
        class   => 'Business::Fixflo::Agency',
        objects => [ map { Business::Fixflo::Agency->new(
            client => $self,
            url    => $_,
        ) } @{ $agencies->{Items} } ],
    );

    return $Paginator;
}

sub _get_properties {
    my ( $self,$params ) = @_;
    my $properties = $self->_api_request( 'GET','Property/Search',$params );

    my $Paginator = Business::Fixflo::Paginator->new(
        links  => {
            next     => $properties->{NextURL},
            previous => $properties->{PreviousURL},
        },
        client  => $self,
        class   => 'Business::Fixflo::Property',
        objects => [ map { Business::Fixflo::Property->new(
            client  => $self,
            Address => delete( $_->{Address} ),
            %{ $_ },
        ) } @{ $properties->{Items} } ],
    );

    return $Paginator;
}

sub _get_property_addresses {
    my ( $self,$params ) = @_;
    my $property_addresses = $self->_api_request(
        'GET','PropertyAddress/Search',$params
    );

    my $Paginator = Business::Fixflo::Paginator->new(
        links  => {
            next     => $property_addresses->{NextURL},
            previous => $property_addresses->{PreviousURL},
        },
        client  => $self,
        class   => 'Business::Fixflo::PropertyAddress',
        objects => [ map { Business::Fixflo::PropertyAddress->new(
            client  => $self,
            %{ $_ },
        ) } @{ $property_addresses->{Items} } ],
    );

    return $Paginator;
}

sub _get_issue {
    my ( $self,$id ) = @_;

    my $data = $self->_api_request( 'GET',"Issue/$id" );

    my $issue = Business::Fixflo::Issue->new(
        client => $self,
        %{ $data },
    );

    return $issue;
}

sub _get_agency {
    my ( $self,$id ) = @_;

    my $data = $self->_api_request( 'GET',"Agency/$id" );

    my $issue = Business::Fixflo::Agency->new(
        client => $self,
        %{ $data },
    );

    return $issue;
}

sub _get_property {
    my ( $self,$id,$is_external_id ) = @_;

    my $query = $is_external_id
        ? "ExternalPropertyRef=$id"
        : "PropertyId=$id";

    my $data = $self->_api_request( 'GET',"Property?$query" );

    my $property = Business::Fixflo::Property->new(
        client => $self,
        %{ $data },
    );

    return $property;
}

sub _get_property_address {
    my ( $self,$id ) = @_;

    my $data = $self->_api_request( 'GET',"PropertyAddress/$id" );

    my $property_address = Business::Fixflo::PropertyAddress->new(
        client => $self,
        %{ $data },
    );

    return $property_address;
}

sub _get_quick_view_panels {
    my ( $self,$id ) = @_;

    my $data = $self->_api_request( 'GET',"qvp" );
    my @qvps;

    foreach my $qvp ( @{ $data // [] } ) {
        push( @qvps,Business::Fixflo::QuickViewPanel->new(
            client => $self,
            %{ $qvp }
        ) );
    }

    return @qvps;
}

=head1 METHODS

    api_get
    api_post
    api_delete

Make a request to the Fixflo API:

    my $data = $Client->api_get( 'Issues',\%params );

May return a L<Business::Fixflo::Paginator> object (when calling endpoints
that return lists of items) or a Business::Fixflo:: object for the Issue,
Agency, etc.

=cut

sub api_get {
    my ( $self,$path,$params ) = @_;
    return $self->_api_request( 'GET',$path,$params );
}

sub api_post {
    my ( $self,$path,$params ) = @_;
    return $self->_api_request( 'POST',$path,$params );
}

sub api_delete {
    my ( $self,$path,$params ) = @_;
    return $self->_api_request( 'DELETE',$path,$params );
}

sub _api_request {
    my ( $self,$method,$path,$params ) = @_;

    carp( "$method -> $path" )
        if $ENV{FIXFLO_DEBUG};

    my $ua = LWP::UserAgent->new;
    $ua->agent( $self->user_agent );

    $path = $self->_add_query_params( $path,$params )
        if $method eq 'GET';

    my $req = $self->_build_request( $method,$path );

    if ( $method =~ /POST|PUT|DELETE/ ) {
        if ( $params ) {
            $req->content_type( 'application/json' );
            $req->content( JSON->new->encode( $params ) );

            carp( $req->content )
                if $ENV{FIXFLO_DEBUG};
        }
    }

    my $res = $ua->request( $req );

    if ( $res->is_success ) {
        my $data = $res->content;

        if ( $res->headers->header( 'content-type' ) =~ m!application/json! ) {
            $data = JSON->new->decode( $data );
        }

        return $data;
    }
    else {

        carp( "RES: @{[ $res->code ]}" )
            if $ENV{FIXFLO_DEBUG};

        Business::Fixflo::Exception->throw({
            message  => $res->content,
            code     => $res->code,
            response => $res->status_line,
        });
    }
}

sub _build_request {
    my ( $self,$method,$path ) = @_;

    my $req = HTTP::Request->new(
        # passing through the absolute URL means we don't build it
        $method => $path =~ /^http/
            ? $path : join( '/',$self->base_url . $self->api_path,$path ),
    );

    carp(
        $method => $path =~ /^http/
            ? $path : join( '/',$self->base_url . $self->api_path,$path ),
    ) if $ENV{FIXFLO_DEBUG};

    $self->_set_request_headers( $req );

    return $req;
}

sub _set_request_headers {
    my ( $self,$req ) = @_;

    my $auth_string = $self->api_key
        ? $self->api_key
        : "basic " . encode_base64( join( ":",$self->username,$self->password ) );

    $req->header( 'Authorization' => $auth_string );

    carp( "Authorization: $auth_string" )
        if $ENV{FIXFLO_DEBUG};

    $req->header( 'Accept' => 'application/json' );
}

sub _add_query_params {
    my ( $self,$path,$params ) = @_;

    if ( my $query_params = $self->normalize_params( $params ) ) {
        return "$path?$query_params";
    }

    return $path;
}

=head1 AUTHOR

Lee Johnson - C<leejo@cpan.org>

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself. If you would like to contribute documentation,
features, bug fixes, or anything else then please raise an issue / pull request:

    https://github.com/leejo/business-fixflo

=cut

1;

# vim: ts=4:sw=4:et
