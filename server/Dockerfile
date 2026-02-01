# Dockerfile for Warhammer 40K Dedicated Server
# Uses Godot headless for WebSocket multiplayer

FROM ubuntu:22.04

# Install dependencies
RUN apt-get update && apt-get install -y \
    wget \
    unzip \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Set Godot version
ARG GODOT_VERSION=4.4.1

# Download Godot headless server binary
RUN wget -q https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip \
    && unzip Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip \
    && mv Godot_v${GODOT_VERSION}-stable_linux.x86_64 /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot \
    && rm Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip

# Create app directory
WORKDIR /app

# Copy server files
COPY server/ /app/server/

# Copy only necessary autoloads (minimal dependencies)
# Note: In production, you'd export the server project properly
COPY project.godot /app/
COPY autoloads/FeatureFlags.gd /app/autoloads/
COPY autoloads/DebugLogger.gd /app/autoloads/
COPY autoloads/TestModeHandler.gd /app/autoloads/

# Expose WebSocket port
EXPOSE 9080

# Health check endpoint (Fly.io uses this)
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:9080/health || exit 1

# Run the server
# Note: --headless is crucial for server-only operation
CMD ["godot", "--headless", "--main-pack", "/app", "--main-scene", "res://server/server.tscn"]
