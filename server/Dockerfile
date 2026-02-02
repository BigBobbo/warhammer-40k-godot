# Simple Node.js WebSocket relay server
FROM node:20-alpine

WORKDIR /app

# Copy package files
COPY package.json ./

# Install dependencies
RUN npm install --production

# Copy server code
COPY relay-server.js ./

# Expose WebSocket port
EXPOSE 9080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:9081/health || exit 1

CMD ["node", "relay-server.js"]
