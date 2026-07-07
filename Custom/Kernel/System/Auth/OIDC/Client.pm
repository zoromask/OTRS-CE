# --
# Keycloak / OpenID Connect client for OTRS agent login.
# --

package Kernel::System::Auth::OIDC::Client;

use strict;
use warnings;

use JSON::XS;
use MIME::Base64 qw(decode_base64);
use LWP::UserAgent;

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::Encode',
    'Kernel::System::Log',
    'Kernel::System::WebUserAgent',
);

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    $Self->{Enabled}       = $ConfigObject->Get('AuthModule::OIDC::Enabled')       || 0;
    $Self->{Issuer}        = $ConfigObject->Get('AuthModule::OIDC::Issuer')        || '';
    $Self->{InternalIssuer} = $ConfigObject->Get('AuthModule::OIDC::InternalIssuer')
        || $Self->{Issuer};
    $Self->{ClientID}      = $ConfigObject->Get('AuthModule::OIDC::ClientID')      || '';
    $Self->{ClientSecret}  = $ConfigObject->Get('AuthModule::OIDC::ClientSecret')  || '';
    $Self->{RedirectURI}   = $ConfigObject->Get('AuthModule::OIDC::RedirectURI')   || '';
    $Self->{Scope}         = $ConfigObject->Get('AuthModule::OIDC::Scope')         || 'openid profile email';
    $Self->{UserAttribute} = $ConfigObject->Get('AuthModule::OIDC::UserAttribute') || 'preferred_username';
    $Self->{UserRegExp}    = $ConfigObject->Get('AuthModule::OIDC::UserMappingRegExp') || '';
    $Self->{LastError}     = '';

    return $Self;
}

sub IsEnabled {
    my ($Self) = @_;

    return 0 if !$Self->{Enabled};
    return 0 if !$Self->{Issuer};
    return 0 if !$Self->{ClientID};
    return 0 if !$Self->{RedirectURI};

    return 1;
}

sub CreateState {
    my ($Self) = @_;

    return $Self->_RandomString(32);
}

sub CreateNonce {
    my ($Self) = @_;

    return $Self->_RandomString(32);
}

sub GetAuthorizationURL {
    my ( $Self, %Param ) = @_;

    my $State = $Param{State} || '';
    my $Nonce = $Param{Nonce} || '';

    my $URL = $Self->{Issuer} . '/protocol/openid-connect/auth';
    $URL .= '?client_id=' . $Self->_URIEscape( $Self->{ClientID} );
    $URL .= '&redirect_uri=' . $Self->_URIEscape( $Self->{RedirectURI} );
    $URL .= '&response_type=code';
    $URL .= '&scope=' . $Self->_URIEscape( $Self->{Scope} );
    $URL .= '&state=' . $Self->_URIEscape($State);
    $URL .= '&nonce=' . $Self->_URIEscape($Nonce);

    return $URL;
}

sub GetLogoutURL {
    my ( $Self, %Param ) = @_;

    my @QueryParams;

    if ( $Param{IDToken} ) {
        push @QueryParams, 'id_token_hint=' . $Self->_URIEscape( $Param{IDToken} );
    }

    if ( $Param{PostLogoutRedirectURI} ) {
        push @QueryParams, 'post_logout_redirect_uri=' . $Self->_URIEscape( $Param{PostLogoutRedirectURI} );
    }

    if ( $Self->{ClientID} ) {
        push @QueryParams, 'client_id=' . $Self->_URIEscape( $Self->{ClientID} );
    }

    my $URL = $Self->{Issuer} . '/protocol/openid-connect/logout';
    if (@QueryParams) {
        $URL .= '?' . join( '&', @QueryParams );
    }

    return $URL;
}

sub ExchangeCode {
    my ( $Self, %Param ) = @_;

    $Self->{LastError} = '';

    my $Code = $Param{Code} || '';
    if ( !$Code ) {
        $Self->{LastError} = 'Missing authorization code.';
        return;
    }

    my %TokenResponse = $Self->_TokenRequest(
        GrantType => 'authorization_code',
        Code      => $Code,
    );

    if ( !%TokenResponse ) {
        $Self->{LastError} ||= 'Keycloak token exchange failed.';
        return;
    }
    if ( !$TokenResponse{access_token} ) {
        $Self->{LastError} = 'Keycloak did not return an access token.';
        return;
    }

    my %IDTokenClaims = $Self->_DecodeIDTokenPayload(
        IDToken => $TokenResponse{id_token} || '',
    );

    my %UserInfo = $Self->_GetUserInfo(
        AccessToken => $TokenResponse{access_token},
    );

    if ( $TokenResponse{id_token} ) {
        my $Valid = $Self->_ValidateIDToken(
            IDToken => $TokenResponse{id_token},
            Nonce   => $Param{Nonce} || '',
        );
        if ( !$Valid ) {
            $Self->{LastError} ||= 'Invalid ID token.';
            if ( !%UserInfo && !%IDTokenClaims ) {
                return;
            }
        }
    }

    my $Login = $UserInfo{ $Self->{UserAttribute} }
        || $UserInfo{preferred_username}
        || $UserInfo{email}
        || $IDTokenClaims{ $Self->{UserAttribute} }
        || $IDTokenClaims{preferred_username}
        || $IDTokenClaims{email}
        || '';

    if ( $Self->{UserRegExp} && $Login ) {
        $Login =~ s/$Self->{UserRegExp}/$1/;
    }

    if ( !$Login ) {
        $Self->{LastError} ||= 'No username claim found in the Keycloak token.';
        return;
    }

    return {
        Login       => $Login,
        UserInfo    => \%UserInfo,
        AccessToken => $TokenResponse{access_token},
        IDToken     => $TokenResponse{id_token} || '',
    };
}

