#!/usr/bin/env bash
################################################################################
# Script: install-ffmpeg.sh
# Description: Installs FFmpeg with DeckLink, NVIDIA GPU, and other support.
# Revision: 3.0
# Date: 2025-06-21
#
# This script installs FFmpeg from source with support for multiple hardware
# acceleration and library options on Rocky Linux 9. It is idempotent,
# using granular status flags to avoid re-running completed steps.
################################################################################

# --- Configuration ---
set -e

# Software Versions
FFMPEG_VERSION="7.1.1"
DECKLINK_SDK_VERSION="14.4.1"
NVIDIA_CUDA_VERSION="12.9.1"

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

NVIDIA_CUDA_URL="https://developer.download.nvidia.com/compute/cuda/12.9.1/local_installers/cuda-repo-rhel9-12-9-local-12.9.1_575.57.08-1.x86_64.rpm"
NVIDIA_CUDA_RPM_FILENAME="cuda-repo-rhel9-local.rpm"
NVIDIA_CUDA_MD5SUM="419434bd6c568133da5421db0ff7f0b2"

# Directories
SOURCE_DIR="${HOME}/ffmpeg_sources"
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

log "Script started. This will install FFmpeg and many dependencies."

# Check for --force flag
if [[ "$1" == "--force" ]]; then
    log "Force mode enabled. Cleaning up previous installation."
    rm -rf "${SOURCE_DIR}"
fi

# Check for final completion flag
if is_installed "ffmpeg" "${FFMPEG_VERSION}"; then
    log "FFmpeg ${FFMPEG_VERSION} is already fully installed."
    log "Use './install-ffmpeg.sh --force' to re-install from scratch."
    exit 0
fi

# 1. Prepare Environment
log "Preparing source directory at ${SOURCE_DIR}"
mkdir -p "${SOURCE_DIR}"
mkdir -p "${STATUS_DIR}"
cd "${SOURCE_DIR}"

# 2. Install Prerequisites
if ! is_installed "prerequisites" "1.0"; then
    log "Installing prerequisite packages..."
    dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
    /usr/bin/crb enable
    dnf -y groupinstall "Development Tools"
    dnf -y install \
        AMF-devel autoconf automake clang cmake dkms elfutils-libelf-devel glibc \
        intel-gmmlib-devel intel-mediasdk-devel lame-devel libass-devel libdrm-devel \
        libogg-devel libpciaccess-devel libssh-devel libtool libva-devel libva-utils \
        libvorbis-devel libvpl-devel libvpx-devel libX11-devel mercurial mlocate nasm \
        mesa-libGL-devel mesa-libEGL-devel vulkan-headers valgrind-devel \
        numactl-devel numactl-libs ocl-icd-devel opencl-headers openh264-devel \
        openjpeg2-devel openssl-devel opus-devel perl-devel pkgconf-pkg-config \
        SDL2-devel srt-devel texinfo wget xorg-x11-server-devel \
        xwayland-devel yasm zlib-devel kernel-devel
    set_status_flag "prerequisites" "1.0"
fi

# 3. Install External Libraries from Source
log "Installing external libraries from source..."

if ! is_installed "ffnvcodec-headers" "git"; then
    log "Installing 'ffnvcodec-headers'..."
    if [ ! -d "nv-codec-headers" ]; then git clone https://git.videolan.org/git/ffmpeg/nv-codec-headers.git; fi
    cd nv-codec-headers && git pull
    make PREFIX=/usr && make PREFIX=/usr install
    cd "${SOURCE_DIR}"
    set_status_flag "ffnvcodec-headers" "git"
fi

if ! is_installed "libx264" "git"; then
    log "Installing 'libx264'..."
    if [ ! -d "x264" ]; then git clone https://code.videolan.org/videolan/x264.git; fi
    cd x264 && git pull
    ./configure --prefix=/usr --libdir=/usr/lib64 --disable-avs --enable-lto --enable-pic --enable-shared
    make -j$(nproc) && make install
    cd "${SOURCE_DIR}"
    set_status_flag "libx264" "git"
fi

if ! is_installed "libx265" "git"; then
    log "Installing 'libx265'..."
    if [ ! -d "x265_git" ]; then git clone https://bitbucket.org/multicoreware/x265_git; fi
    cd x265_git && git pull
    cd build/linux
    cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX=/usr -DENABLE_SHARED:bool=on ../../source
    make -j$(nproc) && make install
    cd "${SOURCE_DIR}"
    set_status_flag "libx265" "git"
fi

