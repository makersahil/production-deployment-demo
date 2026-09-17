#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

echo "==> Production Deployment Demo"

# --------------------------------------------------
# 1. Validate required files
# --------------------------------------------------

echo "==> Validating deployment environment"

required_files=(
    ".env"
    "docker-compose.yml"
    "application/Dockerfile"
    "application/manage.py"
    "nginx/default.conf"
)

for file in "${required_files[@]}"; do
    if [[ ! -f "$file" ]]; then
        echo "ERROR: Required file missing: $file"
        exit 1
    fi
done

set -a
source .env
set +a

command -v docker >/dev/null 2>&1 || {
    echo "ERROR: Docker is not installed"
    exit 1
}

docker info >/dev/null 2>&1 || {
    echo "ERROR: Docker daemon is unavailable"
    exit 1
}

docker compose version >/dev/null 2>&1 || {
    echo "ERROR: Docker Compose is unavailable"
    exit 1
}

echo "Environment validation passed"


# --------------------------------------------------
# 2. Obtain latest code
# --------------------------------------------------

echo "==> Checking repository"

if [[ -d ".git" ]]; then
    CURRENT_BRANCH="$(git branch --show-current)"

    echo "Current branch: $CURRENT_BRANCH"

    if ! git diff --quiet || ! git diff --cached --quiet; then
        echo "ERROR: Working tree has uncommitted changes"
        echo "Commit or stash them before deployment."
        exit 1
    fi

    echo "Fetching latest repository state"
    git fetch origin "$CURRENT_BRANCH"

    git pull --ff-only origin "$CURRENT_BRANCH"
fi


# --------------------------------------------------
# 3. Validate Compose configuration
# --------------------------------------------------

echo "==> Validating Docker Compose configuration"

docker compose config >/dev/null

echo "Compose configuration valid"


# --------------------------------------------------
# 4. Build application image
# --------------------------------------------------

echo "==> Building application image"

docker compose build app


# --------------------------------------------------
# 5. Start dependencies first
# --------------------------------------------------

echo "==> Starting PostgreSQL and Redis"

docker compose up -d db redis


# --------------------------------------------------
# 6. Wait for PostgreSQL
# --------------------------------------------------

echo "==> Waiting for PostgreSQL"

until docker compose exec -T db pg_isready \
    -U "${POSTGRES_USER:-appuser}" \
    -d "${POSTGRES_DB:-appdb}" >/dev/null 2>&1
do
    echo "PostgreSQL not ready yet..."
    sleep 2
done

echo "PostgreSQL ready"


# --------------------------------------------------
# 7. Verify Redis
# --------------------------------------------------

echo "==> Checking Redis"

until docker compose exec -T redis redis-cli ping \
    | grep -q "PONG"
do
    echo "Redis not ready yet..."
    sleep 2
done

echo "Redis ready"


# --------------------------------------------------
# 8. Run migrations
# --------------------------------------------------

echo "==> Running Django migrations"

docker compose run --rm app \
    python manage.py migrate --noinput


# --------------------------------------------------
# 9. Start application and Nginx
# --------------------------------------------------

echo "==> Starting application stack"

docker compose up -d app nginx


# --------------------------------------------------
# 10. Show status
# --------------------------------------------------

echo "==> Container status"

docker compose ps


# --------------------------------------------------
# 11. Health check
# --------------------------------------------------

echo "==> Waiting for application"

attempt=1
max_attempts=15

until ./scripts/healthcheck.sh >/dev/null 2>&1
do
    if (( attempt >= max_attempts )); then
        echo "ERROR: Application failed health check"

        echo
        echo "Application logs:"
        docker compose logs --tail=50 app || true

        echo
        echo "Nginx logs:"
        docker compose logs --tail=50 nginx || true

        exit 1
    fi

    echo "Application not ready yet. Attempt $attempt/$max_attempts"
    sleep 2

    ((attempt++))
done

./scripts/healthcheck.sh

echo
echo "Deployment completed successfully"
