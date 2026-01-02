#!/bin/bash
# Stop script for Apache Airflow with Synthea

set -e

echo "=================================================="
echo "Stopping Synthea Patient Data Generator"
echo "=================================================="
echo ""

# Check if services are running
if ! docker-compose ps | grep -q "Up"; then
    echo "ℹ️  No services are currently running"
    exit 0
fi

echo "🛑 Stopping services..."
docker-compose stop

echo ""
echo "Do you want to remove containers and networks? (y/N)"
read -r response

if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    echo "🗑️  Removing containers and networks..."
    docker-compose down
    echo "✅ Containers and networks removed"
    
    echo ""
    echo "Do you want to remove volumes (database and data)? (y/N)"
    read -r response2
    
    if [[ "$response2" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        echo "⚠️  This will delete all Airflow metadata and PostgreSQL data!"
        echo "Generated bundles in ./output/ will be preserved."
        echo "Are you sure? (y/N)"
        read -r response3
        
        if [[ "$response3" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            docker-compose down -v
            echo "✅ Volumes removed"
        else
            echo "ℹ️  Volumes preserved"
        fi
    fi
else
    echo "✅ Services stopped (containers preserved)"
fi

echo ""
echo "=================================================="
echo "Shutdown complete!"
echo "=================================================="
echo ""
echo "To start again, run: ./start.sh"
echo "Or manually: docker-compose up -d"
echo ""
