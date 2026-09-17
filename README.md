# Production Deployment Demo

## Overview

This repository demonstrates a production-style deployment workflow for a Django web application using Docker Compose, Nginx, Gunicorn, PostgreSQL, Redis, and GitHub Actions.

The goal is to show how a small web application can move from source code into a repeatable, maintainable deployment environment with:

- containerized services
- reverse proxying
- PostgreSQL persistence
- Redis integration
- automated CI validation
- deployment automation
- health checks
- backups and restore testing
- rollback procedures
- monitoring documentation
- basic security hardening

The project intentionally keeps the application itself simple so the focus remains on deployment and operations.

---

## Architecture

![Production deployment architecture](docs/architecture.png)

High-level flow:

```text
Developer
    ↓
GitHub
    ↓
GitHub Actions
    ↓
CI validation
    ↓
scripts/deploy.sh
    ↓
Linux VPS / Docker Compose
    ↓
Nginx
    ↓
Django + Gunicorn
    ↓
PostgreSQL / Redis
