#!/usr/bin/env bash
################################################################################
# Script: install_ffmpeg_decklink_alsa.sh
# Description: This script installs FFmpeg with DeckLink and ALSA support on
#              Rocky Linux 9. It is idempotent and uses status flags to
#              avoid re-running completed steps.
# Revision: 2.0
# Date: 2025-06-21
#
# Usage:
#   ./install_ffmpeg_decklink_alsa.sh
#   ./install_ffmpeg_decklink_alsa.sh --force  (to re-install from scratch)
################################################################################

# --- Configuration ---
set -e

# Software Versions
FFMPEG_VERSION="7.1.1"
DECKLINK_SDK_VERSION="14.4.1"

# URLs and Checksums
FFMPEG_URL="https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz"
FFMPEG_FILENAME="ffmpeg-${FFMPEG_VERSION}.tar.xz"
FFMPEG_MD5SUM="26f2bd7d20c6c616f31d7130c88d7250"

DECKLINK_SDK_URL="https://drive.usercontent.google.com/download?id=1feBeeeaqFQPZCF07am5VebRtU4jOi4tP&confirm=y"
DECKLINK_SDK_FILENAME="decklink_sdk_drivers.tar.gz"
DECKLINK_SDK_MD5SUM="576520bf6cfc270ea32a3c76d80aad2d"

# DeckLink Driver RPM - Version specific
DECKLINK_RPM_FILENAME_OLD="desktopvideo-14.4.1a4.x86_64.rpm"
DECKLINK_RPM_URL_NEW="https://drive.usercontent.google.com/download?id=1tAHXbZOnOKi_PGhKga_GXD8GzP48uoU3&confirm=y"
DECKLINK_RPM_FILENAME_NEW="desktopvideo-14.4.1-a4.1.el9.x86_64.rpm"
DECKLINK_RPM_MD5SUM_NEW="e1948617adbede12b456a39ed5ad5ad0"

# Directories
SOURCE_DIR="${HOME}/ffmpeg_decklink_alsa_sources"
STATUS_DIR="${SOURCE_DIR}/.install_status"
LICENSE_DIR="/usr/share/licenses/decklink"
DOC_DIR="/usr/share/doc/decklink"

# --- Functions ---

log() {
    echo "--> $1"
}

verify_checksum() {
    local filename="$1"
    local expected_md5sum="$2"
    log "Verifying checksum for ${filename}..."
    if ! echo "${expected_md5sum}  ${filename}" | md5sum -c; then
        log "ERROR: Checksum for ${filename} failed."
        exit 1
    fi
    log "Checksum for ${filename} verified successfully."
}

download_if_missing() {
    if [ -f "$1" ]; then
        log "File '$1' already exists. Skipping download."
    else
        log "Downloading '$1'..."
        wget --no-check-certificate -O "$1" "$2"
    fi
}

# Creates a status flag for a completed component
set_status_flag() {
    local component_name="$1"
    local version_info="$2"
    echo "${version_info}" > "${STATUS_DIR}/${component_name}"
}

# Checks if a component is already installed and matches the required version
is_installed() {
    local component_name="$1"
    local required_version="$2"
    local flag_file="${STATUS_DIR}/${component_name}"

    if [ -f "${flag_file}" ]; then
        installed_version=$(cat "${flag_file}")
        if [ "${installed_version}" == "${required_version}" ]; then
            log "Component '${component_name}' version '${required_version}' already installed. Skipping."
            return 0 # Success (is installed)
        else
            log "Component '${component_name}' has a different version. Re-installing."
            return 1 # Failure (not installed or wrong version)
        fi
    fi
    return 1 # Failure (not installed)
}

# --- Main Script Execution ---

log "Script started. This will install FFmpeg with DeckLink and ALSA support."

# Check for --force flag
if [[ "$1" == "--force" ]]; then
    log "Force mode enabled. Cleaning up previous installation."
    rm -rf "${SOURCE_DIR}"
fi

# Check for final completion flag
if is_installed "ffmpeg_alsa" "${FFMPEG_VERSION}"; then
    log "FFmpeg (ALSA/DeckLink) ${FFMPEG_VERSION} is already fully installed."
    log "Use './install_ffmpeg_decklink_alsa.sh --force' to re-install from scratch."
    exit 0
fi

# 1. Prepare Environment
log "Preparing source directory at ${SOURCE_DIR}"
mkdir -p "${SOURCE_DIR}"
mkdir -p "${STATUS_DIR}"
cd "${SOURCE_DIR}"

