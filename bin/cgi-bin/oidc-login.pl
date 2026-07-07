#!/usr/bin/env perl
# --
# OpenID Connect login entry point for Keycloak integration.
# --

use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/../..";
use lib "$Bin/../../Kernel/cpan-lib";
use lib "$Bin/../../Custom";

use Kernel::System::ObjectManager;

local $Kernel::OM = Kernel::System::ObjectManager->new();

my $ConfigObject  = $Kernel::OM->Get('Kernel::Config');
my $ParamObject   = $Kernel::OM->Get('Kernel::System::Web::Request');
my $LayoutObject  = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
my $LogObject     = $Kernel::OM->Get('Kernel::System::Log');
my $SessionObject = $Kernel::OM->Get('Kernel::System::AuthSession');
my $UserObject    = $Kernel::OM->Get('Kernel::System::User');
my $MainObject    = $Kernel::OM->Get('Kernel::System::Main');

$MainObject->Require('Kernel::System::Auth::OIDC::Client') || exit 1;

my $OIDCClient = Kernel::System::Auth::OIDC::Client->new();

if ( !$OIDCClient->IsEnabled() ) {
    _Error('Keycloak login is not enabled.');
}

my $RequestedURL = $ParamObject->GetParam( Param => 'RequestedURL' )
    || $ParamObject->GetCookie( Key => 'OTRSOIDCRequestedURL' )
    || 'Action=AgentDashboard';

my $Code  = $ParamObject->GetParam( Param => 'code' )  || '';
my $State = $ParamObject->GetParam( Param => 'state' ) || '';
my $Error = $ParamObject->GetParam( Param => 'error' ) || '';

if ($Error) {
    my $Description = $ParamObject->GetParam( Param => 'error_description' ) || $Error;
    _Error("Keycloak authentication failed: $Description");
}

if ( !$Code ) {
    my $OIDCState = $OIDCClient->CreateState();
    my $OIDCNonce = $OIDCClient->CreateNonce();

    my $Expires = '+10m';
    my $Path    = '';

    $LayoutObject->{SetCookies} = {
        OTRSOIDCState => $ParamObject->SetCookie(
            Key      => 'OTRSOIDCState',
            Value    => $OIDCState,
            Expires  => $Expires,
            Path     => $Path,
            HTTPOnly => 1,
        ),
        OTRSOIDCNonce => $ParamObject->SetCookie(
            Key      => 'OTRSOIDCNonce',
            Value    => $OIDCNonce,
            Expires  => $Expires,
            Path     => $Path,
            HTTPOnly => 1,
        ),
        OTRSOIDCRequestedURL => $ParamObject->SetCookie(
            Key      => 'OTRSOIDCRequestedURL',
            Value    => $RequestedURL,
            Expires  => $Expires,
            Path     => $Path,
            HTTPOnly => 1,
        ),
    };

    my $AuthURL = $OIDCClient->GetAuthorizationURL(
        State => $OIDCState,
        Nonce => $OIDCNonce,
    );

    print $LayoutObject->Redirect( ExtURL => $AuthURL );
    exit 0;
}

my $StoredState = $ParamObject->GetCookie( Key => 'OTRSOIDCState' ) || '';
if ( !$StoredState || $StoredState ne $State ) {
    _Error('Invalid OIDC state. Please try logging in again.');
}

my $Nonce = $ParamObject->GetCookie( Key => 'OTRSOIDCNonce' ) || '';

my $AuthResult = $OIDCClient->ExchangeCode(
    Code  => $Code,
    Nonce => $Nonce,
);

if ( !$AuthResult || !$AuthResult->{Login} ) {
    _Error('Could not resolve an OTRS user from the Keycloak account.');
}

my $Login = $AuthResult->{Login};

my %UserData = $UserObject->GetUserData(
    User          => $Login,
    Valid         => 1,
    NoOutOfOffice => 1,
);

if ( !$UserData{UserID} || !$UserData{UserLogin} ) {
    _Error("Keycloak user '$Login' is not provisioned in OTRS. Ask an administrator to create the agent account.");
}

my $DateTimeObj = $Kernel::OM->Create('Kernel::System::DateTime');

my $NewSessionID = $SessionObject->CreateSessionID(
    %UserData,
    UserLastRequest => $DateTimeObj->ToEpoch(),
    UserType        => 'User',
    SessionSource   => 'AgentInterface',
);

if ( !$NewSessionID ) {
    my $Detail = $SessionObject->SessionIDErrorMessage()
        || 'Could not create an OTRS session.';
    _Error($Detail);
}

my $SessionName = $ConfigObject->Get('SessionName') || 'OTRSAgentInterface';
my $Expires     = '+' . $ConfigObject->Get('SessionMaxTime') . 's';
if ( !$ConfigObject->Get('SessionUseCookieAfterBrowserClose') ) {
    $Expires = '';
}

$LayoutObject->{SetCookies} = {
    SessionIDCookie => $ParamObject->SetCookie(
        Key      => $SessionName,
        Value    => $NewSessionID,
        Expires  => $Expires,
        Path     => $ConfigObject->Get('ScriptAlias'),
        HTTPOnly => 1,
    ),
    OTRSBrowserHasCookie => $ParamObject->SetCookie(
        Key      => 'OTRSBrowserHasCookie',
        Value    => 1,
        Expires  => $Expires,
        Path     => $ConfigObject->Get('ScriptAlias'),
        HTTPOnly => 1,
    ),
};

if ( $AuthResult->{IDToken} ) {
    $LayoutObject->{SetCookies}->{OTRSOIDCIDToken} = $ParamObject->SetCookie(
        Key      => 'OTRSOIDCIDToken',
        Value    => $AuthResult->{IDToken},
        Expires  => $Expires,
        Path     => '',
        HTTPOnly => 1,
    );
}

$RequestedURL = $ParamObject->GetCookie( Key => 'OTRSOIDCRequestedURL' ) || $RequestedURL;

print $LayoutObject->Redirect(
    OP => "index.pl?$RequestedURL",
);

exit 0;

sub _Error {
    my ($Message) = @_;

    $Kernel::OM->Get('Kernel::System::Log')->Log(
        Priority => 'error',
        Message  => "OIDC login error: $Message",
    );

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    print $LayoutObject->ErrorScreen(
        Message => $Message,
    );
    exit 1;
}
