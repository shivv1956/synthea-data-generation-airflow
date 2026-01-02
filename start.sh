#!/bin/bash
# Quick start script for Apache Airflow with Synthea

set -e

echo "=================================================="
echo "Synthea Patient Data Generator with Apache Airflow"
echo "=================================================="
echo ""

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Error: Docker is not running. Please start Docker first."
    exit 1
fi

# Check if Docker Compose is available
if ! command -v docker-compose &> /dev/null; then
    echo "❌ Error: docker-compose is not installed."
    exit 1
fi

echo "✅ Docker is running"
echo ""

# Create required directories
echo "📁 Creating required directories..."
mkdir -p logs dags plugins output/bundles
echo "✅ Directories created"
echo ""

# Build and start services
echo "🚀 Building and starting services..."
echo "This may take several minutes on first run..."
echo ""

docker-compose up --build -d

echo ""
echo "⏳ Waiting for services to be healthy..."
sleep 10

# Check service status
echo ""
echo "📊 Service Status:"
docker-compose ps

echo ""
echo "=================================================="
echo "🎉 Setup Complete!"
echo "=================================================="
echo ""
echo "Access Airflow UI at: http://localhost:8080"
echo "  Username: admin"
echo "  Password: admin"
echo ""
echo "View logs with:"
echo "  docker-compose logs -f airflow-scheduler"
echo ""
echo "Generated bundles will be stored in:"
echo "  ./output/bundles/YYYY-MM-DD/"
echo ""
echo "To stop services:"
echo "  docker-compose down"
echo ""
echo "=================================================="
