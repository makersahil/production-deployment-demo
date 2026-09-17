# Backup and Restore

## Purpose

This document describes the PostgreSQL backup and restore procedure for the Production Deployment Demo.

The goal is to ensure that database backups are:

- easy to create
- compressed
- timestamped
- excluded from Git
- automatically retained for a limited period
- restorable
- periodically verified

A backup should not be considered reliable until it has been successfully restored and checked.

---

## Backup Scope

This project backs up the PostgreSQL database.

PostgreSQL contains the persistent application data.

Redis is treated as an internal cache/service and is not included in the database backup process.

Application source code is already stored in Git and is therefore handled separately from database backups.

---

## Backup Script

Backups are created using:

```text
scripts/backup.sh
```

Run:

```bash
./scripts/backup.sh
```

The script performs the following steps:

```text
load environment configuration
        ↓
verify PostgreSQL availability
        ↓
run pg_dump
        ↓
compress output with gzip
        ↓
store timestamped backup
        ↓
verify backup file exists
        ↓
remove backups older than retention period
```

---

## Backup Script

The backup script uses the following structure:

```bash
#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

if [[ ! -f ".env" ]]; then
    echo "ERROR: .env file not found"
    exit 1
fi

set -a
source .env
set +a

BACKUP_DIR="$PROJECT_ROOT/backups"
TIMESTAMP="$(date +"%Y-%m-%d-%H%M%S")"
BACKUP_FILE="$BACKUP_DIR/postgres-$TIMESTAMP.sql.gz"

mkdir -p "$BACKUP_DIR"

echo "Checking PostgreSQL availability..."

docker compose exec -T db \
    pg_isready \
    -U "$POSTGRES_USER" \
    -d "$POSTGRES_DB" >/dev/null

echo "Creating PostgreSQL backup..."

docker compose exec -T db \
    pg_dump \
    -U "$POSTGRES_USER" \
    -d "$POSTGRES_DB" \
    --no-owner \
    --no-privileges \
    | gzip > "$BACKUP_FILE"

if [[ ! -s "$BACKUP_FILE" ]]; then
    echo "ERROR: Backup file is empty"
    rm -f "$BACKUP_FILE"
    exit 1
fi

echo "Backup created successfully:"
ls -lh "$BACKUP_FILE"

echo "Removing local backups older than 7 days..."

find "$BACKUP_DIR" \
    -type f \
    -name "postgres-*.sql.gz" \
    -mtime +7 \
    -delete

echo "Backup completed successfully."
```

Make the script executable:

```bash
chmod +x scripts/backup.sh
```

---

## Backup Location

Local backups are stored under:

```text
backups/
```

Example:

```text
backups/postgres-2026-09-18-010000.sql.gz
```

The filename contains the creation timestamp:

```text
postgres-YYYY-MM-DD-HHMMSS.sql.gz
```

This makes individual backups easy to identify and sort.

---

## Git Exclusion

The backup directory must not be committed to Git.

The repository `.gitignore` should contain:

```gitignore
backups/
```

Verify:

```bash
git check-ignore backups/
```

Database backups may contain sensitive application data and should never be stored in the public repository.

---

## Create a Backup

Ensure the stack is running:

```bash
docker compose ps
```

Then run:

```bash
./scripts/backup.sh
```

Expected output should indicate:

```text
PostgreSQL availability check passed
Backup created successfully
Retention cleanup completed
Backup completed successfully
```

List available backups:

```bash
ls -lht backups/
```

The newest backup should appear first.

---

## Validate the Backup File

Identify the latest backup:

```bash
LATEST_BACKUP="$(ls -t backups/postgres-*.sql.gz | head -1)"
```

Display it:

```bash
echo "$LATEST_BACKUP"
```

Verify that the gzip archive is valid:

```bash
gunzip -t "$LATEST_BACKUP"
```

If the command returns without an error, the gzip archive is structurally valid.

Inspect the beginning of the SQL dump:

```bash
gunzip -c "$LATEST_BACKUP" | head
```

You should see PostgreSQL dump content.

Example:

```text
--
-- PostgreSQL database dump
--
```

A valid gzip archive alone does not prove the database can be restored.

A real restore test is still required.

---

## Restore Verification

Backups should be tested by restoring them into a temporary database.

Do not overwrite the active application database merely to test a backup.

Identify the newest backup:

```bash
LATEST_BACKUP="$(ls -t backups/postgres-*.sql.gz | head -1)"
```

Create a temporary database:

```bash
docker compose exec -T db \
    createdb \
    -U "$POSTGRES_USER" \
    restore_verify
```

Restore the backup:

```bash
gunzip -c "$LATEST_BACKUP" | \
docker compose exec -T db \
    psql \
    -U "$POSTGRES_USER" \
    -d restore_verify
```

If restoration completes without errors, inspect the restored database.

For example:

```bash
docker compose exec db \
    psql \
    -U "$POSTGRES_USER" \
    -d restore_verify \
    -c "\dt"
```

This displays restored tables.

After verification, remove the temporary database:

```bash
docker compose exec -T db \
    dropdb \
    -U "$POSTGRES_USER" \
    restore_verify
```

---

## Restore Test With Verification Data

A stronger backup test includes known data.

Create a temporary test table in the active application database:

```bash
docker compose exec db \
    psql \
    -U "$POSTGRES_USER" \
    -d "$POSTGRES_DB"
```

Inside PostgreSQL:

```sql
CREATE TABLE backup_test (
    id SERIAL PRIMARY KEY,
    message TEXT NOT NULL
);

INSERT INTO backup_test (message)
VALUES ('backup verification record');

SELECT * FROM backup_test;
```

Exit:

```text
\q
```

Create a backup:

```bash
./scripts/backup.sh
```

