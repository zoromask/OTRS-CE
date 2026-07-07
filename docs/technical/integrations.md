# Keycloak OIDC Login

OTRS CE supports agent login through Keycloak using the OpenID Connect authorization code flow.

## Architecture

```text
Browser -> OTRS /otrs/index.pl
        -> redirect LoginURL /otrs-auth/login
        -> Keycloak login
        -> callback /otrs-auth/login?code=...
        -> OTRS session created
        -> Agent dashboard
```

## Components

| File | Purpose |
|------|---------|
| `bin/cgi-bin/oidc-login.pl` | OIDC login entry point and callback handler |
| `bin/cgi-bin/oidc-logout.pl` | OIDC logout handler (sends `id_token_hint` to Keycloak) |
| `Custom/Kernel/System/Auth/OIDC/Client.pm` | Keycloak token and userinfo client |
| `Kernel/Config/Files/ZZZZKeycloakOIDC.pm` | Runtime configuration from environment variables or bootstrap-generated file |
| `docker/entrypoint.sh` | Writes Apache `SetEnv` directives so CGI handlers receive OIDC settings |

## Environment Variables

| Variable | Description |
|----------|-------------|
| `OTRS_KEYCLOAK_ENABLED` | Set to `1` to enable Keycloak login |
| `OTRS_FQDN` | Public hostname or IP used by browsers to reach OTRS |
| `OTRS_HTTP_TYPE` | `http` or `https` |
| `OTRS_SCRIPT_ALIAS` | Web path prefix, default `otrs/` |
| `OTRS_KEYCLOAK_ISSUER` | Public Keycloak realm issuer URL used in browser redirects |
| `OTRS_KEYCLOAK_INTERNAL_ISSUER` | Cluster-internal issuer URL for token and userinfo requests, e.g. `http://keycloak:8080/realms/otrs` |
| `OTRS_KEYCLOAK_CLIENT_ID` | OIDC client ID |
| `OTRS_KEYCLOAK_CLIENT_SECRET` | OIDC client secret |
| `OTRS_KEYCLOAK_USER_ATTRIBUTE` | Token claim mapped to OTRS login, default `preferred_username` |
| `OTRS_KEYCLOAK_USER_REGEXP` | Optional regexp to transform the claim into an OTRS login |

When `OTRS_KEYCLOAK_ENABLED=1`, OTRS sets:

- `LoginURL` to `/otrs-auth/login` (Apache `ScriptAlias`, outside mod_perl)
- `LogoutURL` to `/otrs-auth/logout`, which forwards the stored `id_token` to Keycloak as `id_token_hint`

In Kubernetes, `bootstrap-k8s.pl` persists these values to SysConfig and writes a static `ZZZZKeycloakOIDC.pm` on the kernel volume. The container entrypoint also generates `/etc/httpd/conf.d/zzz_otrs_oidc_env.conf` because Apache CGI does not inherit the pod environment by default.

## User Provisioning

Keycloak authentication succeeds only if the mapped username already exists in the OTRS `users` table.

Example:

- Keycloak username: `root@localhost`
- OTRS agent login: `root@localhost`

Create matching agent accounts in OTRS before first login.

## Kubernetes

Deploy Keycloak with the bundled manifests:

```bash
kubectl apply -k k8s/
```

Update `k8s/otrs-oidc-configmap.yaml` with the external IPs from:

```bash
kubectl -n otrs get svc otrs keycloak
```

Set:

- `OTRS_FQDN` to the OTRS LoadBalancer IP
- `OTRS_KEYCLOAK_ISSUER` to `http://<KEYCLOAK_IP>:8080/realms/otrs`
- `OTRS_KEYCLOAK_INTERNAL_ISSUER` to `http://keycloak:8080/realms/otrs`
- `KC_HOSTNAME` to the Keycloak LoadBalancer IP

On OrbStack, both `otrs` and `keycloak` services often share the same external IP (`192.168.139.2`) on ports **80** and **8080** respectively. Use that IP for both `OTRS_FQDN` and `KC_HOSTNAME`, not a separate `.3` address.

Restart both deployments after changing the config map.

### Default Keycloak Credentials

- Admin console: `admin` / `keycloak-admin`
- Test realm user: `root@localhost` / `Admin@123`
- OIDC client: `otrs-ce` / `otrs-keycloak-secret`

## Manual Docker Setup

```bash
export OTRS_KEYCLOAK_ENABLED=1
export OTRS_FQDN=localhost
export OTRS_KEYCLOAK_ISSUER=http://localhost:8080/realms/otrs
export OTRS_KEYCLOAK_CLIENT_ID=otrs-ce
export OTRS_KEYCLOAK_CLIENT_SECRET=otrs-keycloak-secret
```

Configure the Keycloak client redirect URI (exact match required in Keycloak 26; hostname wildcards like `http://*` are not supported):

```text
http://<OTRS_IP>/otrs-auth/login
```
