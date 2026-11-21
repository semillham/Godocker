FROM rockylinux/rockylinux:9-minimal

USER root
RUN microdnf update -y \
    && microdnf install -y --setopt=install_weak_deps=0 \
        epel-release \
    && microdnf install -y --setopt=install_weak_deps=0 \
        wget \
        unzip \
        ca-certificates \
        fontconfig \
        mesa-dri-drivers \
        mesa-libGL \
        libX11 \
        libXcursor \
        libXrandr \
        libXi \
        libXinerama \
        libXext \
        libXrender \
        alsa-lib \
        xorg-x11-server-Xvfb \
        x11vnc \
        novnc \
        python3-websockify \
        fluxbox \
    && microdnf clean all

# Download and install Godot (adjust version/URL as needed)

ARG GODOT_VERSION=4.3-stable
RUN wget -q "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip" -O /tmp/godot.zip \
    && unzip -q /tmp/godot.zip -d /opt/godot \
    && mv /opt/godot/Godot_v${GODOT_VERSION}_linux.x86_64 /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot \
    && rm -rf /tmp/godot.zip /opt/godot \
    && printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -e' \
    'export DISPLAY=:1' \
    'Xvfb :1 -screen 0 1280x720x24 &' \
    'sleep 1' \
    'fluxbox &' \
    'x11vnc -display :1 -nopw -forever -shared -rfbport 5900 &' \
    'websockify --web /usr/share/novnc/ 4510 localhost:5900 &' \
    'exec godot' \
    > /usr/local/bin/start-godot.sh \
    && chmod +x /usr/local/bin/start-godot.sh

RUN mkdir -p /home/godot && chown -R 1000:1000 /home/godot

EXPOSE 4510
USER 1000
ENV HOME=/home/godot
WORKDIR /home/godot

CMD ["/usr/local/bin/start-godot.sh"]