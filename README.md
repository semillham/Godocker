# Godocker — Portable Browser-Based Godot Workstation

Godocker packages the **Godot Engine** inside a Linux container (`rockylinux/rockylinux:9-minimal`) with **Xvfb**, **Fluxbox**, **x11vnc**, and **noVNC** so you can develop games in a web browser (`http://localhost:4510/vnc.html`) from any device on your network or local machine.

It is designed around two core goals:

1. **A consistent browser-based Godot workspace:** Maintain the exact same editor setup, projects, and runtime environment across your home machines without installing engine dependencies directly onto every device.
2. **A low-barrier home experience:** Provide an interactive `startup.sh` script that automates OS/SELinux detection, Podman or Docker selection, version selection, persistent directory permissions, and GPU hardware flags.

---

## Features

* **Browser-Accessible Editor (`:4510`):** Access Godot over noVNC from any modern web browser without installing a local VNC client.
* **Unified GDScript & C# Support:** Uses the official Godot `.NET` (`mono`) release alongside `.NET SDK 8.0` and `GodotSharp`, supporting pure GDScript, C#, or mixed-language projects out of the box.
* **Selectable Godot Version:** Prompts for any upstream Godot release tag at setup time (defaulting to `4.7.2-stable`).
* **Persistent State:** Preserves projects, editor preferences, and downloaded export templates across container restarts and rebuilds.
* **Cross-Engine Compatibility:** Works seamlessly with **Podman** or **Docker**, with an interactive prompt to install Podman if neither engine is present.
* **Flexible Graphics Acceleration:** Supports CPU software rendering (`llvmpipe`), AMD/Intel GPUs (`/dev/dri`), and NVIDIA GPUs (`--gpus all` / CDI).
* **Safety-First Automation:** Enforces `sudo` privileges up front, detects live SELinux state, validates host mount paths against accidental system/home relabeling, verifies daemon availability, and confirms before replacing an existing `godot-home` container.

---

## Technical Specifications

### Container & OS Stack

| Component | Specification | Notes |
| :--- | :--- | :--- |
| **Base Image** | `rockylinux/rockylinux:9-minimal` | Minimal RPM-based footprint using `microdnf` |
| **Container Engine** | Podman or Docker | Auto-detected by `startup.sh` (prefers Podman if both exist) |
| **Container Name** | `godot-home` | Single-instance home workstation naming |
| **Container User** | `1000:1000` (`HOME=/home/godot`) | Host bind mounts are `chown`-mapped to `$SUDO_UID:$SUDO_GID` |
| **Default Workdir** | `/home/godot/projects` | Maps directly to `./projects` on the host |
| **Restart Policy** | `always` (Podman) / `unless-stopped` (Docker) | Engine-appropriate automatic recovery on reboot |

### Engine & Runtime Tooling

