#!/usr/bin/env bash
set -euo pipefail
set -a; source .env; set +a

echo "== DNS for ${SERVER_DOMAIN} =="
getent hosts "${SERVER_DOMAIN}" || { echo "DNS not resolving yet"; exit 1; }

echo "== TCP 25565 =="
nc -vz -w 5 "${SERVER_DOMAIN}" 25565

echo "== Containers =="
docker compose ps
