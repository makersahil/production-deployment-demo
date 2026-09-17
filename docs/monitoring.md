# Monitoring

## Purpose

This document describes the lightweight monitoring approach used for the Production Deployment Demo.

The goal is to answer four operational questions:

```text
Is the application reachable?
Is the application healthy?
Is the system degrading?
If something fails, can the cause be identified quickly?
```

The monitoring approach is intentionally simple and suitable for a small application deployment.

It focuses on:

- HTTP availability
- application health
- container state
- CPU and memory usage
- disk usage
- PostgreSQL availability
- Redis availability
- backup status
- SSL certificate expiry
- application logs
- Nginx logs
- database logs
- basic failure validation

For larger environments, this approach can later be extended with centralized metrics, alerting, dashboards, and log aggregation.

---

## HTTP Availability

The first question is whether the application is reachable.

Check the root endpoint:

```bash
curl -i http://localhost/
```

Expected response:

```text
HTTP/1.1 200 OK
```

The application should return:

```json
{
  "service": "production-deployment-demo",
  "status": "running"
}
```

---

## Application Health

The project exposes a dedicated health endpoint:

```text
/health/
```

Check it with:

```bash
curl -i http://localhost/health/
```

Expected response:

```text
HTTP/1.1 200 OK
```

Expected body:

```json
{
  "status": "healthy"
}
```

The health endpoint provides a simple indication that the application can respond successfully.

---

## Health Check Script

The repository includes:

```text
scripts/healthcheck.sh
```

Run:

```bash
./scripts/healthcheck.sh
```

The script checks:

```text
http://localhost/health/
```

and exits with a failure status if the request fails or the expected response is not returned.

Example successful output:

```text
Checking application health at: http://localhost/health/
Health response: {"status": "healthy"}
Health check passed
```

This script can be used during:

- deployment validation
- manual health checks
- troubleshooting
- future automated monitoring

---

## HTTP Status Codes

Sometimes only the status code is required.

Check the root endpoint:

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://localhost/
```

Check the health endpoint:

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://localhost/health/
```

Expected:

```text
200
```

Repeated responses such as:

```text
500
502
503
504
```

should be investigated.

---

## Container Status

Check the complete Docker Compose stack:

```bash
docker compose ps
```

Expected services:

```text
app
db
redis
nginx
```

All required services should normally show a running state.

Watch for states such as:

```text
Exited
Restarting
Created
unhealthy
```

These may indicate service failure or configuration problems.

---

## Docker Process View

A broader Docker view can be obtained with:

```bash
docker ps
```

This shows:

- container names
- running state
- uptime
- published ports
- image names

To also include stopped containers:

```bash
docker ps -a
```

---

## CPU and Memory Usage

Check live container resource usage:

```bash
docker stats
```

For a one-time snapshot:

```bash
docker stats --no-stream
```

Monitor:

- CPU percentage
- memory usage
- memory limits
- network I/O
- block I/O
- process count

Unexpectedly high CPU or memory usage may indicate:

- application bugs
- expensive requests
- runaway processes
- database issues
- traffic spikes
- memory leaks

---

## Host Memory

Check system memory:

```bash
free -h
```

Important values include:

```text
total
used
available
swap
```

Low available memory combined with increasing swap usage may indicate memory pressure.

---

## Disk Usage

Check filesystem capacity:

```bash
df -h
```

Important locations include:

```text
/
Docker storage
backup storage
database storage
```

Disk exhaustion can cause:

- PostgreSQL write failures
- backup failures
- Docker failures
- application errors
- logging failures
- deployment failures

---

## Docker Disk Usage

Check Docker storage consumption:

```bash
docker system df
```

This displays disk usage from:

- images
- containers
- local volumes
- build cache

Old Docker images and build cache can consume significant disk space over time.

Cleanup should be performed carefully.

Do not remove volumes containing production database data.

---

## PostgreSQL Monitoring

Check PostgreSQL availability:

```bash
docker compose exec db pg_isready
```

A healthy database should report:

```text
accepting connections
```

A more explicit connectivity check:

```bash
docker compose exec db \
    psql \
    -U "$POSTGRES_USER" \
    -d "$POSTGRES_DB" \
    -c "SELECT 1;"
```

Expected result:

```text
1
```

---

## PostgreSQL Logs

Inspect recent PostgreSQL logs:

```bash
docker compose logs --tail=100 db
```

Follow logs in real time:

```bash
docker compose logs -f db
```

Look for:

- connection failures
- authentication failures
- database startup errors
- storage errors
- unexpected shutdowns
- recovery messages

---

## PostgreSQL Connection Issues

If Django cannot connect to PostgreSQL, check:

```bash
docker compose exec db pg_isready
```

Then verify:

```bash
docker compose ps
```

Then inspect:

```bash
docker compose logs db
docker compose logs app
```

