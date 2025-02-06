#!/usr/bin/env bash
################################################################################
# Script: install-ffmpeg.sh
# Author: Nikos Toutountzoglou, nikos.toutountzoglou@svt.se
# Description: Install ffmpeg with Decklink, Intel QSV, NVIDIA GPU and AMF-AMD GPU support
# Revision: 2.0
# Date: 2025-02-06
#
# This script installs ffmpeg with support for multiple hardware acceleration
# and library options. It includes installation of dependencies, external libraries,
# Decklink SDK, and ffmpeg itself.
#
# Requirements:
# - Rocky Linux 9
#
# Usage:
# Run the script and follow the prompts.
# Ensure you have sudo privileges for installation of packages and libraries.
################################################################################

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

SOURCE_DIR="${HOME}/ffmpeg_decklink_sources"

LICENSE_DIR="/usr/share/licenses/decklink"
DOC_DIR="/usr/share/doc/decklink"

CUDA_VER="12.6.3"
CUDA_RPM="cuda-repo-rhel9-12-6-local-${CUDA_VER}_560.35.05-1.x86_64.rpm"
CUDA_RPM_URL="https://developer.download.nvidia.com/compute/cuda/${CUDA_VER}/local_installers/${CUDA_RPM}"

# Function to log messages
log() {
    echo "[LOG] $1"
}

# Function to handle errors
handle_error() {
    log "An error occurred. Exiting..."
    exit 1
}

# Trap errors and clean up
trap 'handle_error' ERR

# Function to check Linux distro
check_distro() {
    if grep -q "Rocky Linux 9" /etc/os-release; then
        log "Detected 'Rocky Linux 9'. Continuing."
    else
        log "Could not detect 'Rocky Linux 9'. Exiting."
        exit 1
    fi
}

# Function to prompt user for confirmation
confirm() {
    local prompt="$1"
    local default_response="${2:-y}"
    local response

    read -r -p "${prompt} [Y/n] (default: ${default_response}): " response
    response="${response:-${default_response}}"

    [[ "${response}" =~ ^[Yy]$ ]]
}

# Function to prepare source directory
prepare_sourcedir() {
    if [ -d "${SOURCE_DIR}" ]; then
        if confirm "Source directory '${SOURCE_DIR}' already exists. Delete it and reinstall?"; then
            rm -rf "${SOURCE_DIR}"
        else
            exit 0
        fi
    fi
    mkdir -p "${SOURCE_DIR}"
    cd "${SOURCE_DIR}"
}

# Function to download a file
download_file() {
    local url="$1"
    local filename="$2"

    log "Downloading ${filename}..."
    curl -# -L -o "${filename}" "${url}"
}

# Function to verify a file checksum
verify_checksum() {
    local filename="$1"
    local md5sum="$2"

    log "Verifying MD5 checksum for ${filename}..."
    echo "${md5sum}  ${filename}" | md5sum -c
}

# Function to extract a tarball
extract_tarball() {
    local filename="$1"
    log "Extracting ${filename}..."
    tar -xf "${filename}"
}

# Function to run dnf commands
dnf_install() {
    sudo dnf install -y "$@"
}

dnf_groupinstall() {
    sudo dnf groupinstall -y "$@"
}

dnf_clean_all() {
    sudo dnf clean all
}

dnf_list_installed() {
    dnf list installed "$@"
}

# Function to install prerequisites
install_prerequisites() {
    log "Enable EPEL, CRB and Development Tools."
    dnf_install epel-release
    sudo /usr/bin/crb enable
    dnf_groupinstall "Development Tools"

    log "Installing prerequisite packages."
    dnf_install AMF-devel autoconf automake clang cmake glibc intel-gmmlib-devel intel-mediasdk-devel \
        libass-devel libdrm-devel libogg-devel libpciaccess-devel libssh-devel libtool libva-devel \
        libva-utils libvorbis-devel libvpl-devel libX11-devel mercurial mlocate nasm numactl-devel \
        numactl-libs ocl-icd-devel opencl-headers openh264-devel openjpeg2-devel openssl-devel \
        perl-devel pkgconf-pkg-config SDL2-devel srt srt-devel texinfo xorg-x11-server-devel \
        xwayland-devel yasm zlib-devel
}

