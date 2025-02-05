#!/usr/bin/env bash
# Author: Nikos Toutountzoglou, nikos.toutountzoglou@svt.se
# Script: install-ffmpeg.sh
# Description: Install ffmpeg with Decklink, Intel QSV, NVIDIA GPU and AMF-AMD GPU support
# Revision: 1.9

# Define color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO] $1${NC}"
}

log_warn() {
    echo -e "${YELLOW}[WARN] $1${NC}"
}

log_error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

# Function to handle errors
handle_error() {
    log_error "An error occurred. Exiting..."
    exit 1
}

# Trap errors and clean up
trap 'handle_error' ERR

# Function to check Linux distro
check_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=${ID}
        VERS_ID=${VERSION_ID}
        OS_ID="${VERS_ID:0:1}"
    elif type lsb_release &>/dev/null; then
        OS=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
    elif [ -f /etc/lsb-release ]; then
        . /etc/lsb-release
        OS=$(echo ${DISTRIB_ID} | tr '[:upper:]' '[:lower:]')
    elif [ -f /etc/debian_version ]; then
        OS=debian
    else
        log_error "Unknown Linux distro. Exiting!"
        exit 1
    fi

    if [ "${OS}" = "rocky" ] && [ "${OS_ID}" = "9" ]; then
        log_info "Detected 'Rocky Linux 9'. Continuing."
    else
        log_error "Could not detect 'Rocky Linux 9'. Exiting."
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

# Function to prepare working directory
prepare_workdir() {
    if [ -d "${WORKDIR}" ]; then
        if confirm "Source directory '${WORKDIR}' already exists. Delete it and reinstall?"; then
            rm -rf "${WORKDIR}"
        else
            exit 0
        fi
    fi
    mkdir -p "${WORKDIR}"
    cd "${WORKDIR}"
}

# Function to download and verify a file
download_and_verify() {
    local url="$1"
    local filename="$2"
    local md5sum="$3"

    log_info "Downloading ${filename}..."
    curl -fSL -o "${filename}" "${url}"

    log_info "Verifying MD5 checksum for ${filename}..."
    echo "${md5sum}  ${filename}" | md5sum -c
}

# Function to extract a tarball
extract_tarball() {
    local filename="$1"
    log_info "Extracting ${filename}..."
    tar -xf "${filename}"
}

# Function to install prerequisites
install_prerequisites() {
    log_info "Enable EPEL, CRB and Development Tools."
    sudo dnf install -y epel-release
    sudo /usr/bin/crb enable
    sudo dnf groupinstall -y "Development Tools"

    log_info "Installing prerequisite packages."
    sudo dnf install -y \
        AMF-devel \
        autoconf \
        automake \
        clang \
        cmake \
        glibc \
        intel-gmmlib-devel \
        intel-mediasdk-devel \
        libass-devel \
        libdrm-devel \
        libogg-devel \
        libpciaccess-devel \
        libssh-devel \
        libtool \
        libva-devel \
        libva-utils \
        libvorbis-devel \
        libvpl-devel \
        libX11-devel \
        mercurial \
        mlocate \
        nasm \
        numactl-devel \
        numactl-libs \
        ocl-icd-devel \
        opencl-headers \
        openh264-devel \
        openjpeg2-devel \
        openssl-devel \
        perl-devel \
        pkgconf-pkg-config \
        SDL2-devel \
        srt \
        srt-devel \
        texinfo \
        xorg-x11-server-devel \
        xwayland-devel \
        yasm \
        zlib-devel
}

# Function to install external libraries
install_external_libraries() {
    log_info "Enable NVIDIA CUDA Toolkit repo."
    if ! dnf list installed cuda-toolkit-12-* &>/dev/null; then
        curl -fSL -o "${CUDA_RPM}" "${CUDA_RPM_URL}"
        sudo dnf install -y "${CUDA_RPM}"
        sudo dnf clean all
        sudo dnf -y install cuda-toolkit-12-6
        sudo ldconfig
    else
        log_info "CUDA Toolkit already enabled, skipping."
    fi

    log_info "Installing 'ffnvcodec-headers'."
    git clone https://git.videolan.org/git/ffmpeg/nv-codec-headers.git
    cd nv-codec-headers
    make PREFIX='/usr'
    sudo make PREFIX='/usr' install
    cd "${WORKDIR}"

    log_info "Installing 'libx264'."
    git clone https://code.videolan.org/videolan/x264.git
    cd x264
    ./configure --prefix='/usr' --libdir='/usr/lib' --disable-avs --enable-lto --enable-pic --enable-shared
    make
    sudo make install
    cd "${WORKDIR}"

    log_info "Installing 'libx265'."
    git clone https://bitbucket.org/multicoreware/x265_git
    cd x265_git/build/linux
    cmake -G "Unix Makefiles" ../../source -DCMAKE_INSTALL_PREFIX=/usr -Wno-dev
    cmake ../../source -DCMAKE_INSTALL_PREFIX=/usr -Wno-dev
    make
    sudo make install
    cd "${WORKDIR}"

    log_info "Installing 'libzvbi' (Teletext)."
    curl -fSL -LO https://sourceforge.net/projects/zapping/files/zvbi/0.2.35/zvbi-0.2.35.tar.bz2
    tar -xf zvbi-0.2.35.tar.bz2
    cd zvbi-0.2.35
    ./configure --prefix='/usr' --sbindir='/usr/bin'
    make
    sudo make install
    cd "${WORKDIR}"

    log_info "Installing 'libklvanc' (VANC SMPTE2038)."
    git clone https://github.com/stoth68000/libklvanc.git
    cd libklvanc
    ./autogen.sh --build
    ./configure --prefix='/usr' --libdir='/usr/lib'
    make
    sudo make install
    cd "${WORKDIR}"
}

