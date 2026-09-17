# Security

## Purpose

This document describes the basic security practices used or recommended for the Production Deployment Demo.

The goal is to reduce unnecessary exposure and establish sensible defaults for a small production deployment.

The security approach focuses on:

- SSH key authentication
- non-root administration
- least privilege
- minimal public port exposure
- firewall configuration
- HTTPS in production
- secrets outside source control
- private PostgreSQL access
- private Redis access
- operating system and container updates
- credential rotation
- backup protection

This document describes **basic production hardening**.

It is not a penetration test, formal security audit, compliance assessment, or advanced threat-detection design.

---

## Security Scope

The intended architecture is:

```text
Internet
   │
   ▼
Nginx
   │
   ▼
Django + Gunicorn
   │
   ├────────► PostgreSQL
   │
   └────────► Redis
```

Only Nginx should receive public application traffic.

PostgreSQL and Redis should remain private inside the internal Docker network.

---

## Public Network Exposure

A typical production VPS should expose only the ports required for administration and web traffic.

Expected public ports:

```text
22   SSH
80   HTTP
443  HTTPS
```

The application server, PostgreSQL, and Redis should not be directly exposed to the internet.

---

## Firewall

A host firewall should allow only required inbound traffic.

Using UFW, a basic production configuration could be:

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
```

Allow SSH:

```bash
sudo ufw allow OpenSSH
```

Allow HTTP:

```bash
sudo ufw allow 80/tcp
```

Allow HTTPS:

```bash
sudo ufw allow 443/tcp
```

Enable the firewall:

```bash
sudo ufw enable
```

Check status:

```bash
sudo ufw status verbose
```

Expected public services should be limited to:

```text
SSH
HTTP
HTTPS
```

Do not expose PostgreSQL or Redis through the host firewall unless there is a specific and secured operational requirement.

---

## SSH Authentication

Production administration should use SSH keys instead of password authentication where possible.

A recommended key type is:

```text
Ed25519
```

Generate a key:

```bash
ssh-keygen -t ed25519 -C "deployment-access"
```

Public key:

```text
~/.ssh/id_ed25519.pub
```

Private key:

```text
~/.ssh/id_ed25519
```

The private key must remain protected and should never be committed to Git.

---

## SSH Key Protection

Private SSH keys should:

- remain only on trusted devices
- use restrictive filesystem permissions
- use a passphrase where appropriate
- be removed when no longer required
- be rotated after suspected compromise

Example:

```bash
chmod 600 ~/.ssh/id_ed25519
```

---

## Non-Root Administration

Routine production administration should not be performed directly as `root`.

Create a dedicated administrative or deployment user.

Example:

```text
deploy
```

The user may receive controlled `sudo` access when required.

The principle is:

```text
normal administration
        ↓
non-root user
        ↓
sudo only when required
```

Direct root login increases the impact of mistakes and credential compromise.

---

## Least Privilege

Every user, service, and credential should receive only the permissions required to perform its role.

Examples include:

- Django uses dedicated PostgreSQL application credentials
- PostgreSQL administrative credentials are not used by the application
- Redis remains internal
- deployment users receive only required host permissions
- cloud credentials should be narrowly scoped
- backup credentials should only access required backup storage

Avoid broad administrative permissions when narrower access is sufficient.

---

## Docker Permissions

Docker access should be treated carefully.

Membership in the host:

```text
docker
```

group effectively grants very powerful control over the system and can often be used to obtain root-equivalent access.

Only trusted administrative users should be members of the Docker group.

Check membership:

```bash
getent group docker
```

Do not grant Docker access broadly.

---

## Nginx as Public Ingress

Nginx is the public entry point for application traffic.

Traffic should follow:

```text
Internet
   │
   ▼
Nginx
   │
   ▼
Gunicorn + Django
```

The Django application server should not be directly exposed to the public internet.

This limits public-facing application ports and keeps routing responsibilities centralized.

---

## Application Port

Gunicorn listens internally on:

```text
8000/tcp
```

The Docker Compose configuration should expose this port only to the internal Docker network.

It should not normally include:

```yaml
ports:
  - "8000:8000"
