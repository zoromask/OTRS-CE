#!/usr/bin/env perl
# --
# OpenID Connect logout handler for Keycloak integration.
# --

use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/../..";
use lib "$Bin/../../Kernel/cpan-lib";
use lib "$Bin/../../Custom";

use Kernel::System::ObjectManager;

local $Kernel::OM = Kernel::System::ObjectManager->new();

my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
my $ParamObject  = $Kernel::OM->Get('Kernel::System::Web::Request');
my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
my $MainObject   = $Kernel::OM->Get('Kernel::System::Main');

$MainObject->Require('Kernel::System::Auth::OIDC::Client') || exit 1;

my $OIDCClient = Kernel::System::Auth::OIDC::Client->new();

if ( !$OIDCClient->IsEnabled() ) {
    print $LayoutObject->Redirect( OP => 'index.pl' );
    exit 0;
}

my $HttpType    = $ConfigObject->Get('HttpType')    || 'http';
my $FQDN        = $ConfigObject->Get('FQDN')        || 'localhost';
my $ScriptAlias = $ConfigObject->Get('ScriptAlias') || 'otrs/';
$ScriptAlias .= '/' if $ScriptAlias !~ m{/\z};

my $PostLogoutRedirectURI = "$HttpType://$FQDN/$ScriptAlias" . 'index.pl';
my $IDToken               = $ParamObject->GetCookie( Key => 'OTRSOIDCIDToken' ) || '';

my $LogoutURL = $OIDCClient->GetLogoutURL(
    IDToken               => $IDToken,
    PostLogoutRedirectURI => $PostLogoutRedirectURI,
);

$LayoutObject->{SetCookies} = {
    OTRSOIDCIDToken => $ParamObject->SetCookie(
        Key      => 'OTRSOIDCIDToken',
        Value    => '',
        Expires  => '-1y',
        Path     => '',
        HTTPOnly => 1,
    ),
    OTRSOIDCState => $ParamObject->SetCookie(
        Key      => 'OTRSOIDCState',
        Value    => '',
        Expires  => '-1y',
        Path     => '',
        HTTPOnly => 1,
    ),
    OTRSOIDCNonce => $ParamObject->SetCookie(
        Key      => 'OTRSOIDCNonce',
        Value    => '',
        Expires  => '-1y',
        Path     => '',
        HTTPOnly => 1,
    ),
};

print $LayoutObject->Redirect( ExtURL => $LogoutURL );
exit 0;