Identify it:

```bash
LATEST_BACKUP="$(ls -t backups/postgres-*.sql.gz | head -1)"
```

Create the temporary restore database:

```bash
docker compose exec -T db \
    createdb \
    -U "$POSTGRES_USER" \
    restore_verify
```

Restore the backup:

```bash
gunzip -c "$LATEST_BACKUP" | \
docker compose exec -T db \
    psql \
    -U "$POSTGRES_USER" \
    -d restore_verify
```

Verify the known data:

```bash
docker compose exec db \
    psql \
    -U "$POSTGRES_USER" \
    -d restore_verify \
    -c "SELECT * FROM backup_test;"
```

Expected result should include:

```text
backup verification record
```

If the record exists, the backup has successfully passed a real restore test.

Remove the temporary restore database:

```bash
docker compose exec -T db \
    dropdb \
    -U "$POSTGRES_USER" \
    restore_verify
```

---

## Production Restore

A real production restore should be treated as a controlled recovery operation.

Before restoring:

1. identify the correct backup
2. determine why restoration is required
3. stop or restrict application writes
4. preserve the current database if possible
5. confirm that the selected backup is valid
6. document the recovery operation

Do not blindly restore over a working production database.

---

## Example Production Restore Flow

Stop application traffic if necessary:

```bash
docker compose stop app
```

Create a safety backup of the current database:

```bash
./scripts/backup.sh
```

Identify the backup that should be restored:

```bash
ls -lht backups/
```

Set the selected backup:

```bash
RESTORE_FILE="backups/postgres-YYYY-MM-DD-HHMMSS.sql.gz"
```

The exact restoration approach depends on whether the current database should be:

- replaced
- recreated
- restored into a separate database
- inspected before switching application traffic

A safer approach is usually to restore into another database first, validate it, and only then decide whether to switch or replace the production database.

---

## Retention

The local backup script currently removes files older than:

```text
7 days
```

using:

```bash
find "$BACKUP_DIR" \
    -type f \
    -name "postgres-*.sql.gz" \
    -mtime +7 \
    -delete
```

This local retention period is suitable for the demo.

Real production retention should be based on application requirements.

A possible production policy might include:

```text
daily backups      → 7 days
weekly backups     → 4 weeks
monthly backups    → several months
```

Retention requirements vary by business, compliance, storage, and recovery requirements.

---

## Off-Server Storage

Local server backups alone are not sufficient for a real production system.

If the VPS fails completely, local backups may disappear with it.

Production backups should therefore also be copied to durable off-server storage.

Examples include:

- object storage
- another secured server
- managed backup storage
- encrypted cloud storage

The principle is:

```text
production database
        ↓
local backup
        ↓
off-server backup
```

The database and every backup copy should not share a single failure point.

---

## Backup Security

Database backups may contain sensitive information.

Production backups should therefore be:

- access controlled
- excluded from Git
- stored with restrictive permissions
- encrypted where appropriate
- transferred securely
- kept away from public web directories
- protected using separate storage credentials

Backup credentials should follow least-privilege principles.

---

## Monitoring Backups

Backup existence should be monitored.

List backups:

```bash
ls -lht backups/
```

Find the latest backup:

```bash
ls -t backups/postgres-*.sql.gz | head -1
```

Validate the newest archive:

```bash
LATEST_BACKUP="$(ls -t backups/postgres-*.sql.gz | head -1)"
gunzip -t "$LATEST_BACKUP"
```

Important conditions to monitor include:

```text
backup did not run
backup file is empty
backup is too old
archive is corrupted
storage is full
restore test fails
```

A successful command is not enough if no one notices that backups stopped running several days ago.

---

## Disk Usage

Backups consume disk space.

Check filesystem usage:

```bash
df -h
```

Check backup directory size:

```bash
du -sh backups/
```

Check individual backup sizes:

```bash
ls -lh backups/
```

Disk exhaustion can cause:

- backup failures
- PostgreSQL write failures
- Docker failures
- application failures
- logging failures

Backup monitoring should therefore include available disk capacity.

---

## Recovery Principles

The recovery process follows several important principles.

### Preserve Evidence

Before modifying a failed production environment, preserve:

- application logs
- database logs
- Nginx logs
- container status
- current Git commit
- current database state when possible

---

### Do Not Destroy the Current Database Immediately

Even if a database appears damaged or incorrect, take a safety backup when possible before replacing it.

---

### Test Before Switching

Whenever possible:

```text
restore backup
      ↓
temporary database
      ↓
verify schema
      ↓
verify expected data
      ↓
only then use for recovery
```

---

### Backups and Rollbacks Are Different

Application rollback and database restoration solve different problems.

A broken application release may only require:

```text
application rollback
```

A database restore should only be used when the database itself needs recovery.

Do not restore the database simply because application code failed.

For release rollback procedures, see:

```text
docs/rollback.md
```

---

## Backup Validation Checklist

A usable backup process should answer all of the following:

```text
Can I create a backup?
Can I identify when it was created?
Is it compressed?
Is it excluded from Git?
Is it non-empty?
Is the archive valid?
Can PostgreSQL restore it?
Can I verify expected data after restoration?
Can I remove old backups automatically?
Would backups survive complete VPS failure?
```

For the local demo, the first eight items are implemented and testable.

Off-server backup storage is documented as a production requirement rather than being implemented in the local environment.

---

## Summary

The backup architecture is:

```text
PostgreSQL
    │
    │ pg_dump
    ▼
SQL dump
    │
    │ gzip
    ▼
Timestamped backup
    │
    ├────────► Local retention
    │
    ├────────► Restore verification
    │
    └────────► Off-server storage
                 (production)
```

The core rule is simple:

> A backup is not proven by its existence. It is proven by a successful restore.
