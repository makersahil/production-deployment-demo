# Architecture

## Goal

This project demonstrates a production-style deployment architecture for a small Django web application.

The design focuses on:

- repeatable application deployment
- separation between public and internal services
- PostgreSQL persistence
- Redis integration
- reverse proxying through Nginx
- CI validation through GitHub Actions
- deployment automation through Bash scripts
- health checks
- backup and recovery procedures
- rollback procedures
- lightweight monitoring
- basic production hardening

The architecture is intentionally simple enough for small software teams while still demonstrating practical production operations.

---

## Architecture Diagram

![Production deployment architecture](architecture.png)

---

## Components

### GitHub

GitHub stores:

- application source code
- Docker configuration
- Nginx configuration
- CI workflow
- deployment scripts
- operational documentation

---

### GitHub Actions

GitHub Actions provides Continuous Integration.

The CI workflow performs:

- repository checkout
- Python environment setup
- dependency installation
- Django system checks
- database migration validation
- automated tests
- Docker Compose validation
- Docker image build validation

GitHub Actions currently validates changes but does not automatically deploy the application to production.

Deployment is handled separately through:

```text
scripts/deploy.sh
```

---

### Linux VPS

The intended production environment is a Linux VPS running Docker and Docker Compose.

The VPS hosts:

- Nginx
- Django + Gunicorn
- PostgreSQL
- Redis

---

### Nginx

Nginx is the public entry point for application traffic.

Responsibilities include:

- receiving HTTP/HTTPS traffic
- reverse proxying requests to Gunicorn
- forwarding client and proxy headers
- TLS termination in production
- preventing direct public access to the Django application server

---

### Django + Gunicorn

Django provides the application.

Gunicorn runs Django as the production WSGI server.

The application listens internally on:

```text
8000/tcp
```

It is not intended to be directly exposed to the public internet.

---

### PostgreSQL

PostgreSQL provides persistent relational data storage.

The database:

- uses a dedicated application database
- uses dedicated application credentials
- stores persistent data in a Docker volume
- communicates with Django through the internal Docker network
- is not publicly exposed

---

### Redis

Redis provides application cache/connectivity functionality.

Redis:

- runs as a separate container
- communicates with Django through the internal Docker network
- is not publicly exposed

---

## Request Flow

Application traffic follows this path:

```text
Client
  │
  │ HTTP / HTTPS
  ▼
Nginx
  │
  │ reverse proxy
  ▼
Gunicorn
  │
  ▼
Django
  │
  ├──────────────► PostgreSQL
  │
  └──────────────► Redis
```

In production, Nginx should terminate HTTPS.

The application, PostgreSQL, and Redis remain behind the public ingress layer.

---

## Deployment Flow

Development and deployment are intentionally separated.

### Continuous Integration

```text
Developer
   │
   │ git push
   ▼
GitHub
   │
   ▼
GitHub Actions
   │
   ├── Django checks
   ├── automated tests
   ├── migration validation
   ├── Docker Compose validation
   └── Docker image build
```

CI answers:

```text
Can this change safely build and pass validation?
```

---

### Deployment

Deployment is currently performed using:

```text
scripts/deploy.sh
```

Deployment flow:

```text
Validated repository
        │
        ▼
scripts/deploy.sh
        │
        ├── validate environment
        ├── obtain latest code
        ├── validate Docker Compose
        ├── build application image
        ├── start PostgreSQL
        ├── start Redis
        ├── wait for dependencies
        ├── run Django migrations
        ├── start application
        ├── start Nginx
        └── run health check
```

The deployment script uses:

```bash
set -euo pipefail
```

so critical failures stop deployment instead of allowing a false successful result.

---

## Network Boundaries

The intended network exposure is:

```text
PUBLIC NETWORK
────────────────────────────────────

Internet
   │
   ▼
Nginx
Ports: 80 / 443

────────────────────────────────────
INTERNAL DOCKER NETWORK

Django + Gunicorn
Port: 8000

PostgreSQL
Port: 5432

Redis
Port: 6379
```

Only Nginx should receive public application traffic.

PostgreSQL and Redis should not have public host port mappings.

---

## Persistent Data

PostgreSQL data is stored using the Docker volume:

```text
postgres_data
```

This allows database data to survive normal application container recreation.

Commands such as:

```bash
docker compose down -v
```

should not be used casually in production because `-v` removes Docker volumes and can destroy persistent database data.

Application containers are replaceable.

Persistent database data is not.

---

## Failure Scenarios

### Application Container Failure

Possible symptoms:

