# Architecture

## Goal

This project demonstrates a production-style deployment architecture for a
small Django web application.

The design aims to provide:

- repeatable application deployment
- separation between public and internal services
- PostgreSQL persistence
- Redis-backed caching
- reverse proxying through Nginx
- CI validation through GitHub Actions
- automated deployment through a deployment script
- backup and recovery procedures
- health checks and operational documentation
- basic production hardening

The architecture intentionally remains simple enough for small software teams
while retaining the operational practices expected from a production deployment.

---

## Components

### GitHub

Stores the application source code, infrastructure configuration,
documentation, CI workflow, and deployment scripts.

---

### GitHub Actions

GitHub Actions provides Continuous Integration.

The CI workflow currently performs:

- repository checkout
- Python environment setup
- dependency installation
- Django system checks
- automated tests
- database migration validation
- Docker Compose configuration validation
- Docker image build validation

GitHub Actions currently validates changes but does not automatically deploy
to production.

Deployment automation is handled separately through `scripts/deploy.sh`.

---

### Linux VPS

The intended production host is a Linux VPS running Docker and Docker Compose.

The VPS hosts:

- Nginx
- Django/Gunicorn
- PostgreSQL
- Redis

---

### Nginx

Nginx is the public entry point for application traffic.

Responsibilities include:

- receiving HTTP/HTTPS traffic
- reverse proxying requests to Gunicorn
- forwarding client/proxy headers
- TLS termination in production
- isolating the application server from direct public exposure

---

### Django + Gunicorn

Django provides the application.

Gunicorn runs Django as the production WSGI server.

The application listens internally on:

```text
8000/tcp
