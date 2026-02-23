#!/bin/bash
set -e

PI_HOST="drewpost@192.168.1.56"
PI_DIR="/home/drewpost/teslamate-ios"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> Syncing source to Pi..."
rsync -az --delete \
  --exclude '_build' \
  --exclude 'deps' \
  --exclude '.git' \
  --exclude 'ios' \
  --exclude 'node_modules' \
  --exclude 'assets/node_modules' \
  --exclude '.elixir_ls' \
  --exclude 'DerivedData' \
  "$REPO_DIR/" "$PI_HOST:$PI_DIR/"

echo "==> Building Docker image on Pi (this may take several minutes)..."
ssh "$PI_HOST" "cd $PI_DIR && docker build -t teslamate-ios:latest ."

echo "==> Updating docker-compose and restarting..."
ssh "$PI_HOST" "cd /home/drewpost/teslamate && docker compose up -d teslamate"

echo "==> Waiting for service to start..."
sleep 10

echo "==> Testing health endpoint..."
ssh "$PI_HOST" "curl -sf http://localhost:4000/api/v1/health || echo 'Health check failed (API may not be enabled yet)'"

echo ""
echo "Done! Custom TeslaMate image built and deployed."
echo "Remember to add ENABLE_API=true and API_AUTH_TOKEN to your docker-compose.yml"
