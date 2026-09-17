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

echo "==> Checking PostgreSQL"

docker compose exec -T db \
    pg_isready \
    -U "$POSTGRES_USER" \
    -d "$POSTGRES_DB" >/dev/null

echo "PostgreSQL is ready"

echo "==> Creating backup"

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

echo "Backup created:"
echo "$BACKUP_FILE"

ls -lh "$BACKUP_FILE"

echo "==> Removing backups older than 7 days"

find "$BACKUP_DIR" \
    -type f \
    -name "postgres-*.sql.gz" \
    -mtime +7 \
    -delete

echo "Backup completed successfully"
