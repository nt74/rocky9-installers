#!/usr/bin/env bash

# Script: install_ffmpeg_decklink_alsa.sh
# Description: This script installs FFmpeg 7.1 and BlackMagic DeckLink SDK 14.2 on Rocky Linux 9.5.
#              It enables ALSA and DeckLink support and installs all binaries and libraries to /usr.
#              The script uses curl for downloads, verifies MD5 checksums, and extracts sources
#              to a directory in the user's $HOME.
# Usage: ./install_ffmpeg_decklink_alsa.sh
# Author: Nikos Toutountzoglou
# Date: 2025-02-05
# Rev: 01

# Variables
FFMPEG_VERSION="7.1"
FFMPEG_URL="https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz"
FFMPEG_FILENAME="ffmpeg-${FFMPEG_VERSION}.tar.xz"
FFMPEG_MD5SUM="623aa63a72139a82ccb99cd6ee477b94"

DECKLINK_SDK_VERSION="14.2"
DECKLINK_SDK_URL="https://drive.usercontent.google.com/download?id=1feBeeeaqFQPZCF07am5VebRtU4jOi4tP&confirm=y"
DECKLINK_SDK_FILENAME="decklink_sdk_drivers.tar.gz"
DECKLINK_SDK_MD5SUM="576520bf6cfc270ea32a3c76d80aad2d"
DECKLINK_RPM_FILENAME="desktopvideo-14.4.1a4.x86_64.rpm"

ALSA_ENABLED="true"
INSTALL_PREFIX="/usr"
SOURCE_DIR="${HOME}/ffmpeg_decklink_sources"
DOWNLOAD_CMD="curl -L -o"
MD5_CHECK="md5sum -c"

LICENSE_DIR="/usr/share/licenses/decklink"
DOC_DIR="/usr/share/doc/decklink"

# Function to handle errors
handle_error() {
    echo "An error occurred. Exiting..."
    exit 1
}

# Trap errors and clean up
trap 'handle_error' ERR

# Function to prompt user for confirmation
confirm() {
    local prompt="$1"
    local default_response="${2:-y}"
    local response

    read -r -p "${prompt} [Y/n] (default: ${default_response}): " response
    response="${response:-${default_response}}"

    [[ "${response}" =~ ^[Yy]$ ]]
}

# Function to delete the source directory
delete_source_dir() {
    if [ -d "${SOURCE_DIR}" ]; then
        echo "Deleting source directory: ${SOURCE_DIR}..."
        rm -rf "${SOURCE_DIR}"
    fi
}

# Function to install all required components
install_all_dependencies() {
    echo "Installing Development Tools group, EPEL repository, PowerTools repository, and required dependencies..."

    # Install Development Tools group
    sudo dnf groupinstall -y "Development Tools"

    # Install EPEL repository
    sudo dnf install -y epel-release

    # Enable PowerTools repository
    sudo dnf config-manager --set-enabled crb

    # Install dependencies
    sudo dnf install -y curl gcc gcc-c++ make autoconf automake libtool \
        alsa-lib-devel xz nasm
}

# Function to download and verify a file
download_and_verify() {
    local url="$1"
    local filename="$2"
    local md5sum="$3"

    echo "Downloading ${filename}..."
    ${DOWNLOAD_CMD} "${filename}" "${url}"

    echo "Verifying MD5 checksum for ${filename}..."
    echo "${md5sum}  ${filename}" | ${MD5_CHECK}
}

# Function to extract a tarball
extract_tarball() {
    local filename="$1"
    echo "Extracting ${filename}..."
    if [[ "${filename}" == *.tar.xz ]]; then
        tar -xf "${filename}"
    elif [[ "${filename}" == *.tar.gz ]]; then
        tar -xzf "${filename}"
    else
        echo "Unsupported file format for extraction: ${filename}"
        handle_error
    fi
}

# Function to install BlackMagic DeckLink SDK and drivers
install_decklink_sdk_and_drivers() {
    echo "Installing BlackMagic DeckLink SDK ${DECKLINK_SDK_VERSION} and drivers..."
    download_and_verify "${DECKLINK_SDK_URL}" "${DECKLINK_SDK_FILENAME}" "${DECKLINK_SDK_MD5SUM}"
    extract_tarball "${DECKLINK_SDK_FILENAME}"

    # Copy SDK headers to /usr/include
    echo "Copying BlackMagic SDK headers to /usr/include..."
    sudo cp -r "${SOURCE_DIR}/decklink_sdk_drivers/SDK/include" "/usr/include"

    # Install the RPM driver
    echo "Installing RPM driver: ${DECKLINK_RPM_FILENAME}..."
    sudo dnf install -y "${SOURCE_DIR}/decklink_sdk_drivers/drivers/rpm/x86_64/${DECKLINK_RPM_FILENAME}"

    # Copy License and Documentation files
    echo "Copying License and Documentation files..."
    sudo mkdir -p "${LICENSE_DIR}"
    sudo mkdir -p "${DOC_DIR}"
    sudo cp "${SOURCE_DIR}/decklink_sdk_drivers/drivers/License.txt" "${LICENSE_DIR}/"
    sudo cp "${SOURCE_DIR}/decklink_sdk_drivers/SDK/Blackmagic DeckLink SDK.pdf" "${DOC_DIR}/"
}

# Function to install FFmpeg
install_ffmpeg() {
    echo "Installing FFmpeg ${FFMPEG_VERSION}..."
    download_and_verify "${FFMPEG_URL}" "${FFMPEG_FILENAME}" "${FFMPEG_MD5SUM}"
    extract_tarball "${FFMPEG_FILENAME}"

    cd "ffmpeg-${FFMPEG_VERSION}" || handle_error

    # Configure FFmpeg (only ALSA and DeckLink are enabled)
    ./configure --prefix="${INSTALL_PREFIX}" \
                --enable-decklink \
                --enable-alsa

    # Build and install FFmpeg
    make -j"$(nproc)"
    sudo make install
}

# Main script execution
if confirm "Do you want to reinstall (delete source folder and re-download/re-install)?"; then
    delete_source_dir
fi

mkdir -p "${SOURCE_DIR}"
cd "${SOURCE_DIR}" || handle_error

if confirm "Install all required components (Development Tools group, EPEL repository, PowerTools repository, and dependencies)?"; then
    install_all_dependencies
fi

if confirm "Install BlackMagic DeckLink SDK and drivers?"; then
    install_decklink_sdk_and_drivers
fi

if confirm "Install FFmpeg ${FFMPEG_VERSION}?"; then
    install_ffmpeg
fi

echo "Installation completed successfully!"
