# Multi-stage build for optimized image
FROM node:18-alpine AS builder

WORKDIR /app

# Copy package files
COPY package*.json ./
COPY client/package*.json ./client/

# Install dependencies
RUN npm ci --only=production
RUN cd client && npm ci

# Copy source code
COPY . .

# Build React app
RUN cd client && npm run build

# Production stage
FROM node:18-alpine

WORKDIR /app

# Install dumb-init for proper signal handling
RUN apk add --no-cache dumb-init

# Create non-root user
RUN addgroup -g 1001 -S spotify && \
    adduser -u 1001 -S spotify -G spotify

# Copy from builder
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/client/build ./client/build
COPY --from=builder /app/server.js ./
COPY --from=builder /app/package.json ./

# Create config directory
RUN mkdir -p /app/config && \
    chown -R spotify:spotify /app

# Switch to non-root user
USER spotify

# Environment variables
ENV NODE_ENV=production \
    PORT=5000 \
    SPOTIFY_CONFIG_DIR=/app/config

EXPOSE 5000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD node -e "require('http').get('http://localhost:5000/api/health', (r) => {r.statusCode === 200 ? process.exit(0) : process.exit(1)})"

# Use dumb-init to handle signals properly
ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "server.js"]