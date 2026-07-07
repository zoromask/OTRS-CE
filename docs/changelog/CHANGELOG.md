# Changelog

### Fixed

- OIDC logout now sends `id_token_hint` to Keycloak via `/otrs-auth/logout`
- OIDC userinfo request now sends the Bearer token correctly (`Header` vs `Headers` in WebUserAgent)

## 2026-07-08

### Added

- Keycloak OpenID Connect login for agents (`oidc-login.pl`, `Custom/Kernel/System/Auth/OIDC/Client.pm`)
- Keycloak Kubernetes manifests and OIDC configuration map
- Apache `SetEnv` generation in `docker/entrypoint.sh` for OIDC CGI handlers
- Bootstrap persistence of OIDC settings to SysConfig and `ZZZZKeycloakOIDC.pm`

### Changed

- OIDC login endpoint moved to `/otrs-auth/login` (outside mod_perl `Location /otrs`)
- OTRS database connection uses MySQL SSL (`mysql_ssl=1`) for compatibility with MySQL 9.7 authentication
- Agent login can be delegated to Keycloak via OpenID Connect

## 2026-07-07

### Added

- Dockerfile for OTRS Community Edition 6.0.41 based on AlmaLinux 9.8
- Docker build helpers in `docker/otrs-setup.sh` and `docker/entrypoint.sh`
- Deployment and configuration documentation for containerized installs
