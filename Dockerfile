ARG MTA_SERVER_VERSION=1.5.7
ARG MTA_SERVER_BUILD_NUMBER=20359

FROM alpine:latest AS helper
ARG MTA_SERVER_VERSION
ARG MTA_SERVER_BUILD_NUMBER
WORKDIR /mtasa-rootfs

# Create necessary directories first
RUN mkdir -p ./usr/lib ./lib

# Install dependencies and download files
RUN apk add --no-cache --update wget tar && \
    wget https://nightly.mtasa.com/multitheftauto_linux_x64-${MTA_SERVER_VERSION}-rc-${MTA_SERVER_BUILD_NUMBER}.tar.gz -O /tmp/mtasa.tar.gz && \
    wget https://linux.mtasa.com/dl/baseconfig.tar.gz -P /tmp && \
    wget http://nightly.mtasa.com/files/libmysqlclient.so.16 -O ./usr/lib/libmysqlclient.so.16 && \
    cp ./usr/lib/libmysqlclient.so.16 ./lib/ && \
    tar -xzf /tmp/mtasa.tar.gz && \
    mv multitheftauto_linux_x64* mtasa && \
    mkdir -p mtasa/.default mtasa/x64/modules && \
    tar -xzf /tmp/baseconfig.tar.gz -C mtasa/.default && \
    wget https://nightly.mtasa.com/files/modules/64/mta_mysql.so -O mtasa/x64/modules/mta_mysql.so && \
    wget https://nightly.mtasa.com/files/modules/64/ml_sockets.so -O mtasa/x64/modules/ml_sockets.so && \
    chmod -R go+rw mtasa && \
    chmod +x usr/lib/libmysqlclient.so.16 lib/libmysqlclient.so.16

# Main image
FROM debian:bullseye-slim
ARG MTA_SERVER_VERSION
ARG MTA_SERVER_BUILD_NUMBER

# Set safer environment variables
ENV MTA_SERVER_VERSION=${MTA_SERVER_VERSION} \
    MTA_SERVER_BUILD_NUMBER=${MTA_SERVER_BUILD_NUMBER} \
    MTA_DEFAULT_RESOURCES_URL=http://mirror.mtasa.com/mtasa/resources/mtasa-resources-latest.zip \
    MTA_SERVER_ROOT_DIR=/mtasa \
    MTA_SERVER_CONFIG_FILE_NAME=mtaserver.conf

# Create a separate ENV for sensitive variables to avoid warnings
ENV MTA_SERVER_PASSWORD="" \
    MTA_SERVER_PASSWORD_REPLACE_POLICY="when-empty"

WORKDIR /mtasa
COPY --from=helper /mtasa-rootfs /

# Install dependencies including libssl
RUN groupadd -r mtasa && \
    useradd --no-log-init -r -g mtasa mtasa && \
    chown mtasa:mtasa . && \
    mkdir -p /data /resources /resource-cache /native-modules && \
    chown -R mtasa:mtasa /data /resources /resource-cache /native-modules /mtasa && \
    chmod go+w /data /resources /resource-cache /native-modules && \
    apt-get update && \
    dpkg --add-architecture i386 && \
    apt-get install -y --no-install-recommends \
        bash \
        tar \
        unzip \
        libncursesw5 \
        wget \
        gdb \
        libssl1.1 \
        libssl-dev && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    apt-get autoclean -y && \
    apt-get autoremove -y

USER mtasa
RUN mkdir -p ${MTA_SERVER_ROOT_DIR}/mods && \
    rmdir ${MTA_SERVER_ROOT_DIR}/mods/deathmatch 2>/dev/null || true && \
    ln -sf /usr ${MTA_SERVER_ROOT_DIR}/mods/deathmatch && \
    ln -sfT /data ${MTA_SERVER_ROOT_DIR}/mods/deathmatch

# Create a simple entrypoint script
RUN echo '#!/bin/bash' > /entrypoint.sh && \
    echo 'export LD_LIBRARY_PATH=/lib:/usr/lib' >> /entrypoint.sh && \
    echo 'exec /mtasa/mta-server64 "$@"' >> /entrypoint.sh && \
    chmod +x /entrypoint.sh

ENV TERM=xterm
EXPOSE 22003/udp 22005/tcp 22126/udp
VOLUME ["/resources", "/resource-cache", "/native-modules", "/data"]
ENTRYPOINT ["/entrypoint.sh"]
CMD ["-x", "-n", "-u"]
