#!/bin/bash

# TeslaMate Development Setup Script
# This script helps set up the development environment

set -e

echo "🚀 Setting up TeslaMate for development..."

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker first."
    exit 1
fi

# Build and start the development environment
echo "📦 Building development containers..."
docker-compose -f docker-compose.dev.yaml build

echo "🎯 Starting development services..."
docker-compose -f docker-compose.dev.yaml up -d

# Wait for services to be ready
echo "⏳ Waiting for services to start..."
sleep 10

# Check if TeslaMate is running
if docker-compose -f docker-compose.dev.yaml ps teslamate | grep -q "Up"; then
    echo "✅ TeslaMate development server is running!"
    echo ""
    echo "🌐 Access TeslaMate at: http://localhost:4000"
    echo "📊 Access Grafana at: http://localhost:3000"
    echo "🗄️  PostgreSQL at: localhost:5432"
    echo ""
    echo "📝 To view logs: docker-compose -f docker-compose.dev.yaml logs -f teslamate"
    echo "🛑 To stop: docker-compose -f docker-compose.dev.yaml down"
    echo ""
    echo "🔥 Hot reloading is enabled - changes will be reflected automatically!"
else
    echo "❌ TeslaMate failed to start. Check the logs:"
    echo "docker-compose -f docker-compose.dev.yaml logs teslamate"
    exit 1
fi
