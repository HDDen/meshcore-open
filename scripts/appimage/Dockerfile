ARG BASE_IMAGE=ubuntu:24.04@sha256:fe81560990fae86dc4743202b2cb4d3df98d0bcf949173cecef15ce1127ef852
FROM ${BASE_IMAGE} AS runtime-test
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    xvfb xauth x11-utils x11-apps xdotool imagemagick dbus-x11 binutils libgl1 libegl1 libgles2 \
    libgl1-mesa-dri fonts-dejavu-core \
  && rm -rf /var/lib/apt/lists/*
