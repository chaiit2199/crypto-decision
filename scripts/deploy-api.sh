#!/usr/bin/env bash
set -euo pipefail
# Run in the VPS deploy directory. Secrets remain in .env; never source them as shell code.
export IMAGE_TAG="${1:?Pass the immutable image tag}"
test -f .env
exec 9>.deploy.lock
flock -n 9 || { echo 'Another deployment is running'; exit 1; }
docker compose --env-file .env config --quiet
docker compose --env-file .env pull api
docker compose --env-file .env up -d --wait --wait-timeout 120 db
docker compose --env-file .env run --rm --no-deps -T api eval 'CryptoDecisionLab.Release.migrate()' < /dev/null
docker compose --env-file .env up -d --no-deps --force-recreate --wait --wait-timeout 180 api
container_id="$(docker compose --env-file .env ps -q api)"
test "$(docker inspect --format '{{.Config.Image}}' "$container_id")" = "$IMAGE_TAG"
printf 'IMAGE_TAG=%s\n' "$IMAGE_TAG" > .image.env.tmp
mv .image.env.tmp .image.env
echo "API healthy: $IMAGE_TAG"
