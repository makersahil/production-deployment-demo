````markdown
# Rollback Procedure

## Purpose

This document describes the rollback procedure for the Production Deployment Demo.

The goal is to provide a controlled way to recover from a failed application release without immediately damaging persistent data.

Application rollback and database rollback are treated as separate operations.

A failed deployment does **not** automatically mean the database should be restored or migrations should be reversed.

---

## Rollback Triggers

A rollback should be considered when a newly deployed release causes issues such as:

- `/health/` fails
- repeated HTTP 5xx responses
- application container crash loops
- critical application functionality stops working
- deployment migrations fail
- application logs show release-specific fatal errors
- the service becomes unstable after deployment

The decision to rollback should be based on observable failure rather than assumption.

---

## Rollback Principle

The rollback flow is:

```text
detect failure
      ↓
preserve evidence
      ↓
identify current release
      ↓
identify known-good release
      ↓
check database migration impact
      ↓
restore previous application version
      ↓
rebuild containers
      ↓
verify application health
      ↓
investigate root cause
```

---

## Before Rolling Back

Do not immediately overwrite the failed release.

First collect enough information to understand what happened.

---

## Check Current Service State

Run:

```bash
docker compose ps
```

Look for:

- stopped containers
- restarting containers
- unhealthy services
- unexpected service states

---

## Check Application Health

Run:

```bash
curl -i http://localhost/health/
```

Expected healthy response:

```json
{
  "status": "healthy"
}
```

If the request fails or returns an unexpected response, continue investigation.

---

## Preserve Logs

Create a directory for rollback investigation logs:

```bash
mkdir -p rollback-logs
```

Save application logs:

```bash
docker compose logs app > rollback-logs/app.log
```

Save Nginx logs:

```bash
docker compose logs nginx > rollback-logs/nginx.log
```

Save PostgreSQL logs:

```bash
docker compose logs db > rollback-logs/db.log
```

Save Redis logs:

```bash
docker compose logs redis > rollback-logs/redis.log
```

Preserving logs before changing the environment helps with later root-cause analysis.

---

## Identify the Current Release

Check the currently deployed Git commit:

```bash
git rev-parse HEAD
```

For a shorter version:

```bash
git rev-parse --short HEAD
```

View recent history:

```bash
git log --oneline --decorate -10
```

Example:

```text
7e21f34 feat: add new application change
4c861af docs: add rollback procedure
be26fa6 feat: add production deployment demo stack
```

Record the current failing commit before changing anything.

---

## Identify a Known-Good Release

Use Git history to find the last release known to work correctly.

Run:

```bash
git log --oneline
```

Select the commit immediately before the failing release, or another commit already verified as stable.

Example:

```text
GOOD_COMMIT=be26fa6
```

Do not choose a commit blindly.

Confirm that the selected release previously passed:

- CI
- application health checks
- deployment validation

---

## Check Database Migration Changes

Before rolling application code backward, check whether the failing release introduced database migrations.

Compare the known-good release with the failing release:

```bash
git diff GOOD_COMMIT..BAD_COMMIT -- application/*/migrations/
```

You can also inspect migrations with:

```bash
docker compose exec app python manage.py showmigrations
```

Database changes require special caution.

Examples of potentially dangerous changes include:

- dropped columns
- dropped tables
- renamed columns
- changed field types
- destructive data migrations
- migrations that transform existing records
- migrations incompatible with the previous application version

Do not automatically reverse database migrations simply because the application is being rolled back.

---

## Create a Safety Backup

Before making database-related rollback changes, create a database backup:

```bash
./scripts/backup.sh
```

Confirm that the backup exists:

```bash
ls -lht backups/
```

If the database is still operational, preserving its current state gives you another recovery option.

---

## Application Rollback

Once a known-good Git commit has been identified, check it out:

```bash
git checkout GOOD_COMMIT
```

Example:

```bash
git checkout be26fa6
```

This places Git in detached HEAD mode.

That is acceptable for temporary rollback validation.

---

## Rebuild the Application

Build the application image from the known-good source:

```bash
docker compose build app
```

---

## Restart the Application

Start the application and Nginx using the known-good release:

