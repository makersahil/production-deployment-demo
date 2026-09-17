# PostgreSQL Backup and Restore

## Overview

The production deployment demo uses PostgreSQL as its persistent
application database.

Database backups are created using `pg_dump`, compressed with gzip,
and stored outside the PostgreSQL container.

The backup process covers:

1. Create
2. Store
3. Retain
4. Restore
5. Verify


## Creating a Backup

Run:

```bash
./scripts/backup.sh