# Function to install Decklink SDK and drivers
install_decklink_sdk_and_drivers() {
    log_info "Installing Decklink SDK and drivers..."
    extract_tarball "${DECKLINK_SDK_FILENAME}"

    # Copy SDK headers to /usr/include
    log_info "Copying BlackMagic SDK headers to /usr/include..."
    sudo cp -r "${SOURCE_DIR}/decklink_sdk_drivers/SDK/include" "/usr/include"

    # Install the RPM driver
    log_info "Installing RPM driver: ${DECKLINK_RPM_FILENAME}..."
    sudo dnf install -y "${SOURCE_DIR}/decklink_sdk_drivers/drivers/rpm/x86_64/${DECKLINK_RPM_FILENAME}"

    # Copy License and Documentation files
    log_info "Copying License and Documentation files..."
    sudo mkdir -p "${LICENSE_DIR}"
    sudo mkdir -p "${DOC_DIR}"
    sudo cp "${SOURCE_DIR}/decklink_sdk_drivers/drivers/License.txt" "${LICENSE_DIR}/"
    sudo cp "${SOURCE_DIR}/decklink_sdk_drivers/SDK/Blackmagic DeckLink SDK.pdf" "${DOC_DIR}/"
}

# Function to install ffmpeg
install_ffmpeg() {
    log_info "Installing 'ffmpeg' version ${FFMPEG_VERSION}."
    cd "${FFMPEG_FILENAME%.tar.xz}"
    export PKG_CONFIG_PATH="${PKG_CONFIG_PATH}:/usr/lib/pkgconfig"
    ./configure \
        --prefix='/usr' \
        --disable-debug \
        --disable-htmlpages \
        --enable-amf \
        --enable-decklink \
        --enable-gpl \
        --enable-libdrm \
        --enable-libklvanc \
        --enable-libopenh264 \
        --enable-libopenjpeg \
        --enable-libsrt \
        --enable-libssh \
        --enable-libvpl \
        --enable-libx264 \
        --enable-libx265 \
        --enable-libzvbi \
        --enable-nonfree \
        --enable-nvdec \
        --enable-nvenc \
        --enable-opencl \
        --enable-openssl \
        --enable-pic \
        --enable-runtime-cpudetect \
        --enable-vaapi

    make
    sudo make install
}

# Main script execution
log_info "Script started."

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

CUDA_VER="12.6.3"
CUDA_RPM="cuda-repo-rhel9-12-6-local-${CUDA_VER}_560.35.05-1.x86_64.rpm"
CUDA_RPM_URL="https://developer.download.nvidia.com/compute/cuda/${CUDA_VER}/local_installers/${CUDA_RPM}"

WORKDIR="${HOME}/src/release/rocky9-ffmpeg"

check_distro
if confirm "Install ffmpeg with Decklink, Intel QSV, NVIDIA GPU and AMF-AMD GPU support?"; then
    prepare_workdir
    download_and_verify "${FFMPEG_URL}" "${FFMPEG_FILENAME}" "${FFMPEG_MD5SUM}"
    download_and_verify "${DECKLINK_SDK_URL}" "${DECKLINK_SDK_FILENAME}" "${DECKLINK_SDK_MD5SUM}"
    
    extract_tarball "${FFMPEG_FILENAME}"
    extract_tarball "${DECKLINK_SDK_FILENAME}"
    
    install_prerequisites
    install_external_libraries
    install_decklink_sdk_and_drivers
    install_ffmpeg
    
    log_info "All done. Downloaded sources are stored in folder '${WORKDIR}'."
    sudo ldconfig
    sudo updatedb
    log_info "Script completed."
fi
exit 0