```

in a production deployment.

Nginx should reach the application through the Compose service name.

Example:

```text
http://app:8000
```

---

## PostgreSQL Network Exposure

PostgreSQL listens internally on:

```text
5432/tcp
```

The database should not be published directly to the host or public internet.

The Docker Compose service should avoid host mappings such as:

```yaml
ports:
  - "5432:5432"
```

unless remote database access is explicitly required and separately secured.

The application connects using:

```text
POSTGRES_HOST=db
```

where:

```text
db
```

is the internal Docker Compose service name.

---

## Redis Network Exposure

Redis listens internally on:

```text
6379/tcp
```

Redis should not normally be publicly accessible.

Avoid:

```yaml
ports:
  - "6379:6379"
```

for production deployments.

The application connects through:

```text
redis://redis:6379/0
```

where:

```text
redis
```

is the internal Docker Compose service name.

---

## Verify Port Exposure

Check running containers:

```bash
docker compose ps
```

Also inspect:

```bash
docker ps
```

Expected architecture:

```text
Nginx        public
App          internal
PostgreSQL   internal
Redis        internal
```

PostgreSQL and Redis should not show public host mappings.

---

## Secrets Management

Sensitive configuration should not be stored directly in source code.

Examples of secrets include:

- Django secret keys
- database passwords
- API keys
- access tokens
- SSH private keys
- cloud credentials
- backup storage credentials

The repository contains:

```text
.env.example
```

with safe placeholder values.

The actual:

```text
.env
```

file contains local or production configuration and must not be committed.

---

## Verify `.env` Is Ignored

Run:

```bash
git check-ignore .env
```

Expected:

```text
.env
```

Check Git status:

```bash
git status
```

The real `.env` should not appear as a tracked file.

Check tracked environment files:

```bash
git ls-files | grep -E '(^|/)\.env$'
```

This command should return nothing for the real `.env` file.

---

## Search for Accidentally Committed Secrets

Search tracked files for common secret patterns:

```bash
git grep -niE 'password|secret|token|api[_-]?key|private[_-]?key'
```

Review any matches carefully.

Some matches may be harmless documentation or variable names, but real credentials must not appear in source control.

---

## Environment File Permissions

On a real server, the `.env` file should have restrictive permissions.

Example:

```bash
chmod 600 .env
```

Check:

```bash
ls -l .env
```

Only the required administrative user should be able to read production secrets.

---

## HTTPS

Production deployments should use HTTPS.

Recommended traffic flow:

```text
Client
   │
   │ HTTPS
   ▼
Nginx
   │
   │ HTTP/internal network
   ▼
