ARG BUILD_FROM

# hadolint ignore=DL3006
FROM ${BUILD_FROM}

# Common build arguments
ARG BUILD_ARCH
ARG BUILD_DATE
ARG BUILD_DESCRIPTION
ARG BUILD_NAME
ARG BUILD_REF
ARG BUILD_REPOSITORY
ARG BUILD_VERSION

# TODO: use poetry from apk, after migrating to alpine > 3.14
# In this case no needed:
#   apk: rust, cargo, musl-dev, libffi-dev, libressl-dev, gcc?
#   pip: setuptools-rust, poetry
# FIXME: is openssl needed? We added libressl-dev
# https://github.com/FrederikP/python-poetry-alpine/blob/master/Dockerfile

#         openssl=1.1.1l-r0 \
# hadolint ignore=DL3003
RUN apk add --no-cache --virtual .build-dependencies \
        gcc=10.3.1_git20210424-r2 \
        musl-dev=1.2.2-r3 \
        libffi-dev=3.3-r2 \
        libressl-dev=3.3.3-r0 \
        git=2.32.0-r0 \
        rust=1.52.1-r1 \
        cargo=1.52.1-r1 \
    \
    && mkdir -p /root/build \
    \
    && git clone --single-branch --branch 2.2.6 https://github.com/flyte/mqtt-io /root/build/mqtt_io \
    \
    && python3 -m venv /root/build/venv \
    && /root/build/venv/bin/pip install --no-cache-dir setuptools-rust==0.12.1 \
    && /root/build/venv/bin/pip install --no-cache-dir poetry==1.1.10 \
    \
    && mkdir -p /home/mqtt_io \
    && cd /root/build/mqtt_io   \
    && /root/build/venv/bin/python -m poetry export -o /home/mqtt_io/requirements.txt \
    \
    && cd /home/mqtt_io \
    && python3 -m venv venv \
    && venv/bin/pip install --no-cache-dir -r requirements.txt \
    && venv/bin/pip install --no-cache-dir gpiod==1.5.0 \
    && cp -r /root/build/mqtt_io/mqtt_io mqtt_io \
    \
    && cd /root \
    && pip install --no-cache-dir yq==2.12.2 \
    \
    && apk del --no-cache --purge .build-dependencies \
    && rm -f -r \
        /root/build \
        /root/.cache \
        /root/.cmake \
        /tmp/* \
    \

# Copy root filesystem
COPY rootfs /

#
# Labels
#
LABEL \
    io.hass.name="${BUILD_NAME}" \
    io.hass.description="${BUILD_DESCRIPTION}" \
    io.hass.arch="${BUILD_ARCH}" \
    io.hass.type="addon" \
    io.hass.version=${BUILD_VERSION} \
    maintainer="Pavel Sokolov <pavel@jethome.ru>" \
    io.hass.name="${BUILD_NAME}" \
    io.hass.description="${BUILD_DESCRIPTION}" \
    org.opencontainers.image.vendor="JetHome" \
    org.opencontainers.image.authors="Pavel Sokolov <pavel@jethome.ru>" \
    org.opencontainers.image.licenses="MIT" \
    org.opencontainers.image.url="ghcr.io/jethome-ru/hassio-addon-jethub-mqtt-io/{arch}" \
    org.opencontainers.image.source="https://github.com/${BUILD_REPOSITORY}" \
    org.opencontainers.image.documentation="https://github.com/${BUILD_REPOSITORY}/blob/master/README.md" \
    org.opencontainers.image.created=${BUILD_DATE} \
    org.opencontainers.image.revision=${BUILD_REF} \
    org.opencontainers.image.version=${BUILD_VERSION}
