#!/usr/bin/env bash
################################################################################
# Script: install-ffmpeg-alsa.sh
# Description: Installs FFmpeg with DeckLink and ALSA support on Rocky Linux 9.
#              Simplified version focusing on audio capture and DeckLink basics.
# Revision: 2.2
# Date: 2025-09-04
# Updated for: FFmpeg 8.0, DeckLink SDK 15.0, and Rocky Linux 9.6
################################################################################

set -e

# Ensure script is not run as root
if [ "$(id -u)" -eq 0 ]; then
    echo "Do NOT run this script as root. Please run it as a regular user."
    exit 1
fi

# Get the directory where the script is located
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Get the calling user's home directory safely
USER_HOME="${HOME}"

# Software Versions
FFMPEG_VERSION="8.0"
DECKLINK_SDK_VERSION="15.0"

# URLs and Checksums
FFMPEG_URL="https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz"
FFMPEG_FILENAME="ffmpeg-${FFMPEG_VERSION}.tar.xz"
FFMPEG_MD5SUM="2c91c725fb1b393618554ff429e4ae43"

DECKLINK_SDK_URL="https://drive.usercontent.google.com/download?id=1UvOe7UnwgJMTCDvZZwrwxvWtE9CeepWS&confirm=y"
DECKLINK_SDK_FILENAME="decklink_sdk_drivers.tar.gz"
DECKLINK_SDK_MD5SUM="ef3000b4b0aa0d50ec391cece9ff12e1"

DECKLINK_RPM_FILENAME_15="desktopvideo-15.0a62.x86_64.rpm"

# Directories in the user's home
SOURCE_DIR="${USER_HOME}/ffmpeg_alsa_sources"
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
            return 0 # installed
        fi
    fi
    return 1 # not installed
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
    reply="${reply,,}" # to lower
    if [[ -z "$reply" ]]; then
        reply="$default"
    fi
    [[ "$reply" == "y" || "$reply" == "yes" ]]
}

ask_reinstall_component() {
    ask_yes_no "Component '$1' version '$2' is already installed. Do you want to force re-install it?" "n"
}

ask_force_install() {
    ask_yes_no "Do you want to force install the $1 RPM package? (this may override files)" "n"
}

ask_keep_sourcedir() {
    ask_yes_no "Do you want to keep all the sourcedir placeholder files and directories?" "n"
}

run_sudo() {
    # Run a command with sudo, prompting password if needed
    sudo "$@"
}

log "Script started. This will install FFmpeg ${FFMPEG_VERSION} with DeckLink ${DECKLINK_SDK_VERSION} and ALSA support (simplified version)."

if [[ "$1" == "--force" ]]; then
    log "Force mode enabled. Cleaning up previous installation."
    rm -rf "${SOURCE_DIR}"
fi

log "Preparing source directory at ${SOURCE_DIR}"
mkdir -p "${SOURCE_DIR}"
mkdir -p "${STATUS_DIR}"
cd "${SOURCE_DIR}"

# 1. Prerequisites
if is_installed "prerequisites_alsa" "1.0"; then
    if ask_reinstall_component "prerequisites_alsa" "1.0"; then
        log "Re-installing prerequisites as requested."
        rm -f "${STATUS_DIR}/prerequisites_alsa"
    else
        log "Skipping prerequisites."
    fi
fi
if ! is_installed "prerequisites_alsa" "1.0"; then
    log "Installing prerequisite packages..."
    run_sudo dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
    run_sudo /usr/bin/crb enable
    run_sudo dnf -y groupinstall "Development Tools"
    run_sudo dnf -y install \
        alsa-lib-devel \
        autoconf \
        automake \
        cmake \
        dkms \
        elfutils-libelf-devel \
        kernel-devel \
        libpciaccess-devel \
        libtool \
        nasm \
        patch \
        pkgconf-pkg-config \
        wget \
        xz \
        yasm
    set_status_flag "prerequisites_alsa" "1.0"
fi

# 2. Decklink SDK and Drivers
if is_installed "decklink_driver" "${DECKLINK_SDK_VERSION}"; then
    if ask_reinstall_component "decklink_driver" "${DECKLINK_SDK_VERSION}"; then
        rm -f "${STATUS_DIR}/decklink_driver"
    else
        log "Skipping Decklink driver install."
    fi
fi

if ! is_installed "decklink_driver" "${DECKLINK_SDK_VERSION}"; then
    log "Installing Decklink SDK ${DECKLINK_SDK_VERSION} and Drivers..."
    download_if_missing "${DECKLINK_SDK_FILENAME}" "${DECKLINK_SDK_URL}"
    verify_checksum "${DECKLINK_SDK_FILENAME}" "${DECKLINK_SDK_MD5SUM}"

    DECKLINK_SDK_BASE_DIR="decklink_sdk_drivers"
    if [ ! -d "${DECKLINK_SDK_BASE_DIR}" ]; then tar -xf "${DECKLINK_SDK_FILENAME}"; fi

    log "Installing DeckLink SDK headers..."
    run_sudo cp -rf "${DECKLINK_SDK_BASE_DIR}/SDK/include/"* /usr/include/

    RPM_INSTALL_PATH="${SOURCE_DIR}/${DECKLINK_SDK_BASE_DIR}/drivers/rpm/x86_64/${DECKLINK_RPM_FILENAME_15}"
    if [ ! -f "${RPM_INSTALL_PATH}" ]; then 
        log "ERROR: DeckLink RPM not found at: ${RPM_INSTALL_PATH}"
        exit 1
    fi

    log "Installing DeckLink driver RPM: ${DECKLINK_RPM_FILENAME_15}"
    if ask_force_install "Decklink driver"; then
        if rpm -q desktopvideo > /dev/null; then
            run_sudo dnf -y reinstall "${RPM_INSTALL_PATH}"
        else
            run_sudo dnf -y localinstall --allowerasing "${RPM_INSTALL_PATH}"
        fi
    else
        run_sudo dnf -y localinstall "${RPM_INSTALL_PATH}"
    fi

    run_sudo mkdir -p "${LICENSE_DIR}" && run_sudo mkdir -p "${DOC_DIR}"
    run_sudo cp -f "${DECKLINK_SDK_BASE_DIR}/drivers/License.txt" "${LICENSE_DIR}/"
    run_sudo cp -f "${DECKLINK_SDK_BASE_DIR}/SDK/Blackmagic DeckLink SDK.pdf" "${DOC_DIR}/"
    set_status_flag "decklink_driver" "${DECKLINK_SDK_VERSION}"