Django + Gunicorn
```

TLS should normally terminate at Nginx.

The local demo currently uses HTTP only.

HTTPS is therefore a production requirement rather than a locally implemented feature.

---

## TLS Certificates

A production deployment can use a certificate provider such as Let's Encrypt.

A common setup uses Certbot with Nginx.

Example package installation:

```bash
sudo apt update
sudo apt install certbot python3-certbot-nginx
```

Certificate request:

```bash
sudo certbot --nginx -d example.com -d www.example.com
```

The exact domain configuration will depend on the production environment.

---

## Certificate Renewal

Certificates must be renewed before expiration.

Check Certbot renewal:

```bash
sudo certbot renew --dry-run
```

Certificate expiry should also be monitored.

Example:

```bash
echo | \
openssl s_client -servername example.com -connect example.com:443 2>/dev/null | \
openssl x509 -noout -dates
```

---

## Django Production Settings

Production configuration should use:

```text
DEBUG=False
```

The environment file should contain:

```env
DJANGO_DEBUG=False
```

Debug mode should not be enabled on a public production deployment.

Django debug pages may expose sensitive configuration, stack traces, internal paths, and application details.

---

## Allowed Hosts

Django should only accept expected hostnames.

Example:

```env
DJANGO_ALLOWED_HOSTS=example.com,www.example.com
```

For local development:

```env
DJANGO_ALLOWED_HOSTS=localhost,127.0.0.1
```

Do not use overly broad host configuration without a clear reason.

---

## Django Secret Key

The production Django secret key should be long, random, and unique.

Do not use:

```text
change-me
```

in production.

Generate a strong secret before deployment.

For example:

```bash
python -c 'import secrets; print(secrets.token_urlsafe(64))'
```

Store it in the production environment rather than in Git.

---

## Database Credentials

Production PostgreSQL credentials should:

- use a dedicated application user
- use a strong password
- not reuse unrelated credentials
- not use a PostgreSQL superuser for normal application access
- be rotated if exposure is suspected

Example variables:

```env
POSTGRES_DB=appdb
POSTGRES_USER=appuser
POSTGRES_PASSWORD=strong-random-password
```

---

## Credential Rotation

Credentials should be rotated when:

- a team member no longer requires access
- a credential is accidentally exposed
- a laptop or server is compromised
- a repository secret is committed
- an external integration is removed
- periodic security policy requires rotation

Potential credentials include:

```text
SSH keys
database passwords
API tokens
cloud credentials
backup credentials
deployment credentials
```

Rotation should include removal of the old credential after the replacement has been verified.

---

## Operating System Updates

Production systems should receive security updates.

On Ubuntu/Debian systems:

```bash
sudo apt update
sudo apt upgrade
```

Review updates before applying significant changes to critical production systems.

Regular patching reduces exposure to known vulnerabilities.

---

## Container Image Updates

Containers also require maintenance.

Images such as:

```text
python
nginx
postgres
redis
```

should not remain indefinitely on outdated versions.

Rebuild images periodically:

```bash
docker compose build --pull
```

Then test before production deployment.

Updates should be validated through CI and deployment testing.

---

## Minimal Container Images

Use reasonably small, trusted base images where practical.

Examples used by this project include:

```text
python:3.12-slim
postgres:16-alpine
redis:7-alpine
nginx:alpine
```

Smaller images can reduce unnecessary packages and attack surface, although image size alone is not a complete security measure.

---

## Container Privileges

Containers should not run with unnecessary elevated privileges.

Avoid settings such as:

```yaml
privileged: true
```

unless absolutely required.

This application stack does not require privileged containers.

---

## Secrets in Docker Images

Secrets should not be baked into Docker images.

Avoid Dockerfile instructions such as:

```dockerfile
ENV DATABASE_PASSWORD=real-password
```

or:

```dockerfile
COPY .env /app/.env
```

Production secrets should be supplied at runtime.

---

## Backup Security

Database backups may contain all persistent application data.

Backups must therefore be protected.

Production backups should be:

- excluded from Git
- access controlled
- stored outside public directories
- encrypted where appropriate
- transferred securely
- retained only as required
- removed securely when no longer required

---

## Backup Directory

Local backups are stored under:

```text
backups/
```

This directory should be included in `.gitignore`.

Verify:

```bash
git check-ignore backups/
```

Backups should not be committed to a public repository.

---

## Off-Server Backups

A production system should not keep its only backup copy on the same VPS as the database.

Recommended flow:

```text
PostgreSQL
    │
    ▼
Local Backup
    │
    ▼
Encrypted / Controlled Off-Server Storage
```

This protects against:

- complete VPS failure
- filesystem corruption
- accidental server deletion
- ransomware or destructive compromise
- storage-device failure

---

## Logging and Sensitive Data

Application logs should not intentionally contain:

- passwords
- secret keys
- authentication tokens
- session values
- private credentials

When debugging authentication or configuration problems, avoid printing full secrets into logs.

Logs themselves may contain sensitive application information and should have controlled access.

---

## Security Updates and Maintenance

Production hardening is not a one-time task.

A basic maintenance cycle should include:

```text
review OS updates
        ↓
review container updates
        ↓
review exposed ports
        ↓
review active SSH keys
        ↓
review credentials
        ↓
review backups
        ↓
review logs
```

Security degrades over time if configuration is never revisited.

---

## Security Validation

Use the following questions to validate the deployment:

```text
Is PostgreSQL publicly exposed?
Expected: No

Is Redis publicly exposed?
Expected: No

Is the real .env file tracked by Git?
Expected: No

Are secrets hardcoded in source code?
Expected: No

Does routine administration require root login?
Expected: No

Are unnecessary ports publicly available?
Expected: No

Is Django DEBUG enabled in production?
Expected: No