# 2. Install Prerequisites
if ! is_installed "prerequisites_alsa" "1.0"; then
    log "Installing prerequisite packages..."
    dnf -y install epel-release
    /usr/bin/crb enable
    dnf -y groupinstall "Development Tools"
    # Added dkms and kernel-devel for driver stability across kernel updates
    dnf -y install \
        alsa-lib-devel \
        dkms \
        kernel-devel \
        wget \
        xz
    set_status_flag "prerequisites_alsa" "1.0"
fi

# 3. Install Decklink SDK and Drivers
OS_VERSION_MAJOR_MINOR=$(. /etc/os-release && echo "$VERSION_ID" | cut -d. -f1-2)
if [[ "$OS_VERSION_MAJOR_MINOR" > "9.5" ]]; then
    DECKLINK_DRIVER_VERSION_FLAG="${DECKLINK_SDK_VERSION}-new"
else
    DECKLINK_DRIVER_VERSION_FLAG="${DECKLINK_SDK_VERSION}-old"
fi

if ! is_installed "decklink_driver" "${DECKLINK_DRIVER_VERSION_FLAG}"; then
    log "Installing Decklink SDK and Drivers..."
    download_if_missing "${DECKLINK_SDK_FILENAME}" "${DECKLINK_SDK_URL}"
    verify_checksum "${DECKLINK_SDK_FILENAME}" "${DECKLINK_SDK_MD5SUM}"
    
    DECKLINK_SDK_BASE_DIR="decklink_sdk_drivers"
    if [ ! -d "${DECKLINK_SDK_BASE_DIR}" ]; then tar -xf "${DECKLINK_SDK_FILENAME}"; fi
    
    cp -rf "${DECKLINK_SDK_BASE_DIR}/SDK/include/"* /usr/include/

    if [[ "$OS_VERSION_MAJOR_MINOR" > "9.5" ]]; then
        download_if_missing "${DECKLINK_RPM_FILENAME_NEW}" "${DECKLINK_RPM_URL_NEW}"
        verify_checksum "${DECKLINK_RPM_FILENAME_NEW}" "${DECKLINK_RPM_MD5SUM_NEW}"
        RPM_INSTALL_PATH="${SOURCE_DIR}/${DECKLINK_RPM_FILENAME_NEW}"
    else
        RPM_INSTALL_PATH="${SOURCE_DIR}/${DECKLINK_SDK_BASE_DIR}/drivers/rpm/x86_64/${DECKLINK_RPM_FILENAME_OLD}"
    fi

    if ! rpm -q desktopvideo > /dev/null; then dnf -y localinstall "${RPM_INSTALL_PATH}"; fi
    
    mkdir -p "${LICENSE_DIR}" && mkdir -p "${DOC_DIR}"
    cp -f "${DECKLINK_SDK_BASE_DIR}/drivers/License.txt" "${LICENSE_DIR}/"
    cp -f "${DECKLINK_SDK_BASE_DIR}/SDK/Blackmagic DeckLink SDK.pdf" "${DOC_DIR}/"
    set_status_flag "decklink_driver" "${DECKLINK_DRIVER_VERSION_FLAG}"
fi

# 4. Download and Compile FFmpeg
log "Downloading and compiling FFmpeg from official source..."
download_if_missing "${FFMPEG_FILENAME}" "${FFMPEG_URL}"
verify_checksum "${FFMPEG_FILENAME}" "${FFMPEG_MD5SUM}"

if [ ! -d "ffmpeg-${FFMPEG_VERSION}" ]; then
    log "Extracting FFmpeg..."
    tar -xf "${FFMPEG_FILENAME}"
fi
cd "ffmpeg-${FFMPEG_VERSION}"

log "Configuring FFmpeg build..."
./configure --prefix=/usr \
    --libdir=/usr/lib64 \
    --shlibdir=/usr/lib64 \
    --enable-decklink \
    --enable-alsa

log "Compiling FFmpeg (this may take a while)..."
make -j$(nproc) && make install

# --- Finalization ---
log "Cleaning up and finalizing installation..."
ldconfig
updatedb
set_status_flag "ffmpeg_alsa" "${FFMPEG_VERSION}"

log "========================================================================"
log "      Installation finished successfully!"
log "      FFmpeg ${FFMPEG_VERSION} with DeckLink and ALSA support is ready."
log "      Sources are located in '${SOURCE_DIR}'."
log "========================================================================"

exit 0
