FROM python:3.11-slim-bullseye

# Install system dependencies
RUN apt-get update && apt-get install -y \
    # Basic tools
    curl wget git sudo \
    # Audio support
    alsa-utils pulseaudio \
    # Network tools
    net-tools iproute2 iptables \
    # Build tools
    build-essential pkg-config \
    # Process management
    supervisor systemd \
    # Web server
    nginx \
    # Node.js for frontend
    nodejs npm \
    # DBus for system integration
    dbus libdbus-1-dev \
    # For Spotifyd
    libasound2-dev libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Rust for building Spotify tools
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

# Create app directory
WORKDIR /app

# Copy backend requirements and install
COPY backend/requirements.txt /app/backend/
RUN pip install --no-cache-dir -r backend/requirements.txt

# Copy frontend and build
COPY frontend/package.json /app/frontend/
WORKDIR /app/frontend
RUN npm install --production
COPY frontend/ /app/frontend/
RUN npm install && npm run build || true

# Copy all application files
WORKDIR /app
COPY . /app/

# Install Spotifyd
RUN cd /tmp && \
    wget https://github.com/Spotifyd/spotifyd/releases/download/v0.3.5/spotifyd-linux-default-full.tar.gz && \
    tar xzf spotifyd-linux-default-full.tar.gz && \
    mv spotifyd /usr/local/bin/ && \
    chmod +x /usr/local/bin/spotifyd

# Install spotify-tui
RUN cargo install spotify-tui || true

# Setup nginx
COPY docker/nginx.conf /etc/nginx/sites-available/default

# Setup supervisor
COPY docker/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Create necessary directories
RUN mkdir -p /app/data /app/logs /app/config /app/scripts

# Make scripts executable
RUN chmod +x /app/scripts/*.sh || true

# Expose ports
EXPOSE 80 443

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
    CMD curl -f http://localhost/health || exit 1

# Start supervisor
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]