Are database backups committed to Git?
Expected: No
```

---

## Validation Commands

Check container exposure:

```bash
docker compose ps
```

Check Docker ports:

```bash
docker ps
```

Check Git status:

```bash
git status
```

Verify `.env` exclusion:

```bash
git check-ignore .env
```

Check whether the real `.env` is tracked:

```bash
git ls-files | grep -E '(^|/)\.env$'
```

Search for potential secrets:

```bash
git grep -niE 'password|secret|token|api[_-]?key|private[_-]?key'
```

Check firewall status on a real VPS:

```bash
sudo ufw status verbose
```

Check Nginx configuration:

```bash
docker compose exec nginx nginx -t
```

---

## Security Checklist

A basic production review should verify:

```text
[ ] SSH key authentication is used
[ ] routine administration uses a non-root account
[ ] sudo access is limited
[ ] Docker access is limited to trusted users
[ ] firewall is enabled
[ ] only required public ports are open
[ ] Nginx is the public application entry point
[ ] Gunicorn is not directly public
[ ] PostgreSQL is not publicly exposed
[ ] Redis is not publicly exposed
[ ] Django DEBUG is disabled
[ ] ALLOWED_HOSTS is configured
[ ] Django secret key is strong and private
[ ] database credentials use least privilege
[ ] .env is excluded from Git
[ ] real secrets are absent from repository history
[ ] HTTPS is enabled in production
[ ] certificates are renewed
[ ] operating system receives security updates
[ ] container images are maintained
[ ] containers do not use unnecessary privileges
[ ] backups are excluded from Git
[ ] backups are protected
[ ] off-server backups exist for production
[ ] credentials can be rotated
```

---

## Local Demo vs Production

The local demonstration implements or validates:

```text
internal PostgreSQL networking
internal Redis networking
Nginx reverse proxy
environment-based secrets
.env Git exclusion
Docker service separation
basic validation commands
```

The following are documented production recommendations and are not necessarily implemented in the local demo:

```text
UFW firewall
real VPS SSH hardening
HTTPS certificates
TLS renewal
off-server backup storage
production secret-management platform
external monitoring
centralized security logging
```

This distinction is intentional.

The project should not claim that a security feature has been implemented when it has only been documented.

---

## Security Boundary

This repository demonstrates **basic production deployment hardening**.

It does not provide:

- penetration testing
- web application security testing
- vulnerability scanning
- intrusion detection
- Web Application Firewall tuning
- DDoS protection
- security compliance certification
- SOC monitoring
- advanced secrets management
- formal threat modeling
- zero-trust architecture

Those controls may be appropriate for higher-risk or larger production systems.

---

## Incident Response Basics

If a credential is exposed:

```text
revoke credential
      ↓
create replacement
      ↓
update production configuration
      ↓
restart affected service
      ↓
verify functionality
      ↓
investigate exposure
```

If a secret was committed to Git, deleting the line in a later commit is not enough.

The credential should be considered compromised and rotated.

Repository history may also require cleanup depending on the sensitivity and exposure.

---

## Security Philosophy

The goal is not to make the system theoretically invulnerable.

The goal is to reduce avoidable risk through simple, repeatable controls:

```text
minimize exposure
       ↓
use least privilege
       ↓
protect secrets
       ↓
patch systems
       ↓
protect data
       ↓
monitor failures
       ↓
rotate compromised access
```

For a small deployment, simple controls applied consistently are more useful than a complicated security design that is never maintained.

---

## Summary

The intended security boundary is:

```text
                Internet
                   │
            ports 80 / 443
                   │
                   ▼
              ┌─────────┐
              │  Nginx  │
              └────┬────┘
                   │
          Internal Docker Network
                   │
                   ▼
          ┌─────────────────┐
          │ Django/Gunicorn │
          └───────┬─────────┘
                  │
             ┌────┴────┐
             ▼         ▼
        PostgreSQL    Redis
          private     private
```

Administrative access:

```text
Administrator
      │
      │ SSH key
      ▼
Non-root user
      │
      │ controlled sudo
      ▼
Linux VPS
```

The core principle is:

> Expose only what must be public, keep data services private, protect credentials, and grant the minimum access required.
