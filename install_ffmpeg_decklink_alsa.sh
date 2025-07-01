#!/usr/bin/env bash
################################################################################
# Script: install_ffmpeg_decklink_alsa.sh
# Description: This script installs FFmpeg with DeckLink and ALSA support on
#              Rocky Linux 9. It is idempotent and uses status flags to
#              avoid re-running completed steps. Prompts for DeckLink driver
#              reinstall if already present.
# Revision: 2.1
# Date: 2025-07-01
#
# Usage:
#   ./install_ffmpeg_decklink_alsa.sh
#   ./install_ffmpeg_decklink_alsa.sh --force  (to re-install from scratch)
################################################################################

set -e

# --- User Safety and Home Directory Management ---
if [ "$(id -u)" -eq 0 ]; then
    echo "Do NOT run this script as root. Please run it as a regular user."
    exit 1
fi

USER_HOME="${HOME}"

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

DECKLINK_RPM_FILENAME_OLD="desktopvideo-14.4.1a4.x86_64.rpm"
DECKLINK_RPM_URL_NEW="https://drive.usercontent.google.com/download?id=1tAHXbZOnOKi_PGhKga_GXD8GzP48uoU3&confirm=y"
DECKLINK_RPM_FILENAME_NEW="desktopvideo-14.4.1-a4.1.el9.x86_64.rpm"
DECKLINK_RPM_MD5SUM_NEW="e1948617adbede12b456a39ed5ad5ad0"

# Directories (always in user's home)
SOURCE_DIR="${USER_HOME}/ffmpeg_decklink_alsa_sources"
STATUS_DIR="${SOURCE_DIR}/.install_status"
LICENSE_DIR="/usr/share/licenses/decklink"
DOC_DIR="/usr/share/doc/decklink"

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

set_status_flag() {
    local component_name="$1"
    local version_info="$2"
    echo "${version_info}" > "${STATUS_DIR}/${component_name}"
}

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

ask_yes_no() {
    local prompt="$1"
    local default="${2:-n}"
    local reply
    if [ "$default" = "y" ]; then
        prompt="$prompt [Y/n] "
    else
        prompt="$prompt [y/N] "
    fi
    read -rp "$prompt" reply
    reply="${reply,,}"
    if [[ -z "$reply" ]]; then
        reply="$default"
    fi
    [[ "$reply" == "y" || "$reply" == "yes" ]]
}

run_sudo() {
    sudo "$@"
}

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
    run_sudo dnf -y install epel-release
    run_sudo /usr/bin/crb enable
    run_sudo dnf -y groupinstall "Development Tools"
    run_sudo dnf -y install \
        alsa-lib-devel \
        dkms \
        kernel-devel \
        wget \
        xz
    set_status_flag "prerequisites_alsa" "1.0"
fi

# 3. Install Decklink SDK and Drivers, with prompt for reinstall
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

    run_sudo cp -rf "${DECKLINK_SDK_BASE_DIR}/SDK/include/"* /usr/include/

    if [[ "$OS_VERSION_MAJOR_MINOR" > "9.5" ]]; then
        download_if_missing "${DECKLINK_RPM_FILENAME_NEW}" "${DECKLINK_RPM_URL_NEW}"
        verify_checksum "${DECKLINK_RPM_FILENAME_NEW}" "${DECKLINK_RPM_MD5SUM_NEW}"
        RPM_INSTALL_PATH="${SOURCE_DIR}/${DECKLINK_RPM_FILENAME_NEW}"
    else
        RPM_INSTALL_PATH="${SOURCE_DIR}/${DECKLINK_SDK_BASE_DIR}/drivers/rpm/x86_64/${DECKLINK_RPM_FILENAME_OLD}"
    fi

    decklink_installed=0
    if rpm -q desktopvideo > /dev/null; then
        decklink_installed=1
    fi

    if [ "$decklink_installed" -eq 1 ]; then
        if ask_yes_no "DeckLink driver is already installed. Do you want to force reinstall it?" "n"; then
            run_sudo dnf -y reinstall "${RPM_INSTALL_PATH}"
        else
            log "Skipping DeckLink driver installation as it is already installed."
            decklink_installed=2
        fi
    fi

    if [ "$decklink_installed" -eq 0 ]; then
        run_sudo dnf -y localinstall "${RPM_INSTALL_PATH}"
    fi

    run_sudo mkdir -p "${LICENSE_DIR}" && run_sudo mkdir -p "${DOC_DIR}"
    run_sudo cp -f "${DECKLINK_SDK_BASE_DIR}/drivers/License.txt" "${LICENSE_DIR}/"
    run_sudo cp -f "${DECKLINK_SDK_BASE_DIR}/SDK/Blackmagic DeckLink SDK.pdf" "${DOC_DIR}/"
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
make -j$(nproc) && run_sudo make install

# --- Finalization ---
log "Cleaning up and finalizing installation..."
run_sudo ldconfig
run_sudo updatedb
set_status_flag "ffmpeg_alsa" "${FFMPEG_VERSION}"

log "========================================================================"
log "      Installation finished successfully!"
log "      FFmpeg ${FFMPEG_VERSION} with DeckLink and ALSA support is ready."
log "      Sources are located in '${SOURCE_DIR}'."
log "========================================================================"

# Prompt to keep or delete placeholder/source files (status flags always kept)
if ! ask_yes_no "Do you want to keep all the sourcedir placeholder files and directories?" "n"; then
    log "Deleting sourcedir and placeholder files as requested (status flags preserved)."
    find "${SOURCE_DIR}" -mindepth 1 -maxdepth 1 ! -name ".install_status" -exec rm -rf {} +
else
    log "Keeping sourcedir and placeholder files as requested."
fi

exit 0