sub _TokenRequest {
    my ( $Self, %Param ) = @_;

    my $URL = $Self->{InternalIssuer} . '/protocol/openid-connect/token';

    my %Data = (
        client_id     => $Self->{ClientID},
        client_secret => $Self->{ClientSecret},
        grant_type    => $Param{GrantType},
    );

    if ( $Param{GrantType} eq 'authorization_code' ) {
        $Data{code}         = $Param{Code};
        $Data{redirect_uri} = $Self->{RedirectURI};
    }

    my %Response = $Self->_HTTPPost(
        URL  => $URL,
        Data => \%Data,
    );

    return if !%Response;
    return if $Response{Status} !~ /^200/;

    my $JSON = eval { decode_json( ${ $Response{Content} } ) };
    if ( !$JSON || ref $JSON ne 'HASH' ) {
        $Self->{LastError} = 'Invalid token response from Keycloak.';
        return;
    }

    return %{$JSON};
}

sub _HTTPPost {
    my ( $Self, %Param ) = @_;

    my $FormData = $Param{Data} || {};
    $FormData = {} if ref $FormData ne 'HASH';

    my $UserAgent = LWP::UserAgent->new( timeout => 30 );
    # LWP requires a hash reference here; unpacking with %{...} drops grant_type.
    my $Response  = $UserAgent->post( $Param{URL}, $FormData );

    if ( !$Response->is_success() ) {
        my $Body = $Response->decoded_content() || '';
        if ( $Body =~ /"error_description"\s*:\s*"([^"]+)"/ ) {
            $Self->{LastError} = $1;
        }
        elsif ( $Body =~ /"error"\s*:\s*"([^"]+)"/ ) {
            $Self->{LastError} = $1;
        }
        else {
            $Self->{LastError} = $Response->status_line();
        }
        return;
    }

    my $Content = $Response->decoded_content();
    $Kernel::OM->Get('Kernel::System::Encode')->EncodeInput( \$Content );

    return (
        Status  => $Response->status_line(),
        Content => \$Content,
    );
}

sub _GetUserInfo {
    my ( $Self, %Param ) = @_;

    my $URL = $Self->{InternalIssuer} . '/protocol/openid-connect/userinfo';

    my %Response = $Kernel::OM->Get('Kernel::System::WebUserAgent')->Request(
        URL     => $URL,
        Type    => 'GET',
        Header  => {
            Authorization => 'Bearer ' . $Param{AccessToken},
        },
    );

    return if !$Response{Content};
    if ( $Response{Status} !~ /^200/ ) {
        $Self->{LastError} ||= 'Keycloak userinfo request failed.';
        return;
    }

    my $JSON = eval { decode_json( ${ $Response{Content} } ) };
    return if !$JSON || ref $JSON ne 'HASH';

    return %{$JSON};
}

sub _DecodeIDTokenPayload {
    my ( $Self, %Param ) = @_;

    my $IDToken = $Param{IDToken} || '';
    my @Parts   = split /[.]/, $IDToken;
    return if scalar @Parts != 3;

    my $PayloadPart = $Parts[1];
    while ( length($PayloadPart) % 4 ) {
        $PayloadPart .= '=';
    }
    $PayloadPart =~ tr/-_/\+\//;

    my $PayloadJSON = eval { decode_json( decode_base64($PayloadPart) ) };
    return if !$PayloadJSON || ref $PayloadJSON ne 'HASH';

    return %{$PayloadJSON};
}

sub _ValidateIDToken {
    my ( $Self, %Param ) = @_;

    my %PayloadJSON = $Self->_DecodeIDTokenPayload(
        IDToken => $Param{IDToken} || '',
    );
    return if !%PayloadJSON;

    my $Now = time();

    if ( $PayloadJSON{iss} && $PayloadJSON{iss} ne $Self->{Issuer} ) {
        $Self->{LastError} = 'ID token issuer mismatch.';
        return;
    }

    if ( $PayloadJSON{aud} ) {
        my $AudienceOK = ref $PayloadJSON{aud} eq 'ARRAY'
            ? scalar grep { $_ eq $Self->{ClientID} } @{ $PayloadJSON{aud} }
            : $PayloadJSON{aud} eq $Self->{ClientID};
        if ( !$AudienceOK ) {
            $Self->{LastError} = 'ID token audience mismatch.';
            return;
        }
    }

    if ( $PayloadJSON{exp} && $PayloadJSON{exp} < $Now ) {
        $Self->{LastError} = 'ID token has expired.';
        return;
    }

    if (   $Param{Nonce}
        && $PayloadJSON{nonce}
        && $PayloadJSON{nonce} ne $Param{Nonce} )
    {
        $Self->{LastError} = 'ID token nonce mismatch.';
        return;
    }

    return 1;
}

sub _RandomString {
    my ( $Self, $Length ) = @_;

    my @Chars = ( 'a' .. 'z', 'A' .. 'Z', 0 .. 9 );
    my $String = '';
    for ( 1 .. $Length ) {
        $String .= $Chars[ int( rand(@Chars) ) ];
    }

    return $String;
}

sub _URIEscape {
    my ( $Self, $String ) = @_;

    $String =~ s/([^A-Za-z0-9\-_.~])/sprintf('%%%02X', ord($1))/ge;

    return $String;
}

1;
