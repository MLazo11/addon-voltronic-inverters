ARG BUILD_FROM
FROM ${BUILD_FROM}

# Install dependencies
RUN apt-get update && apt-get install -y \
        git \
        build-essential \
        cmake \
        jq \
        mosquitto-clients \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Set the working directory
WORKDIR /opt

# Define the desired commit hash
ARG GIT_COMMIT=a01e305846c697d985847405909e91ba81289a49

# Clone the repository with Sparse Checkout and check out the specific commit
RUN git clone --filter=blob:none --no-checkout https://github.com/catalinbordan/docker-voltronic-homeassistant.git repo && \
    cd repo && \
    git fetch origin $GIT_COMMIT && \
    git checkout $GIT_COMMIT && \
    git sparse-checkout init --cone && \
    git sparse-checkout set sources config

# Create the destination directory and copy necessary files
RUN mkdir -p /etc/inverter && \
    cp -r repo/sources/* /opt/ && \
    cp -r repo/config/* /etc/inverter/

# Fix: serialize access to the serial port so mqtt-push.sh and mqtt-subscriber.sh
# don't call inverter_poller at the same time (race condition, issue #5:
# https://github.com/GitGab19/addon-voltronic-inverters/issues/5)
RUN sed -i 's#timeout 10 /opt/inverter-cli/bin/inverter_poller -1#flock -w 15 /tmp/inverter_poller.lock timeout 10 /opt/inverter-cli/bin/inverter_poller -1#' /opt/inverter-mqtt/mqtt-push.sh
RUN sed -i 's#/opt/inverter-cli/bin/inverter_poller -r $rawcmd#flock -w 15 /tmp/inverter_poller.lock /opt/inverter-cli/bin/inverter_poller -r $rawcmd#' /opt/inverter-mqtt/mqtt-subscriber.sh
RUN rm -rf repo

# Remove the cloned repository to reduce image size

COPY run.sh /run.sh
RUN chmod a+x /run.sh

RUN sed -i '1i#include <string>' /opt/inverter-cli/inverter.h

# Fix: avoid segfault when the inverter reply is truncated/incomplete before the
# 5s read timeout (endbuf stays NULL and pointer arithmetic on it corrupts buf[] index).
# Also force explicit raw serial mode instead of relying on inherited termios state.
RUN sed -i 's#settings\.c_oflag &= ~OPOST;#settings.c_oflag \&= ~OPOST; settings.c_lflag \&= ~(ICANON | ECHO | ECHOE | ISIG); settings.c_iflag \&= ~(ICRNL | INLCR | IGNCR | IXON | IXOFF);#' /opt/inverter-cli/inverter.cpp
RUN sed -i 's#int replysize = endbuf - startbuf + 1;#if (endbuf == NULL) { lprintf("DEBUG:  %s: incomplete reply, no CR terminator before timeout (%d bytes received)", cmd, i); return false; } int replysize = endbuf - startbuf + 1;#' /opt/inverter-cli/inverter.cpp

# Build the inverter CLI
RUN cd /opt/inverter-cli && \
    mkdir bin && \
    cmake . && \
    make && \
    mv inverter_poller bin/

# Configure healthcheck
HEALTHCHECK \
    --interval=30s \
    --timeout=10s \
    --start-period=1m \
    --retries=3 \
  CMD /opt/healthcheck

# Set the startup command
CMD [ "/run.sh" ]