```bash
docker compose up -d app nginx
```

Check service status:

```bash
docker compose ps
```

---

## Verify the Rollback

Run the health check:

```bash
./scripts/healthcheck.sh
```

Or manually:

```bash
curl -i http://localhost/health/
```

Expected:

```json
{
  "status": "healthy"
}
```

Test the root endpoint:

```bash
curl -i http://localhost/
```

Expected:

```json
{
  "service": "production-deployment-demo",
  "status": "running"
}
```

---

## Verify PostgreSQL

Run:

```bash
docker compose exec db pg_isready
```

Expected output should indicate:

```text
accepting connections
```

Optionally verify database connectivity:

```bash
docker compose exec db \
    psql \
    -U "$POSTGRES_USER" \
    -d "$POSTGRES_DB" \
    -c "SELECT 1;"
```

---

## Verify Redis

Run:

```bash
docker compose exec redis redis-cli ping
```

Expected:

```text
PONG
```

---

## Review Logs After Rollback

Check application logs:

```bash
docker compose logs --tail=100 app
```

Check Nginx logs:

```bash
docker compose logs --tail=100 nginx
```

Look for:

- startup failures
- connection errors
- migration errors
- repeated exceptions
- HTTP upstream failures

---

## Returning to the Main Branch

After verifying the known-good commit, return to the main branch:

```bash
git checkout main
```

If the latest commit is known to be broken, do not immediately redeploy it.

Instead, either:

- revert the bad commit
- fix the issue in a new commit
- create a hotfix

---

## Revert a Bad Commit

A safe way to remove a bad release while preserving Git history is:

```bash
git revert BAD_COMMIT
```

Example:

```bash
git revert 7e21f34
```

This creates a new commit that reverses the changes introduced by the bad commit.

Push the revert:

```bash
git push origin main
```

Wait for CI to pass before deployment.

---

## Deploy the Reverted Version

After CI passes:

```bash
./scripts/deploy.sh
```

Then verify:

```bash
./scripts/healthcheck.sh
```

Also check:

```bash
docker compose ps
```

---

## Database Rollback

Database rollback must be handled separately from application rollback.

Do not automatically run reverse migrations.

First determine:

- which migrations were applied
- whether they are reversible
- whether they changed existing data
- whether the previous application version can operate with the current schema
- whether a database backup should be restored instead

---

## Inspect Applied Migrations

Run:

```bash
docker compose exec app python manage.py showmigrations
```

Compare this with the migration state expected by the known-good release.

---

## Reversible Migrations

Some Django migrations can be reversed using:

```bash
python manage.py migrate app_name migration_name
```

Inside Docker:

```bash
docker compose exec app \
    python manage.py migrate app_name migration_name
```

This should only be done after confirming the migration is safely reversible.

Do not guess migration targets during a production incident.

---

## Dangerous Migration Scenarios

Extra caution is required if a release:

```text
dropped a table
dropped a column
renamed fields
changed field types
rewrote existing data
deleted existing data
performed irreversible RunPython operations
```

In these cases, rolling the application code backward may not restore database compatibility.

A database backup may be required.

---

## Database Restore

If database restoration is necessary, follow:

```text
docs/backups.md
```

Do not restore the database simply because application code failed.

Database restoration should only be used when the database itself requires recovery.

---

## Simulated Rollback Test

Rollback procedures should be tested before they are needed during a real incident.

A simple validation sequence is:

```text
known-good release
       ↓
introduce controlled failure
       ↓
deploy failing release
       ↓
confirm failure
       ↓
preserve logs
       ↓
checkout known-good release
       ↓
rebuild application
       ↓
restart services
       ↓
confirm healthy response
```

---

## Example Controlled Failure

Start from a known-good state:

```bash
./scripts/healthcheck.sh
```

Record the good commit:

```bash
git rev-parse --short HEAD
```

Temporarily modify the health endpoint so it returns a failure.

For example:

```python
return JsonResponse({"status": "unhealthy"}, status=500)
```

Commit the intentional failure:

```bash
git add .
git commit -m "test: simulate failed release"
```

Deploy:

```bash
./scripts/deploy.sh
```

