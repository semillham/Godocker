#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# 0. Require sudo / root privileges up front
# ---------------------------------------------------------------------------
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  echo "This setup script requires administrator privileges to configure packages and containers."
  echo "Please re-run it with sudo:"
  echo "  sudo $0 $*"
  exit 1
fi

TARGET_USER="${SUDO_USER:-root}"
TARGET_UID="${SUDO_UID:-1000}"
TARGET_GID="${SUDO_GID:-1000}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6 || echo "/home/${TARGET_USER}")"
CONTAINER_NAME="godot-home"

# ---------------------------------------------------------------------------
# 1. Detect OS and live SELinux state
# ---------------------------------------------------------------------------
detect_os_and_selinux() {
  OS_ID="unknown"
  OS_LIKE=""
  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_LIKE="${ID_LIKE:-}"
  fi

  VOL_SUFFIX=""
  SELINUX_MODE="none"

  if command -v getenforce >/dev/null 2>&1; then
    SELINUX_MODE="$(getenforce 2>/dev/null || echo "Disabled")"
    case "$SELINUX_MODE" in
      Enforcing|Permissive)
        VOL_SUFFIX=":Z"
        ;;
    esac
  elif [ -d /sys/fs/selinux ]; then
    SELINUX_MODE="active"
    VOL_SUFFIX=":Z"
  fi

  echo "Detected OS: ${OS_ID} (SELinux: ${SELINUX_MODE})"
}

# ---------------------------------------------------------------------------
# 2. Safety-first path guard before mounting or relabeling with :Z
# ---------------------------------------------------------------------------
validate_mount_dir() {
  local raw_path="$1"
  local resolved_path
  resolved_path="$(realpath -m "$raw_path")"

  case "$resolved_path" in
    ""|"/"|"/bin"|"/boot"|"/dev"|"/etc"|"/home"|"/lib"|"/lib64"|"/opt"|"/proc"|"/root"|"/run"|"/sbin"|"/srv"|"/sys"|"/tmp"|"/usr"|"/var"|"$HOME"|"$TARGET_HOME")
      echo "Safety Error: Refusing to mount or relabel sensitive path: ${resolved_path}"
      echo "Please run this script inside a dedicated project folder (e.g., ~/godot-workspace)."
      exit 1
      ;;
  esac

  mkdir -p "$resolved_path"
  chown -R "${TARGET_UID}:${TARGET_GID}" "$resolved_path"
  echo "$resolved_path"
}

# ---------------------------------------------------------------------------
# 3. Confirmed Podman installation fallback
# ---------------------------------------------------------------------------
install_podman() {
  echo "Installing Podman..."
  case "$OS_ID $OS_LIKE" in
    *fedora*|*rhel*|*rocky*|*centos*|*almalinux*)
      dnf install -y podman
      ;;
    *ubuntu*|*debian*|*mint*|*pop*)
      apt-get update && apt-get install -y podman
      ;;
    *arch*|*manjaro*|*steamos*)
      pacman -Sy --noconfirm podman
      ;;
    *suse*|*opensuse*)
      zypper install -y podman
      ;;
    *)
      if command -v dnf >/dev/null 2>&1; then
        dnf install -y podman
      elif command -v apt-get >/dev/null 2>&1; then
        apt-get update && apt-get install -y podman
      elif command -v pacman >/dev/null 2>&1; then
        pacman -Sy --noconfirm podman
      elif command -v zypper >/dev/null 2>&1; then
        zypper install -y podman
      else
        echo "Unsupported package manager. Please install Podman manually: https://podman.io/docs/installation"
        exit 1
      fi
      ;;
  esac
}

# ---------------------------------------------------------------------------
# 4. Check for an existing Godocker container before setup
# ---------------------------------------------------------------------------
handle_existing_container() {
  if "$ENGINE" container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
    echo ""
    echo "An existing '${CONTAINER_NAME}' container deployment was found."
    read -r -p "Do you want to delete the previous deployment of Godocker? [y/N]: " REMOVE_CHOICE
    REMOVE_CHOICE="${REMOVE_CHOICE:-N}"

    if [[ "$REMOVE_CHOICE" =~ ^[Yy]$ ]]; then
      echo "Removing previous '${CONTAINER_NAME}' container..."
      "$ENGINE" rm -f "$CONTAINER_NAME" >/dev/null
    else
      echo "Keeping existing '${CONTAINER_NAME}' container. Setup aborted without changes."
      exit 0
    fi
  fi
}