| Component | Specification | Notes |
| :--- | :--- | :--- |
| **Godot Engine** | `4.7.2-stable` (Configurable via `GODOT_VERSION`) | Official `_mono_linux.x86_64` release (supports both GDScript and C#) |
| **.NET Runtime / SDK** | `dotnet-sdk-8.0` | Paired with `/usr/local/bin/GodotSharp` next to `/usr/local/bin/godot` |
| **CLI Utilities** | `bash`, `git`, `wget`, `unzip`, `ca-certificates` | Included for source control and workspace management |
| **Audio Subsystem** | `alsa-lib` | Satisfies Godot Linux binary audio library dependencies |

### Display, Graphics & Networking Stack

| Component | Specification | Notes |
| :--- | :--- | :--- |
| **Virtual X Server** | `Xvfb` on `DISPLAY=:1` | Default screen geometry `1920x1080x24` |
| **Window Manager** | `fluxbox` | Lightweight window management for editor dialogs and popups |
| **VNC Server** | `x11vnc` (Internal port `5900`) | Configured with `-nopw -forever -shared` |
| **Web Proxy / UI** | `python3-websockify` + `novnc` | Exposed on container & host port `4510/tcp` (`/usr/share/novnc/`) |
| **Graphics Libraries** | `mesa-dri-drivers`, `mesa-libGL`, `mesa-vulkan-drivers`, `vulkan-loader`, `vulkan-tools` | Vendor-neutral OpenGL & Vulkan ICD/loader stack |
| **X11 Libraries** | `libX11`, `libXcursor`, `libXrandr`, `libXi`, `libXinerama`, `libXext`, `libXrender`, `libXfixes`, `libXdamage`, `fontconfig` | Full X11 windowing, input, and font rendering support |

### Build Arguments & Environment Variables

| Variable | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `GODOT_VERSION` | Build `ARG` | `4.7.2-stable` | Upstream Godot release tag downloaded during image build |
| `RESOLUTION` | Runtime `ENV` | `1920x1080` | Sets the `Xvfb` virtual display resolution (`<WIDTH>x<HEIGHT>`) |
| `HOME` | Runtime `ENV` | `/home/godot` | Home directory for container user `1000` |
| `DISPLAY` | Runtime `ENV` | `:1` | X11 display target used by `Xvfb`, `fluxbox`, `x11vnc`, and `godot` |

### Persistent Storage & SELinux Handling

`startup.sh` resolves target paths with `realpath -m`—blocking `/`, `$HOME`, `$TARGET_HOME`, and top-level OS directories (`/etc`, `/usr`, `/var`, etc.)—and appends `:Z` to volume mounts **only** when SELinux is live (`Enforcing` or `Permissive` via `getenforce` or `/sys/fs/selinux`).

| Host Path | Container Path | Purpose |
| :--- | :--- | :--- |
| `./projects` | `/home/godot/projects` | Godot project files, scenes, scripts, and assets |
| `./godot-config` | `/home/godot/.config/godot` | Editor settings, theme layouts, and shortcut profiles |
| `./godot-data` | `/home/godot/.local/share/godot` | Export templates, shader caches, and local editor data |

### Hardware Acceleration Modes

| Mode | Host Requirement | Runtime Flags Applied |
| :--- | :--- | :--- |
| **1. Auto / CPU Fallback** | Any Linux host | None (uses Mesa `llvmpipe` software rasterizer) |
| **2. AMD / Intel GPU** | Linux host with `/dev/dri` | `--device /dev/dri:/dev/dri` |
| **3. NVIDIA GPU (Podman)** | Host NVIDIA drivers + CDI (`nvidia.com/gpu`) | `--device nvidia.com/gpu=all` |
| **3. NVIDIA GPU (Docker)** | Host NVIDIA drivers + NVIDIA Container Toolkit | `--gpus all -e NVIDIA_VISIBLE_DEVICES=all -e NVIDIA_DRIVER_CAPABILITIES=graphics,display,utility` |

---

## Project Layout

```text
.
├── Dockerfile          # Builds the Rocky Linux 9 Minimal + Godot (.NET/GDScript) + noVNC image
├── startup.sh          # Interactive setup & deployment script for home users
├── README.md           # Technical documentation and troubleshooting guide
├── projects/           # Persistent Godot projects (/home/godot/projects)
├── godot-config/       # Persistent Godot editor settings (/home/godot/.config/godot)
└── godot-data/         # Persistent export templates & user data (/home/godot/.local/share/godot)
```

---

## Quick Start

1. Place `Dockerfile` and `startup.sh` inside a dedicated workspace directory (for example, `~/godocker-home`):

   ```bash
   mkdir -p ~/godocker-home && cd ~/godocker-home
   ```

2. Make `startup.sh` executable and run it with `sudo`:

   ```bash
   chmod +x startup.sh
   sudo ./startup.sh
   ```

3. Complete the interactive prompts:
   * **Existing deployment check:** If `godot-home` already exists, confirm whether to remove and replace it.
   * **Godot version tag:** Press Enter for `4.7.2-stable` or enter another official GitHub release tag (for example, `4.6.3-stable` or `4.3-stable`).
   * **Screen resolution:** Default `1920x1080`
   * **GPU acceleration:** Auto/CPU fallback, AMD/Intel (`/dev/dri`), or NVIDIA

4. Open your browser and navigate to:

   ```text
   http://localhost:4510/vnc.html
   ```

---

## Daily Operations

| Action | Docker Command | Podman Command |
| :--- | :--- | :--- |
| **Check status** | `docker ps --filter "name=godot-home"` | `podman ps --filter "name=godot-home"` |
| **Stop workspace** | `docker stop godot-home` | `podman stop godot-home` |
| **Start workspace** | `docker start godot-home` | `podman start godot-home` |
| **View logs** | `docker logs -f godot-home` | `podman logs -f godot-home` |
| **Verify GPU/Vulkan** | `docker exec godot-home vulkaninfo --summary` | `podman exec godot-home vulkaninfo --summary` |
| **Rebuild / Reconfigure** | `sudo ./startup.sh` (confirm removal when prompted) | `sudo ./startup.sh` (confirm removal when prompted) |

---

## Troubleshooting

### `startup.sh` exits immediately asking for `sudo`
`startup.sh` enforces `EUID == 0` at startup so it can install Podman if missing and manage system container services while still mapping folder ownership back to `$SUDO_UID:$SUDO_GID`. Run:

```bash
sudo ./startup.sh
```

### Docker is installed, but `docker info` fails
The Docker daemon (`dockerd`) is stopped. Start the service and re-run `startup.sh`:

```bash
sudo systemctl start docker
```

### Rootless Podman warns about missing `subuid` / `subgid` entries
If `/etc/subuid` does not contain an entry for your non-root username, allocate subordinate UID/GID ranges and migrate Podman:

```bash
sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 "$USER"
podman system migrate
```

### Image build fails during `wget` for `GODOT_VERSION`
Verify that the entered version tag matches an exact release tag on the official Godot GitHub releases page (for example, `4.7.2-stable`, `4.6.3-stable`, or `4.3-stable`) and includes `-stable` (or the appropriate pre-release suffix).

### Browser cannot connect to `http://localhost:4510/vnc.html`
1. Verify `godot-home` is in the `Up` state (`docker ps` or `podman ps`).
2. Inspect container startup logs (`docker logs godot-home` or `podman logs godot-home`) for Xvfb, websockify, or Godot binary errors.
3. Confirm no other host service is already bound to TCP port `4510` (`ss -tulpn | grep 4510`).

### GPU acceleration falls back to software rendering (`llvmpipe`)
* **AMD / Intel:** Confirm `/dev/dri` exists on the host (`ls -la /dev/dri`) and select option `2` in `startup.sh`. Run `vulkaninfo --summary` inside the container to verify your hardware GPU appears instead of `llvmpipe`.
* **NVIDIA:** Confirm `nvidia-smi` works on the host and that either the **NVIDIA Container Toolkit** (Docker) or **CDI configuration** (`nvidia-ctk cdi generate`, Podman) is configured before choosing option `3`.

---

## Roadmap Notes

This deployment script (`startup.sh`) targets a **single home workstation** (`godot-home` on port `4510`). Future multi-user enterprise deployments will extend this image by parameterizing per-user container names, isolated user storage directories, dynamic port or reverse-proxy routing, VNC/web authentication, and per-user CPU/memory quotas.