fi

# 3. Download and Compile FFmpeg (simplified configuration)
ffmpeg_installed_and_skipped=0
if is_installed "ffmpeg_alsa" "${FFMPEG_VERSION}"; then
    if ask_reinstall_component "ffmpeg_alsa" "${FFMPEG_VERSION}"; then
        rm -f "${STATUS_DIR}/ffmpeg_alsa"
        rm -rf "ffmpeg-${FFMPEG_VERSION}"
    else
        log "FFmpeg ALSA ${FFMPEG_VERSION} is already fully installed."
        log "Use './install-ffmpeg-alsa.sh --force' to re-install from scratch."
        ffmpeg_installed_and_skipped=1
    fi
fi

if [ "$ffmpeg_installed_and_skipped" -ne 1 ]; then
    log "Downloading and compiling FFmpeg ${FFMPEG_VERSION} from official source..."
    download_if_missing "${FFMPEG_FILENAME}" "${FFMPEG_URL}"
    verify_checksum "${FFMPEG_FILENAME}" "${FFMPEG_MD5SUM}"

    if [ ! -d "ffmpeg-${FFMPEG_VERSION}" ]; then
        log "Extracting FFmpeg..."
        tar -xf "${FFMPEG_FILENAME}"
    fi
    cd "ffmpeg-${FFMPEG_VERSION}"

    # --- FFMPEG SOURCE PATCHING (if patch exists) ---
    FFMPEG_PATCH_FILE="${SCRIPT_DIR}/patch/ffmpeg-decklink-sdk15-compat.patch"
    if [ -f "${FFMPEG_PATCH_FILE}" ]; then
        log "Applying DeckLink SDK 15.0 compatibility patch to FFmpeg..."
        log "Found patch file at: ${FFMPEG_PATCH_FILE}"
        patch -p1 < "${FFMPEG_PATCH_FILE}"
        log "Patch applied successfully."
    else
        log "No DeckLink compatibility patch found. Continuing without patch."
        log "Note: This may cause issues with DeckLink SDK 15.0. Consider using the full installer."
    fi
    # --- END FFMPEG PATCHING ---

    log "Configuring FFmpeg ${FFMPEG_VERSION} build (ALSA + DeckLink focus)..."
    PKG_CONFIG_PATH="/usr/lib64/pkgconfig:/usr/lib/pkgconfig:${PKG_CONFIG_PATH}" ./configure --prefix=/usr \
        --libdir=/usr/lib64 \
        --shlibdir=/usr/lib64 \
        --disable-debug \
        --enable-shared \
        --enable-gpl \
        --enable-nonfree \
        --enable-decklink \
        --enable-alsa \
        --enable-pic \
        --enable-runtime-cpudetect

    log "Compiling FFmpeg ${FFMPEG_VERSION} (this may take a while)..."
    if ! make -j$(nproc); then 
        log "ERROR: FFmpeg compilation failed!"
        exit 1
    fi
    
    log "Installing FFmpeg ${FFMPEG_VERSION}..."
    if ! run_sudo make install; then 
        log "ERROR: FFmpeg installation failed!"
        exit 1
    fi

    log "Cleaning up and finalizing installation..."
    run_sudo ldconfig
    run_sudo updatedb
    set_status_flag "ffmpeg_alsa" "${FFMPEG_VERSION}"

    log "========================================================================"
    log "      Installation finished successfully!"
    log "      FFmpeg ${FFMPEG_VERSION} with DeckLink ${DECKLINK_SDK_VERSION} and ALSA support is ready."
    log "      Sources are located in '${SOURCE_DIR}'."
    log "========================================================================"
fi

log "Verifying FFmpeg installation..."
if /usr/bin/ffmpeg -version | head -1; then
    log "ALSA devices (if any):"
    /usr/bin/ffmpeg -sources alsa 2>&1 | grep -E "(card|device)" || log "No ALSA devices found or not properly configured."
    log "DeckLink devices (if any):"
    /usr/bin/ffmpeg -sources decklink 2>&1 | grep -E "(decklink|Blackmagic)" || log "No DeckLink devices found or driver not loaded."
else
    log "WARNING: FFmpeg installation may have issues"
fi

if ! ask_keep_sourcedir; then
    log "Deleting sourcedir and placeholder files as requested (status flags preserved)."
    find "${SOURCE_DIR}" -mindepth 1 -maxdepth 1 ! -name ".install_status" -exec rm -rf {} +
else
    log "Keeping sourcedir and placeholder files as requested."
fi

log "Script completed successfully."
exit 0
