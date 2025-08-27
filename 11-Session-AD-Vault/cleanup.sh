#!/bin/bash

# Simple cleanup script

echo "Cleaning up demo..."

# Stop any running demo processes
pkill -f demo.sh 2>/dev/null

# Stop and remove Docker containers
docker-compose down -v 2>/dev/null

# Remove log files
rm -f *.log

echo "✅ Cleanup complete"