#!/bin/bash

# Start the FastAPI server with Bonjour discovery for UWB Navigator

echo "🚀 Starting UWB Navigator FastAPI Server..."
echo "📡 This server will automatically discover iOS devices on your network"
echo ""

# Check if Python is installed
if ! command -v python3 &> /dev/null; then
    echo "❌ Python 3 is not installed. Please install Python 3.8 or higher."
    exit 1
fi

# Check if virtual environment exists
if [ ! -d "venv" ]; then
    echo "📦 Creating virtual environment..."
    python3 -m venv venv
fi

# Activate virtual environment
echo "🔧 Activating virtual environment..."
source venv/bin/activate

# Install dependencies
echo "📚 Installing dependencies..."
pip install -r requirements.txt

# Start the server
echo ""
echo "✅ Starting FastAPI server on http://localhost:8000"
echo "📱 The server will automatically discover iOS devices running the UWB Navigator app"
echo "🌐 Open http://localhost:8000 in your browser to see the API documentation"
echo ""
echo "Press Ctrl+C to stop the server"
echo "----------------------------------------"
echo ""

# Run the server
python fastapi_server.py