if ! is_installed "libsrt" "git"; then
    log "Installing 'libsrt' from source..."
    if [ ! -d "srt" ]; then git clone https://github.com/Haivision/srt.git; fi
    cd srt && git pull
    rm -rf build && mkdir build && cd build
    cmake .. -DCMAKE_INSTALL_PREFIX=/usr -DENABLE_SHARED:bool=on
    make -j$(nproc) && make install
    cd "${SOURCE_DIR}"
    set_status_flag "libsrt" "git"
fi

if ! is_installed "libzvbi" "0.2.35"; then
    log "Installing 'libzvbi' (Teletext)..."
    download_if_missing "zvbi-0.2.35.tar.bz2" "https://sourceforge.net/projects/zapping/files/zvbi/0.2.35/zvbi-0.2.35.tar.bz2/download"
    if [ ! -d "zvbi-0.2.35" ]; then tar -xf "zvbi-0.2.35.tar.bz2"; fi
    cd zvbi-0.2.35
    ./configure --prefix=/usr --sbindir=/usr/bin
    make -j$(nproc) && make install
    cd "${SOURCE_DIR}"
    set_status_flag "libzvbi" "0.2.35"
fi

if ! is_installed "libklvanc" "git"; then
    log "Installing 'libklvanc' (VANC SMPTE2038)..."
    if [ ! -d "libklvanc" ]; then git clone https://github.com/stoth68000/libklvanc.git; fi
    cd libklvanc && git pull
    ./autogen.sh --build
    ./configure --prefix=/usr --libdir=/usr/lib64
    make -j$(nproc) && make install
    cd "${SOURCE_DIR}"
    set_status_flag "libklvanc" "git"
fi

# 4. Install NVIDIA CUDA Toolkit
if ! is_installed "cuda_toolkit" "${NVIDIA_CUDA_VERSION}"; then
    log "Installing NVIDIA CUDA Toolkit..."
    download_if_missing "${NVIDIA_CUDA_RPM_FILENAME}" "${NVIDIA_CUDA_URL}"
    verify_checksum "${NVIDIA_CUDA_RPM_FILENAME}" "${NVIDIA_CUDA_MD5SUM}"
    if ! rpm -q cuda-repo-rhel9-12-9-local > /dev/null; then
        dnf -y localinstall "${NVIDIA_CUDA_RPM_FILENAME}"
    fi
    dnf clean all && dnf -y install cuda-toolkit
    set_status_flag "cuda_toolkit" "${NVIDIA_CUDA_VERSION}"
fi

# 5. Install Decklink SDK and Drivers
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

# 6. Download and Compile FFmpeg
log "Downloading and compiling FFmpeg from official source..."
download_if_missing "${FFMPEG_FILENAME}" "${FFMPEG_URL}"
verify_checksum "${FFMPEG_FILENAME}" "${FFMPEG_MD5SUM}"

if [ ! -d "ffmpeg-${FFMPEG_VERSION}" ]; then
    log "Extracting FFmpeg..."
    tar -xf "${FFMPEG_FILENAME}"
fi
cd "ffmpeg-${FFMPEG_VERSION}"

log "Configuring FFmpeg build..."
PKG_CONFIG_PATH="/usr/lib64/pkgconfig:/usr/lib/pkgconfig:${PKG_CONFIG_PATH}" ./configure --prefix=/usr \
    --libdir=/usr/lib64 \
    --shlibdir=/usr/lib64 \
    --disable-debug \
    --enable-shared \
    --enable-gpl \
    --enable-nonfree \
    --enable-decklink \
    --enable-libklvanc \
    --enable-libzvbi \
    --enable-libdrm \
    --enable-libopenh264 \
    --enable-libopenjpeg \
    --enable-libsrt \
    --enable-libssh \
    --enable-libvpl \
    --enable-libx264 \
    --enable-libx265 \
    --enable-nvdec \
    --enable-nvenc \
    --enable-opencl \
    --enable-openssl \
    --enable-pic \
    --enable-runtime-cpudetect \
    --enable-vaapi

log "Compiling FFmpeg (this may take a while)..."
make -j$(nproc) && make install

# --- Finalization ---
log "Cleaning up and finalizing installation..."
ldconfig
updatedb
set_status_flag "ffmpeg" "${FFMPEG_VERSION}"

log "========================================================================"
log "      Installation finished successfully!"
log "      FFmpeg ${FFMPEG_VERSION} with DeckLink and NVIDIA support is ready."
log "      Sources are located in '${SOURCE_DIR}'."
log "========================================================================"

exit 0