The health check should fail.

Verify:

```bash
curl -i http://localhost/health/
```

Expected:

```text
HTTP/1.1 500 Internal Server Error
```

---

## Test the Rollback

Find the previous known-good commit:

```bash
git log --oneline -5
```

Checkout the good commit:

```bash
git checkout GOOD_COMMIT
```

Rebuild:

```bash
docker compose build app
```

Restart:

```bash
docker compose up -d app nginx
```

Verify:

```bash
./scripts/healthcheck.sh
```

The health check should pass again.

---

## Restore the Main Branch After Testing

Return to:

```bash
git checkout main
```

Revert the intentional failure:

```bash
git revert HEAD
```

If necessary, use the actual commit hash instead:

```bash
git revert BAD_COMMIT
```

Push:

```bash
git push origin main
```

After CI succeeds, deploy:

```bash
./scripts/deploy.sh
```

Verify:

```bash
./scripts/healthcheck.sh
```

---

## Rollback Validation Checklist

Before declaring rollback successful, verify:

```text
[ ] correct known-good commit identified
[ ] failure logs preserved
[ ] database migration impact reviewed
[ ] safety database backup created if required
[ ] application rebuilt successfully
[ ] application container running
[ ] Nginx running
[ ] /health/ returns healthy response
[ ] root endpoint works
[ ] PostgreSQL accepts connections
[ ] Redis responds with PONG
[ ] application logs show no critical errors
[ ] Nginx logs show no repeated upstream failures
[ ] broken release reverted or fixed in Git
[ ] CI passes before redeployment
```

---

## Rollback vs Redeployment

Not every failure requires a rollback.

Some failures may be caused by:

- temporary dependency problems
- incorrect environment variables
- expired credentials
- unavailable external services
- disk exhaustion
- configuration mistakes

If the application release itself is not the cause, redeploying an older commit may not solve the problem.

Investigate first.

Rollback when the evidence indicates the new release introduced the failure.

---

## Rollback vs Restart

A restart is appropriate when:

- the application is healthy in code but a process crashed
- a container stopped unexpectedly
- a temporary service issue occurred

Example:

```bash
docker compose restart app
```

A rollback is appropriate when:

- the new application code is broken
- a new release causes health failures
- the new release introduces incompatible behavior

Restarting broken code only gives you freshly restarted broken code.

---

## Rollback vs Database Restore

These operations solve different problems.

### Application Rollback

Used when:

```text
new code is broken
```

Action:

```text
return to previous application version
```

### Database Restore

Used when:

```text
database state is damaged or incorrect
```

Action:

```text
restore data from a verified backup
```

Do not combine the two automatically.

---

## Post-Rollback Actions

After service has been restored:

1. record the failed commit
2. record the known-good commit used for rollback
3. preserve relevant logs
4. identify the root cause
5. create a fix in a separate commit or branch
6. run CI
7. test the fix
8. deploy only after validation
9. verify health again

---

## Incident Notes

For a real production incident, record at minimum:

```text
Incident time:
Failed commit:
Known-good commit:
Observed symptoms:
Rollback reason:
Database migrations involved:
Backup created:
Rollback result:
Root cause:
Fix commit:
```

This makes future debugging and operational improvement much easier.

---

## Recovery Principle

The core rollback principle is:

```text
preserve evidence
       ↓
protect data
       ↓
restore known-good code
       ↓
verify dependencies
       ↓
verify health
       ↓
fix root cause
```

Application recovery should prioritize service restoration without creating a second incident through unnecessary database changes.

---

## Summary

The rollback architecture is:

```text
New Release
    │
    ▼
Deployment
    │
    ▼
Health Check
    │
    ├──────── Healthy ───────► Continue
    │
    ▼
Failure
    │
    ▼
Preserve Logs
    │
    ▼
Check Migrations
    │
    ▼
Known-Good Commit
    │
    ▼
Rebuild Application
    │
    ▼
Restart Services
    │
    ▼
Verify Health
    │
    ▼
Investigate + Fix
```

The key rule is:

> Roll back application code deliberately, and treat database rollback as a separate recovery decision.
````