Remember that:

```text
db
```

is the Docker Compose service hostname.

It resolves inside the Docker network, not from the normal host environment.

---

## Redis Monitoring

Check Redis:

```bash
docker compose exec redis redis-cli ping
```

Expected response:

```text
PONG
```

If Redis does not respond, inspect:

```bash
docker compose logs redis
```

Follow logs:

```bash
docker compose logs -f redis
```

---

## Backup Monitoring

Backups should be monitored as part of normal operations.

List backups:

```bash
ls -lht backups/
```

Find the latest backup:

```bash
ls -t backups/postgres-*.sql.gz | head -1
```

Store the latest backup path:

```bash
LATEST_BACKUP="$(ls -t backups/postgres-*.sql.gz | head -1)"
```

Check it:

```bash
echo "$LATEST_BACKUP"
```

Validate the gzip archive:

```bash
gunzip -t "$LATEST_BACKUP"
```

Inspect backup size:

```bash
ls -lh "$LATEST_BACKUP"
```

---

## Backup Failure Conditions

Backup monitoring should detect situations such as:

```text
no backup exists
latest backup is too old
backup file is empty
gzip archive is corrupted
backup script failed
disk is full
restore verification fails
```

The presence of a backup file alone does not prove recovery is possible.

Restore testing is documented in:

```text
docs/backups.md
```

---

## Application Logs

Inspect recent application logs:

```bash
docker compose logs --tail=100 app
```

Follow application logs:

```bash
docker compose logs -f app
```

Look for:

- Python exceptions
- Django errors
- database connection failures
- Redis connection failures
- migration errors
- Gunicorn worker failures
- repeated HTTP 500 errors

---

## Nginx Logs

Inspect recent Nginx logs:

```bash
docker compose logs --tail=100 nginx
```

Follow logs:

```bash
docker compose logs -f nginx
```

Nginx logs are particularly useful when diagnosing:

- HTTP 502 errors
- upstream connection failures
- application container outages
- proxy configuration problems

---

## Redis Logs

Inspect:

```bash
docker compose logs --tail=100 redis
```

Follow:

```bash
docker compose logs -f redis
```

---

## Combined Logs

View logs from the complete stack:

```bash
docker compose logs --tail=100
```

Follow all services:

```bash
docker compose logs -f
```

For troubleshooting, service-specific logs are usually easier to interpret.

---

## Nginx Configuration Validation

Check that the Nginx configuration is valid:

```bash
docker compose exec nginx nginx -t
```

Expected output should indicate that:

```text
syntax is ok
test is successful
```

A failed configuration test should be corrected before restarting or redeploying Nginx.

---

## SSL Certificate Expiry

A real production deployment should monitor TLS certificate expiry.

Example:

```bash
echo | \
openssl s_client -servername example.com -connect example.com:443 2>/dev/null | \
openssl x509 -noout -dates
```

Example output:

```text
notBefore=...
notAfter=...
```

The `notAfter` value indicates certificate expiration.

Certificates should be renewed before expiration.

The local demo currently uses HTTP and does not implement real TLS certificates.

SSL expiry monitoring is therefore documented as a production requirement rather than a locally implemented feature.

---

## Deployment Health Validation

After deployment, always verify:

```bash
docker compose ps
```

Then:

```bash
./scripts/healthcheck.sh
```

Then:

```bash
curl -i http://localhost/
```

A deployment should not be considered successful merely because Docker commands completed.

The application itself must respond correctly.

---

## Failure Simulation

Monitoring should be tested before a real incident occurs.

A simple controlled failure can be created by stopping the application container.

Run:

```bash
docker compose stop app
```

Check service status:

```bash
docker compose ps
```

The application service should show as stopped.

---

## Verify Health Check Failure

Run:

```bash
./scripts/healthcheck.sh
```

The health check should fail.

Also run:

```bash
curl -i http://localhost/health/
```

Because Nginx is still running but the application upstream is unavailable, Nginx will typically return:

```text
502 Bad Gateway
```

---

## Inspect Failure Logs

Check Nginx:

```bash
docker compose logs --tail=50 nginx
```

You should see an upstream connection failure or similar diagnostic information.

Check application status:

```bash
docker compose ps
```

This demonstrates that monitoring can identify both:

```text
symptom:
HTTP failure

cause:
application container stopped
```

---

## Recover From the Test Failure

Restart the application:

```bash
docker compose start app
```

Verify:

```bash
docker compose ps
```

Then:

```bash
./scripts/healthcheck.sh
```

Expected:

```text
Health check passed
```

Confirm:

```bash
curl -i http://localhost/
```

and:

```bash
curl -i http://localhost/health/
```

Both should return successful responses again.

---

## Common Failure Signals

### HTTP 502

Usually indicates Nginx cannot reach the upstream application.

Check:

