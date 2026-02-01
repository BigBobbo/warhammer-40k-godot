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

# Copy server files (these are in the same directory as Dockerfile)
COPY GameCodeManager.gd /app/server/
COPY server_main.gd /app/server/
COPY server.tscn /app/server/

# Create minimal project.godot for server
RUN echo '[gd_resource type="Environment" format=3]' > /app/project.godot && \
    echo 'config_version=5' >> /app/project.godot && \
    echo '[application]' >> /app/project.godot && \
    echo 'config/name="W40K Server"' >> /app/project.godot && \
    echo 'run/main_scene="res://server/server.tscn"' >> /app/project.godot

# Expose WebSocket port
EXPOSE 9080

# Run the server headless
CMD ["godot", "--headless", "--path", "/app"]
