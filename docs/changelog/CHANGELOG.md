# Changelog

## 2026-07-08

### Added

- Kubernetes manifests for OTRS CE and MySQL 9.7 in `k8s/`
- `docker/bootstrap-k8s.pl` to initialize the database and OTRS configuration in Kubernetes

### Changed

- OTRS database connection uses MySQL SSL (`mysql_ssl=1`) for compatibility with MySQL 9.7 authentication

## 2026-07-07

### Added

- Dockerfile for OTRS Community Edition 6.0.41 based on AlmaLinux 9.8
- Docker build helpers in `docker/otrs-setup.sh` and `docker/entrypoint.sh`
- Deployment and configuration documentation for containerized installs