```bash
docker compose ps
docker compose logs app
docker compose logs nginx
```

---

### HTTP 500

Usually indicates an application-level error.

Check:

```bash
docker compose logs app
```

---

### PostgreSQL Connection Error

Check:

```bash
docker compose exec db pg_isready
docker compose logs db
docker compose logs app
```

---

### Redis Connection Error

Check:

```bash
docker compose exec redis redis-cli ping
docker compose logs redis
docker compose logs app
```

---

### Container Restart Loop

Check:

```bash
docker compose ps
```

Then:

```bash
docker compose logs SERVICE_NAME
```

Example:

```bash
docker compose logs app
```

---

### Disk Full

Check:

```bash
df -h
```

and:

```bash
docker system df
```

Also inspect:

```bash
du -sh backups/
```

---

## Basic Monitoring Checklist

A manual operational check can use:

```text
[ ] application root endpoint returns HTTP 200
[ ] /health/ returns HTTP 200
[ ] healthcheck.sh passes
[ ] Nginx container is running
[ ] application container is running
[ ] PostgreSQL container is running
[ ] Redis container is running
[ ] PostgreSQL accepts connections
[ ] Redis returns PONG
[ ] CPU usage is reasonable
[ ] memory usage is reasonable
[ ] sufficient disk space remains
[ ] recent backup exists
[ ] latest backup is valid
[ ] no repeated critical application errors
[ ] no repeated Nginx upstream errors
[ ] SSL certificate is valid in production
```

---

## Quick Diagnostic Sequence

When the application appears unavailable, use this order:

```bash
curl -i http://localhost/health/
```

Then:

```bash
docker compose ps
```

Then:

```bash
docker compose logs --tail=100 nginx
```

Then:

```bash
docker compose logs --tail=100 app
```

Then:

```bash
docker compose exec db pg_isready
```

Then:

```bash
docker compose exec redis redis-cli ping
```

Then:

```bash
df -h
```

This provides a fast path from external symptom to likely root cause.

---

## What Is Implemented

The local demo implements:

```text
HTTP health endpoint
healthcheck script
container status inspection
Docker resource inspection
disk inspection
PostgreSQL readiness checks
Redis health checks
backup inspection
application logs
Nginx logs
database logs
failure simulation
recovery validation
```

---

## What Is Not Implemented

The project does not currently include:

- Prometheus
- Grafana
- Datadog
- New Relic
- centralized log aggregation
- external uptime monitoring
- automatic alert delivery
- paging systems
- distributed tracing
- production TLS monitoring automation

These are reasonable extensions for larger or more critical systems, but they are intentionally outside the scope of this deployment demo.

---

## Production Monitoring Improvements

A real production environment could extend this setup with:

### External Uptime Monitoring

Check the application from outside the VPS rather than only from the server itself.

This detects:

- DNS failures
- firewall problems
- network outages
- Nginx failure
- total VPS failure

---

### Metrics Collection

Collect:

- CPU
- memory
- disk
- request rates
- error rates
- response latency
- database activity
- container restarts

Possible tooling could include:

```text
Prometheus
Grafana
cloud monitoring services
managed observability platforms
```

---

### Alerting

Alerts could be triggered when:

```text
application is unreachable
health endpoint fails
HTTP 5xx rate increases
CPU remains high
memory is nearly exhausted
disk space is low
database becomes unavailable
Redis becomes unavailable
backup becomes stale
TLS certificate approaches expiry
```

---

### Centralized Logs

Application and infrastructure logs could be forwarded to a central location.

This protects logs if the production VPS itself fails and makes searching historical incidents easier.

---

## Monitoring Philosophy

Monitoring should not simply collect large quantities of data.

It should provide enough information to answer:

```text
What failed?
When did it fail?
What changed?
Which component is responsible?
What action should be taken?
```

A small system does not require an enormous monitoring platform to be operable.

It does require reliable health checks, useful logs, resource visibility, and clear recovery procedures.

---

## Relationship With Other Runbooks

For deployment procedures:

```text
scripts/deploy.sh
```

For backups:

```text
docs/backups.md
```

For rollback:

```text
docs/rollback.md
```

For architecture:

```text
docs/architecture.md
```

For security:

```text
docs/security.md
```

Monitoring provides the signals that help determine when these operational procedures need to be used.

---

## Summary

The monitoring flow is:

```text
Client Request
      │
      ▼
    Nginx
      │
      ▼
Django / Gunicorn
      │
   ┌──┴───┐
   ▼      ▼
Postgres Redis
```

Each layer can be checked independently:

```text
HTTP
 ↓
health endpoint
 ↓
container state
 ↓
application logs
 ↓
database / Redis readiness
 ↓
host resources
 ↓
backup status
```

The core rule is:

> Monitoring should make failures visible, diagnosable, and actionable before they become mysteries.