# Function to install external libraries
install_external_libraries() {
    log "Enable NVIDIA CUDA Toolkit repo."
    if ! dnf_list_installed "cuda-toolkit-12-*" &>/dev/null; then
        download_file "${CUDA_RPM_URL}" "${CUDA_RPM}"
        dnf_install "${CUDA_RPM}"
        dnf_clean_all
        dnf_install cuda-toolkit-12-6
        sudo ldconfig
    else
        log "CUDA Toolkit already enabled, skipping."
    fi

    log "Installing 'ffnvcodec-headers'."
    git clone https://git.videolan.org/git/ffmpeg/nv-codec-headers.git
    cd nv-codec-headers
    make PREFIX=/usr
    sudo make PREFIX=/usr install
    cd "${SOURCE_DIR}"

    log "Installing 'libx264'."
    git clone https://code.videolan.org/videolan/x264.git
    cd x264
    ./configure --prefix=/usr --libdir=/usr/lib --disable-avs --enable-lto --enable-pic --enable-shared
    make
    sudo make install
    cd "${SOURCE_DIR}"

    log "Installing 'libx265'."
    git clone https://bitbucket.org/multicoreware/x265_git
    cd x265_git/build/linux
    cmake -G "Unix Makefiles" ../../source -DCMAKE_INSTALL_PREFIX=/usr -Wno-dev
    cmake ../../source -DCMAKE_INSTALL_PREFIX=/usr -Wno-dev
    make
    sudo make install
    cd "${SOURCE_DIR}"

    log "Installing 'libzvbi' (Teletext)."
    download_file "https://sourceforge.net/projects/zapping/files/zvbi/0.2.35/zvbi-0.2.35.tar.bz2" "zvbi-0.2.35.tar.bz2"
    extract_tarball "zvbi-0.2.35.tar.bz2"
    cd zvbi-0.2.35
    ./configure --prefix=/usr --sbindir=/usr/bin
    make
    sudo make install
    cd "${SOURCE_DIR}"

    log "Installing 'libklvanc' (VANC SMPTE2038)."
    git clone https://github.com/stoth68000/libklvanc.git
    cd libklvanc
    ./autogen.sh --build
    ./configure --prefix=/usr --libdir=/usr/lib
    make
    sudo make install
    cd "${SOURCE_DIR}"
}

# Function to install Decklink SDK and drivers
install_decklink_sdk_and_drivers() {
    log "Installing Decklink SDK and drivers..."
    extract_tarball "${DECKLINK_SDK_FILENAME}"

    log "Copying BlackMagic SDK headers to /usr/include..."
    sudo cp -r "${SOURCE_DIR}/decklink_sdk_drivers/SDK/include" /usr/include

    log "Installing RPM driver: ${DECKLINK_RPM_FILENAME}..."
    dnf_install "${SOURCE_DIR}/decklink_sdk_drivers/drivers/rpm/x86_64/${DECKLINK_RPM_FILENAME}"

    log "Copying License and Documentation files..."
    sudo mkdir -p "${LICENSE_DIR}"
    sudo mkdir -p "${DOC_DIR}"
    sudo cp "${SOURCE_DIR}/decklink_sdk_drivers/drivers/License.txt" "${LICENSE_DIR}/"
    sudo cp "${SOURCE_DIR}/decklink_sdk_drivers/SDK/Blackmagic DeckLink SDK.pdf" "${DOC_DIR}/"
}

# Function to install ffmpeg
install_ffmpeg() {
    log "Installing 'ffmpeg' version ${FFMPEG_VERSION}."
    cd "${FFMPEG_FILENAME%.tar.xz}"
    export PKG_CONFIG_PATH="${PKG_CONFIG_PATH}:/usr/lib/pkgconfig"
    ./configure --prefix=/usr --disable-debug --disable-htmlpages --enable-amf \
        --enable-decklink --enable-gpl --enable-libdrm --enable-libklvanc \
        --enable-libopenh264 --enable-libopenjpeg --enable-libsrt --enable-libssh \
        --enable-libvpl --enable-libx264 --enable-libx265 --enable-libzvbi \
        --enable-nonfree --enable-nvdec --enable-nvenc --enable-opencl \
        --enable-openssl --enable-pic --enable-runtime-cpudetect --enable-vaapi
    make
    sudo make install
}

# Main script execution
log "Script started."

check_distro
if confirm "Install ffmpeg with Decklink, Intel QSV, NVIDIA GPU and AMF-AMD GPU support?"; then
    prepare_sourcedir
    download_file "${FFMPEG_URL}" "${FFMPEG_FILENAME}"
    verify_checksum "${FFMPEG_FILENAME}" "${FFMPEG_MD5SUM}"
    download_file "${DECKLINK_SDK_URL}" "${DECKLINK_SDK_FILENAME}"
    verify_checksum "${DECKLINK_SDK_FILENAME}" "${DECKLINK_SDK_MD5SUM}"
    
    extract_tarball "${FFMPEG_FILENAME}"
    extract_tarball "${DECKLINK_SDK_FILENAME}"
    
    install_prerequisites
    install_external_libraries
    install_decklink_sdk_and_drivers
    install_ffmpeg
    
    log "All done. Downloaded sources are stored in '${SOURCE_DIR}'."
    sudo ldconfig
    sudo updatedb
    log "Script completed."
fi
exit 0