- `/health/` fails
- Nginx returns HTTP 502
- application container stops
- application container repeatedly restarts

Diagnosis:

```bash
docker compose ps
docker compose logs app
docker compose logs nginx
```

Recovery may include:

```bash
docker compose restart app
```

or redeploying a previous known-good release.

---

### PostgreSQL Failure

Possible symptoms:

- database-backed requests fail
- Django reports database connection errors

Diagnosis:

```bash
docker compose exec db pg_isready
docker compose logs db
```

Recovery depends on the cause of the failure.

Persistent data should be protected using Docker volumes and PostgreSQL backups.

---

### Redis Failure

Possible symptoms:

- cache-related failures
- Redis connection errors
- reduced application functionality

Diagnosis:

```bash
docker compose exec redis redis-cli ping
docker compose logs redis
```

Expected healthy response:

```text
PONG
```

---

### Nginx Failure

Possible symptoms:

- application is unavailable externally
- internal application services may still be healthy

Validate Nginx configuration:

```bash
docker compose exec nginx nginx -t
```

Inspect logs:

```bash
docker compose logs nginx
```

---

### Broken Application Release

If a newly deployed release introduces errors, return to a previous known-good version.

See:

```text
docs/rollback.md
```

Application rollback and database rollback must be evaluated separately.

---

## Backup & Recovery

PostgreSQL backups are created using:

```text
scripts/backup.sh
```

Backup flow:

```text
PostgreSQL
    │
    │ pg_dump
    ▼
SQL Dump
    │
    │ gzip
    ▼
postgres-TIMESTAMP.sql.gz
```

Local backup files are stored under:

```text
backups/
```

The backup directory is excluded from Git.

Backup validation includes:

1. creating a PostgreSQL dump
2. compressing the dump
3. storing the backup
4. validating the archive
5. restoring into a temporary database
6. verifying expected data
7. removing the temporary verification database

A backup is not considered reliable until restoration has been tested.

For the full procedure, see:

```text
docs/backups.md
```

For real production use, backups should also be stored on durable off-server storage.

---

## Security Considerations

The architecture follows basic production-hardening principles.

### Public Exposure

Only required services should be exposed publicly.

Typical production ports:

```text
22   SSH
80   HTTP
443  HTTPS
```

PostgreSQL and Redis remain internal.

---

### SSH

Production administration should use:

- SSH key authentication
- non-root administrative users
- controlled sudo privileges
- least privilege

---

### Secrets

Real secrets must remain outside source control.

The repository contains:

```text
.env.example
```

for safe configuration examples.

The real:

```text
.env
```

file is excluded using `.gitignore`.

Secrets include:

- Django secret keys
- database passwords
- API tokens
- private keys
- cloud credentials

---

### HTTPS

Production deployments should use HTTPS terminated at Nginx.

The local demo currently operates over HTTP.

---

### Least Privilege

Services and users should receive only the permissions required for their role.

Examples:

- dedicated PostgreSQL application user
- no unnecessary public database ports
- Redis kept internal
- non-root server administration
- credentials scoped to their intended purpose

---

### Backup Protection

Database backups may contain sensitive application data.

Production backups should therefore be:

- access controlled
- encrypted where appropriate
- excluded from Git
- stored off-server
- retained according to policy
- periodically restore-tested

For additional security guidance, see:

```text
docs/security.md
```

---

## Architecture Summary

```text
Developer
   │
   │ git push
   ▼
GitHub
   │
   ▼
GitHub Actions
   │
   │ CI validation
   ▼
Validated Release
   │
   │ scripts/deploy.sh
   ▼

┌─────────────────────────────────────┐
│              Linux VPS              │
│                                     │
│        ┌─────────────────┐          │
│        │      Nginx      │          │
│        │     80 / 443    │          │
│        └────────┬────────┘          │
│                 │                   │
│                 ▼                   │
│        ┌─────────────────┐          │
│        │    Gunicorn     │          │
│        │    + Django     │          │
│        │      :8000      │          │
│        └────────┬────────┘          │
│                 │                   │
│          ┌──────┴──────┐            │
│          ▼             ▼            │
│   ┌────────────┐ ┌────────────┐     │
│   │ PostgreSQL │ │   Redis    │     │
│   │   :5432    │ │   :6379   │     │
│   └─────┬──────┘ └────────────┘     │
│         │                           │
│         ▼                           │
│  postgres_data                     │
│         │                           │
│         ▼                           │
│      Backups                       │
│                                     │
└─────────────────────────────────────┘
```

This architecture is designed to remain simple, observable, recoverable, secure by default, and maintainable for small production workloads.
