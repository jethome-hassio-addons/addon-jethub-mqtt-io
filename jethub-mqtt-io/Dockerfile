# Runtime Dockerfile for gpio2mqtt addon
# Downloads pre-built binary from GHCR via ORAS

ARG BUILD_FROM=debian:bookworm-slim

# Stage 1: Download binary from GHCR
FROM debian:bookworm-slim AS downloader

ARG BUILD_ARCH=aarch64
ARG BINARY_VERSION=dev

# Map Home Assistant arch to binary arch
# aarch64 -> arm64, amd64 -> amd64
RUN case "${BUILD_ARCH}" in \
        aarch64) ARCH="arm64" ;; \
        amd64) ARCH="amd64" ;; \
        *) echo "Unsupported architecture: ${BUILD_ARCH}" && exit 1 ;; \
    esac && \
    echo "ARCH=${ARCH}" > /tmp/arch.env

# Install oras
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/* \
    && curl -LO https://github.com/oras-project/oras/releases/download/v1.2.2/oras_1.2.2_linux_amd64.tar.gz \
    && tar -xzf oras_1.2.2_linux_amd64.tar.gz -C /usr/local/bin oras \
    && rm -f oras_1.2.2_linux_amd64.tar.gz

# Download binary from GHCR
RUN . /tmp/arch.env && \
    mkdir -p /download && \
    cd /download && \
    oras pull "ghcr.io/jethome-iot/gpio2mqtt-bin:${BINARY_VERSION}-${ARCH}" && \
    mv gpio2mqtt-linux-${ARCH} gpio2mqtt && \
    chmod +x gpio2mqtt

# Stage 2: Final image
# hadolint ignore=DL3006
FROM ${BUILD_FROM}

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgpiod2 \
    ca-certificates \
    curl \
    jq \
    python3 \
    python3-yaml \
    && rm -rf /var/lib/apt/lists/*

# Copy binary from downloader stage
COPY --from=downloader /download/gpio2mqtt /usr/local/bin/gpio2mqtt

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
ARG BUILD_DESCRIPTION="Expose JetHome JetHub peripheral (relays, inputs, etc..) via mqtt-io"
ARG BUILD_NAME="JetHome JetHub mqtt-io peripheral exposer"
ARG BUILD_REF
ARG BUILD_REPOSITORY
ARG BUILD_VERSION

LABEL \
    io.hass.name="${BUILD_NAME}" \
    io.hass.description="${BUILD_DESCRIPTION}" \
    io.hass.arch="${BUILD_ARCH}" \
    io.hass.type="addon" \
    io.hass.version=${BUILD_VERSION} \
    maintainer="JetHome Team <dev@jethome.com>" \
    org.opencontainers.image.title="${BUILD_NAME}" \
    org.opencontainers.image.description="${BUILD_DESCRIPTION}" \
    org.opencontainers.image.vendor="JetHome" \
    org.opencontainers.image.authors="JetHome Team <dev@jethome.com>" \
    org.opencontainers.image.licenses="MIT" \
    org.opencontainers.image.url="https://jethome.ru" \
    org.opencontainers.image.source="https://github.com/${BUILD_REPOSITORY}" \
    org.opencontainers.image.documentation="https://github.com/${BUILD_REPOSITORY}/blob/main/README.md" \
    org.opencontainers.image.created=${BUILD_DATE} \
    org.opencontainers.image.revision=${BUILD_REF} \
    org.opencontainers.image.version=${BUILD_VERSION}
