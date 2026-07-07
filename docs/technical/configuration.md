# Configuration

## Docker Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `OTRS_HOME` | `/opt/otrs` | OTRS installation directory |
| `OTRS_USER` | `otrs` | System user that owns runtime files |
| `OTRS_VERSION` | `6.0.41` | Packaged OTRS CE version |
| `LANG` | `en_US.UTF-8` | Locale for the container |
| `OTRS_ADMIN_PASSWORD` | `Admin@123` | Initial password for `root@localhost` on first bootstrap |

## Apache

The image links `/opt/otrs/scripts/apache2-httpd.include.conf` to `/etc/httpd/conf.d/zzz_otrs.conf`.

OTRS is served under `/otrs/` with static assets under `/otrs-web/`.

## First-Time Setup

1. Build or pull the image.
2. Start the container and map port `80`.
3. Open `/otrs/installer.pl` in a browser.
4. Provide database connection details for an external database server.
5. Complete the installer and restart the container so daemon and cron services start.

## Volumes

Recommended persistent mounts:

```text
/opt/otrs/Kernel
/opt/otrs/var
```
