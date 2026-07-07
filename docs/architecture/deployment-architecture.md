# Deployment Architecture

## Docker Image

OTRS Community Edition 6.0.41 can be deployed as a container image built from AlmaLinux 9.8.

### Components

- **Base image:** `almalinux:9.8`
- **Web server:** Apache `httpd` with `mod_perl`
- **Application path:** `/opt/otrs`
- **System user:** `otrs` (primary group `apache`)
- **Exposed port:** `80`

### Build

```bash
docker build -t otrs-ce:6.0.41 .
```

### Run

```bash
docker run -d \
  --name otrs-ce \
  -p 8080:80 \
  -v otrs-kernel:/opt/otrs/Kernel \
  -v otrs-var:/opt/otrs/var \
  otrs-ce:6.0.41
```

Open `http://localhost:8080/otrs/installer.pl` to complete the web installer.

### Kubernetes

Manifests are in `k8s/`. Deploy the full stack (MySQL 9.7 + OTRS):

```bash
kubectl apply -k k8s/
```

Wait for pods to become ready:

```bash
kubectl -n otrs get pods -w
```

Access OTRS:

```bash
kubectl -n otrs get svc otrs
```

Default database credentials are defined in `k8s/mysql-secret.yaml`:

- Database host: `mysql` (in-cluster service)
- Database name: `otrs`
- Database user: `otrs`
- Database password: `otrs-db-secret`

Default OTRS login after bootstrap:

- User: `root@localhost`
- Password: `Admin@123` (override with `OTRS_ADMIN_PASSWORD`)

### MySQL 9.7 Authentication

MySQL 9.7 uses `caching_sha2_password`, which requires SSL for remote connections. The bootstrap process configures the OTRS DSN with:

```text
mysql_ssl=1;mysql_ssl_verify_server_cert=0;
```

The MySQL init script sets `REQUIRE NONE` for the `otrs` database user.

### External Dependencies

The container image does not include a database server. Use an external MySQL/MariaDB or PostgreSQL instance and configure it through the OTRS installer.

### Persistent Data

Mount volumes for:

- `/opt/otrs/Kernel` — configuration and customizations
- `/opt/otrs/var` — articles, sessions, logs, and runtime data

### Background Services

After installation, the entrypoint starts the OTRS daemon and cron jobs automatically when `Kernel/Config.pm` contains database settings.
