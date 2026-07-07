# --
# Keycloak / OpenID Connect client for OTRS agent login.
# --

package Kernel::System::Auth::OIDC::Client;

use strict;
use warnings;

use JSON::XS;
use MIME::Base64 qw(decode_base64);

our @ObjectDependencies = (
    'Kernel::Config',
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

    my $Code = $Param{Code} || '';
    return if !$Code;

    my %TokenResponse = $Self->_TokenRequest(
        GrantType => 'authorization_code',
        Code      => $Code,
    );

    return if !%TokenResponse;
    return if !$TokenResponse{access_token};

    my %UserInfo = $Self->_GetUserInfo(
        AccessToken => $TokenResponse{access_token},
    );

    return if !%UserInfo;

    if ( $TokenResponse{id_token} ) {
        my $Valid = $Self->_ValidateIDToken(
            IDToken => $TokenResponse{id_token},
            Nonce   => $Param{Nonce} || '',
        );
        return if !$Valid;
    }

    my $Login = $UserInfo{ $Self->{UserAttribute} }
        || $UserInfo{preferred_username}
        || $UserInfo{email}
        || '';

    if ( $Self->{UserRegExp} && $Login ) {
        $Login =~ s/$Self->{UserRegExp}/$1/;
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

    my %Response = $Kernel::OM->Get('Kernel::System::WebUserAgent')->Request(
        URL  => $URL,
        Type => 'POST',
        Data => \%Data,
    );

    return if !$Response{Content};
    return if $Response{Status} !~ /^200/;

    my $JSON = eval { decode_json( ${ $Response{Content} } ) };
    return if !$JSON || ref $JSON ne 'HASH';

    return %{$JSON};
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
    return if $Response{Status} !~ /^200/;

    my $JSON = eval { decode_json( ${ $Response{Content} } ) };
    return if !$JSON || ref $JSON ne 'HASH';

    return %{$JSON};
}

sub _ValidateIDToken {
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

    my $Now = time();

    return if $PayloadJSON->{iss} && $PayloadJSON->{iss} ne $Self->{Issuer};
    return if $PayloadJSON->{aud} && $PayloadJSON->{aud} ne $Self->{ClientID};
    return if $PayloadJSON->{exp} && $PayloadJSON->{exp} < $Now;
    return if $Param{Nonce} && $PayloadJSON->{nonce} && $PayloadJSON->{nonce} ne $Param{Nonce};

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
