#!/bin/bash
set -e

echo "==================================="
echo "Jenkins Test Environment Startup"
echo "==================================="

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "Error: Docker is not running. Please start Docker first."
    exit 1
fi

# Navigate to project directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

echo "Project directory: $PROJECT_DIR"

# Build and start Jenkins
echo ""
echo "Building Jenkins Docker image..."
docker-compose build

echo ""
echo "Starting Jenkins container..."
docker-compose up -d

echo ""
echo "Waiting for Jenkins to start..."
JENKINS_URL="http://localhost:8080"
MAX_ATTEMPTS=60
ATTEMPT=0

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    if curl -s -o /dev/null -w "%{http_code}" "$JENKINS_URL/login" | grep -q "200"; then
        echo "Jenkins is ready!"
        break
    fi
    ATTEMPT=$((ATTEMPT + 1))
    echo "Waiting for Jenkins... (attempt $ATTEMPT/$MAX_ATTEMPTS)"
    sleep 2
done

if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
    echo "Error: Jenkins failed to start within expected time"
    docker-compose logs
    exit 1
fi

echo ""
echo "==================================="
echo "Jenkins is ready!"
echo "==================================="
echo ""
echo "Access Jenkins at: $JENKINS_URL"
echo "Username: admin"
echo "Password: admin"
echo ""

# Show ngrok tunnel URL if available
NGROK_URL=$(curl -s http://localhost:4040/api/tunnels 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['tunnels'][0]['public_url'])" 2>/dev/null)
if [ -n "$NGROK_URL" ]; then
    echo "ngrok tunnel: $NGROK_URL"
    echo "GitHub webhook URL: $NGROK_URL/github-webhook/"
    echo "Generic webhook URL: $NGROK_URL/generic-webhook-trigger/invoke?token=ios-ui-tests-trigger"
    echo "ngrok dashboard: http://localhost:4040"
else
    echo "ngrok: not running (set NGROK_AUTHTOKEN in .env to enable)"
fi
echo ""
echo "To stop: docker-compose down"
echo "To view logs: docker-compose logs -f"
