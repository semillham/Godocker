FROM rockylinux/rockylinux:9-minimal

USER root
RUN microdnf update -y \
    && microdnf install -y --setopt=install_weak_deps=0 \
        epel-release \
    && microdnf install -y --setopt=install_weak_deps=0 \
        bash \
        git \
        wget \
        unzip \
        ca-certificates \
        fontconfig \
        mesa-dri-drivers \
        mesa-libGL \
        mesa-vulkan-drivers \
        vulkan-loader \
        vulkan-tools \
        libX11 \
        libXcursor \
        libXrandr \
        libXi \
        libXinerama \
        libXext \
        libXrender \
        libXfixes \
        libXdamage \
        alsa-lib \
        xorg-x11-server-Xvfb \
        x11vnc \
        novnc \
        python3-websockify \
        fluxbox \
        dotnet-sdk-8.0 \
    && microdnf clean all

# Download and install Godot (.NET build includes both C# and GDScript)
ARG GODOT_VERSION=4.7.2-stable
RUN set -euo pipefail \
    && DIR_NAME="Godot_v${GODOT_VERSION}_mono_linux.x86_64" \
    && ZIP_NAME="${DIR_NAME}.zip" \
    && wget -q "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/${ZIP_NAME}" -O /tmp/godot.zip \
    && unzip -q /tmp/godot.zip -d /opt/godot \
    && mv "/opt/godot/${DIR_NAME}/${DIR_NAME}" /usr/local/bin/godot \
    && mv "/opt/godot/${DIR_NAME}/GodotSharp" /usr/local/bin/GodotSharp \
    && chmod +x /usr/local/bin/godot \
    && rm -rf /tmp/godot.zip /opt/godot \
    && printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -euo pipefail' \
        'export DISPLAY=:1' \
        'RES="${RESOLUTION:-1920x1080}"' \
        'cleanup() { jobs -p | xargs -r kill 2>/dev/null || true; }' \
        'trap cleanup EXIT INT TERM' \
        'Xvfb :1 -screen 0 "${RES}x24" &' \
        'sleep 1' \
        'fluxbox &' \
        'x11vnc -display :1 -nopw -forever -shared -rfbport 5900 &' \
        'websockify --web /usr/share/novnc/ 4510 localhost:5900 &' \
        'godot' \
        > /usr/local/bin/start-godot.sh \
    && chmod +x /usr/local/bin/start-godot.sh

RUN mkdir -p /home/godot/projects /home/godot/.config/godot /home/godot/.local/share/godot \
    && chown -R 1000:1000 /home/godot

ENV HOME=/home/godot \
    RESOLUTION=1920x1080

EXPOSE 4510
USER 1000

WORKDIR /home/godot/projects

CMD ["/usr/local/bin/start-godot.sh"]