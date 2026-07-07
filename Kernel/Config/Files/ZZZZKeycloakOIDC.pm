# --
# Keycloak OpenID Connect settings (loaded from environment in Kubernetes).
# --

package Kernel::Config::Files::ZZZZKeycloakOIDC;

use strict;
use warnings;

sub Load {
    my ( $File, $Self ) = @_;

    my $Enabled = $ENV{OTRS_KEYCLOAK_ENABLED} // '';
    return 1 if !$Enabled || $Enabled eq '0' || $Enabled eq 'false';

    my $FQDN        = $ENV{OTRS_FQDN}         || 'localhost';
    my $HttpType    = $ENV{OTRS_HTTP_TYPE}    || 'http';
    my $ScriptAlias = $ENV{OTRS_SCRIPT_ALIAS} || 'otrs/';
    $ScriptAlias .= '/' if $ScriptAlias !~ m{/\z};

    my $BaseURL = "$HttpType://$FQDN/$ScriptAlias";

    my $Issuer = $ENV{OTRS_KEYCLOAK_ISSUER} || '';
    my $InternalIssuer = $ENV{OTRS_KEYCLOAK_INTERNAL_ISSUER} || '';
    if ( !$Issuer && $ENV{OTRS_KEYCLOAK_HOST} ) {
        my $KeycloakHost = $ENV{OTRS_KEYCLOAK_HOST};
        my $Realm        = $ENV{OTRS_KEYCLOAK_REALM} || 'otrs';
        $Issuer = "$KeycloakHost/realms/$Realm";
    }

    my $ClientID     = $ENV{OTRS_KEYCLOAK_CLIENT_ID}     || 'otrs-ce';
    my $ClientSecret = $ENV{OTRS_KEYCLOAK_CLIENT_SECRET} || 'otrs-keycloak-secret';
    my $UserAttr     = $ENV{OTRS_KEYCLOAK_USER_ATTRIBUTE} || 'preferred_username';

    $Self->{FQDN}      = $FQDN;
    $Self->{HttpType}  = $HttpType;
    $Self->{ScriptAlias} = $ScriptAlias;

    $Self->{'AuthModule::OIDC::Enabled'}             = 1;
    $Self->{'AuthModule::OIDC::Issuer'}              = $Issuer;
    $Self->{'AuthModule::OIDC::InternalIssuer'}       = $InternalIssuer || $Issuer;
    $Self->{'AuthModule::OIDC::ClientID'}            = $ClientID;
    $Self->{'AuthModule::OIDC::ClientSecret'}        = $ClientSecret;
    $Self->{'AuthModule::OIDC::RedirectURI'}         = "$HttpType://$FQDN/otrs-auth/login";
    $Self->{'AuthModule::OIDC::Scope'}               = 'openid profile email';
    $Self->{'AuthModule::OIDC::UserAttribute'}       = $UserAttr;
    $Self->{'AuthModule::OIDC::UserMappingRegExp'}   = $ENV{OTRS_KEYCLOAK_USER_REGEXP} || '';

    $Self->{LoginURL}  = $HttpType . '://' . $FQDN . '/otrs-auth/login';
    $Self->{LogoutURL} = $HttpType . '://' . $FQDN . '/otrs-auth/logout';

    return 1;
}

sub _URIEscape {
    my ($String) = @_;

    $String =~ s/([^A-Za-z0-9\-_.~])/sprintf('%%%02X', ord($1))/ge;

    return $String;
}

1;
