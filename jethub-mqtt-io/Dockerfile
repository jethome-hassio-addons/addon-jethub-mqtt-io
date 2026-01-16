# Runtime-only Dockerfile for gpio2mqtt addon
# Uses pre-built binary from CI artifacts
#
# Build requires passing the binary via build context:
#   docker buildx build --build-context binary=./artifacts \
#     --build-arg BINARY_NAME=gpio2mqtt-linux-arm64 \
#     -f Dockerfile .

ARG BUILD_FROM=debian:bookworm-slim

# hadolint ignore=DL3006
FROM ${BUILD_FROM}

# Arguments for binary selection
ARG BINARY_NAME=gpio2mqtt

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgpiod2 \
    ca-certificates \
    curl \
    jq \
    python3 \
    python3-yaml \
    && rm -rf /var/lib/apt/lists/*

# Copy pre-built binary from build context
COPY --from=binary ${BINARY_NAME} /usr/local/bin/gpio2mqtt
RUN chmod +x /usr/local/bin/gpio2mqtt

# Copy root filesystem (scripts, configs)
COPY rootfs /

# Make scripts executable
RUN chmod +x /usr/local/bin/*.sh

# Set working directory
WORKDIR /data

# Default command
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# Labels
ARG BUILD_ARCH
ARG BUILD_DATE
ARG BUILD_DESCRIPTION="GPIO to MQTT bridge with Home Assistant autodiscovery"
ARG BUILD_NAME="JetHub GPIO2MQTT"
ARG BUILD_REF
ARG BUILD_REPOSITORY
ARG BUILD_VERSION

LABEL \
    io.hass.name="${BUILD_NAME}" \
    io.hass.description="${BUILD_DESCRIPTION}" \
    io.hass.arch="${BUILD_ARCH}" \
    io.hass.type="addon" \
    io.hass.version=${BUILD_VERSION} \
    maintainer="JetHome <info@jethome.ru>" \
    org.opencontainers.image.title="${BUILD_NAME}" \
    org.opencontainers.image.description="${BUILD_DESCRIPTION}" \
    org.opencontainers.image.vendor="JetHome" \
    org.opencontainers.image.authors="JetHome <info@jethome.ru>" \
    org.opencontainers.image.licenses="MIT" \
    org.opencontainers.image.url="https://jethome.ru" \
    org.opencontainers.image.source="https://github.com/${BUILD_REPOSITORY}" \
    org.opencontainers.image.documentation="https://github.com/${BUILD_REPOSITORY}/blob/main/README.md" \
    org.opencontainers.image.created=${BUILD_DATE} \
    org.opencontainers.image.revision=${BUILD_REF} \
    org.opencontainers.image.version=${BUILD_VERSION}
