#!/bin/bash

# Spotify Kids Manager - Flask Startup Script
# Ensures Flask starts correctly with proper error handling

echo "Starting Flask application..."

# Ensure directories exist
mkdir -p /app/logs /app/data /app/config

# Set environment if not set
export FLASK_APP=${FLASK_APP:-app.py}
export FLASK_ENV=${FLASK_ENV:-production}
export PYTHONUNBUFFERED=1

# Change to backend directory
cd /app/backend

# Check if Python and dependencies are available
if ! python3 --version > /dev/null 2>&1; then
    echo "ERROR: Python not found!"
    exit 1
fi

# Check critical imports
echo "Checking Python dependencies..."
python3 -c "import flask" 2>/dev/null || {
    echo "ERROR: Flask not installed. Installing dependencies..."
    pip install -r requirements.txt
}

# Start Flask with proper error handling
echo "Starting Flask on port 5000..."
python3 app.py 2>&1 | tee -a /app/logs/flask_startup.log

# If Flask exits, keep container alive for debugging
if [ $? -ne 0 ]; then
    echo "Flask failed to start. Check logs at /app/logs/"
    echo "Keeping container alive for debugging..."
    tail -f /dev/null
fi