#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------
# Build and install glibc 2.39 on Linux (e.g., Ubuntu 22.04)
# -------------------------------------------------------------

REQUIRED_VERSION="2.39"
BUILD_ROOT="/opt/glibc-build"
SRC_DIR="$BUILD_ROOT/glibc-$REQUIRED_VERSION"
BUILD_DIR="$BUILD_ROOT/glibc-$REQUIRED_VERSION-build"
INSTALL_DIR="$BUILD_ROOT/glibc-$REQUIRED_VERSION-install"
TAR_FILE="$BUILD_ROOT/glibc-$REQUIRED_VERSION.tar.gz"

# Function to print section headers
echo_header() { echo -e "\n===== $1 ====="; }

# Ensure root privileges
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root." >&2
  exit 1
fi

# Check current glibc version
CURRENT_VERSION=$(ldd --version | head -n1 | awk '{print $NF}')
echo_header "Current glibc version: $CURRENT_VERSION"
if printf '%s\n%s' "$REQUIRED_VERSION" "$CURRENT_VERSION" | sort -V | head -n1 | grep -qx "$REQUIRED_VERSION"; then
  echo "glibc >= $REQUIRED_VERSION already installed; nothing to do."
  exit 0
fi

# Prepare build directories
echo_header "Preparing build directories"
mkdir -p "$BUILD_ROOT"
cd "$BUILD_ROOT"

# Download source if necessary
echo_header "Downloading glibc $REQUIRED_VERSION source"
if [[ ! -f "$TAR_FILE" ]]; then
  wget "http://ftp.gnu.org/gnu/libc/glibc-$REQUIRED_VERSION.tar.gz"
fi

# Extract source
echo_header "Extracting source"
rm -rf "$SRC_DIR"
tar -xf "$TAR_FILE"

# Configure build directory
echo_header "Configuring build"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"
"$SRC_DIR/configure" --prefix="$INSTALL_DIR"

# Compile
echo_header "Compiling (this may take several minutes)"
make -j"$(nproc)"

# Install
echo_header "Installing to $INSTALL_DIR"
make install

# Update LD_LIBRARY_PATH for current session
echo_header "Updating LD_LIBRARY_PATH"
export LD_LIBRARY_PATH="$INSTALL_DIR/lib:${LD_LIBRARY_PATH:-}"

# Persistent usage hint
echo_header "Build complete"
echo "To use this glibc, prepend '$INSTALL_DIR/lib' to LD_LIBRARY_PATH or adjust loader."