# ---------------------------------------------------------------------------
# Main Execution
# ---------------------------------------------------------------------------
detect_os_and_selinux

if command -v podman >/dev/null 2>&1; then
  ENGINE="podman"
elif command -v docker >/dev/null 2>&1; then
  ENGINE="docker"
else
  echo "Neither Podman nor Docker was found on this system."
  read -r -p "Would you like to install Podman now? [Y/n]: " INSTALL_CHOICE
  INSTALL_CHOICE="${INSTALL_CHOICE:-Y}"

  if [[ "$INSTALL_CHOICE" =~ ^[Yy]$ ]]; then
    install_podman
    if ! command -v podman >/dev/null 2>&1; then
      echo "Podman installation did not complete. Please review the output above."
      exit 1
    fi
    ENGINE="podman"
  else
    echo "Setup cancelled. Please install Podman or Docker and re-run: sudo $0"
    exit 0
  fi
fi

echo "Using container engine: ${ENGINE}"

if [ "$ENGINE" = "docker" ]; then
  if ! docker info >/dev/null 2>&1; then
    echo "Docker is installed, but the Docker daemon is not running."
    echo "Start it with: sudo systemctl start docker"
    exit 1
  fi
fi

if [ "$ENGINE" = "podman" ] && [ "$TARGET_USER" != "root" ]; then
  if ! grep -q "^${TARGET_USER}:" /etc/subuid 2>/dev/null; then
    echo "Warning: No subuid mapping found for ${TARGET_USER} in /etc/subuid."
    echo "If rootless Podman fails later, run:"
    echo "  sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 ${TARGET_USER} && podman system migrate"
  fi
fi

# Check for an existing container before proceeding with setup
handle_existing_container

echo ""
read -r -p "Godot version tag [4.7.2-stable]: " GODOT_VERSION
GODOT_VERSION="${GODOT_VERSION:-4.7.2-stable}"

read -r -p "Screen resolution [1920x1080]: " RESOLUTION
RESOLUTION="${RESOLUTION:-1920x1080}"

echo ""
echo "Select GPU hardware acceleration:"
echo "  1) Auto / CPU fallback (works everywhere)"
echo "  2) AMD or Intel GPU (/dev/dri)"
echo "  3) NVIDIA GPU"
read -r -p "Choice [1]: " GPU_CHOICE
GPU_CHOICE="${GPU_CHOICE:-1}"

PROJECTS_DIR="$(validate_mount_dir "./projects")"
CONFIG_DIR="$(validate_mount_dir "./godot-config")"
DATA_DIR="$(validate_mount_dir "./godot-data")"

IMAGE_NAME="godot-4510:${GODOT_VERSION}"
echo ""
echo "Building ${IMAGE_NAME} (supports both GDScript and C#; first build may take a few minutes)..."
"$ENGINE" build \
  --build-arg GODOT_VERSION="$GODOT_VERSION" \
  -t "$IMAGE_NAME" .

if [ "$ENGINE" = "podman" ]; then
  RESTART_POLICY="always"
else
  RESTART_POLICY="unless-stopped"
fi

RUN_ARGS=(
  -d
  --name "$CONTAINER_NAME"
  --restart="$RESTART_POLICY"
  -p 4510:4510
  -e "RESOLUTION=${RESOLUTION}"
  -v "${PROJECTS_DIR}:/home/godot/projects${VOL_SUFFIX}"
  -v "${CONFIG_DIR}:/home/godot/.config/godot${VOL_SUFFIX}"
  -v "${DATA_DIR}:/home/godot/.local/share/godot${VOL_SUFFIX}"
)

case "$GPU_CHOICE" in
  2)
    if [ -d /dev/dri ]; then
      RUN_ARGS+=(--device /dev/dri:/dev/dri)
    else
      echo "Warning: /dev/dri not found on host; falling back to CPU rendering."
    fi
    ;;
  3)
    if [ "$ENGINE" = "podman" ]; then
      RUN_ARGS+=(--device nvidia.com/gpu=all)
    else
      RUN_ARGS+=(--gpus all -e NVIDIA_VISIBLE_DEVICES=all -e NVIDIA_DRIVER_CAPABILITIES=graphics,display,utility)
    fi
    ;;
esac

"$ENGINE" run "${RUN_ARGS[@]}" "$IMAGE_NAME"

echo ""
echo "Godot is running! Open http://localhost:4510/vnc.html in your browser."