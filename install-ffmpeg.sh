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

# Function to prompt user
prompt_user() {
    while true; do
        read -r -p "Install ffmpeg with Decklink, Intel QSV, NVIDIA GPU and AMF-AMD GPU support? (y/n) " yesno
        case "${yesno}" in
            n | N) exit 0 ;;
            y | Y) break ;;
            *) log_warn "Please answer 'y/n'." ;;
        esac
    done
}

# Function to prepare working directory
prepare_workdir() {
    if [ -d "${WORKDIR}" ]; then
        while true; do
            log_warn "Source directory '${WORKDIR}' already exists."
            read -r -p "Delete it and reinstall? (y/n) " yesno
            case "${yesno}" in
                n | N) exit 0 ;;
                y | Y) break ;;
                *) log_warn "Please answer 'y/n'." ;;
            esac
        done
    fi

    rm -rf "${WORKDIR}"
    mkdir -p "${WORKDIR}"
    cd "${WORKDIR}"
}

# Function to download sources
download_sources() {
    log_info "Downloading FFmpeg from upstream source."
    curl -fSL -o "${PKGNAME}-n${PKGVER}.tar.gz" "${FFMPEG_VER}"

    log_info "Downloading Decklink Drivers v${BM_DRV_VER} and SDK v${BM_SDK_VER}."
    curl -fSL -o decklink_sdk.tar.gz "${BM_SDK}"
    curl -fSL -o decklink.tar.gz "${BM_DRV}"

    log_info "Checking MD5 checksums."
    echo "${FFMPEG_MD5} ${PKGNAME}-n${PKGVER}.tar.gz" | md5sum -c &&
    echo "${BM_SDK_MD5} decklink_sdk.tar.gz" | md5sum -c &&
    echo "${BM_DRV_MD5} decklink.tar.gz" | md5sum -c || exit 1

    log_info "Downloaded files have successfully passed MD5 checksum test. Continuing."
}

# Function to extract sources
extract_sources() {
    log_info "Extracting file '${PKGNAME}-n${PKGVER}.tar.gz'"
    tar -xf "${PKGNAME}-n${PKGVER}.tar.gz"
    log_info "Extracting files 'decklink_sdk.tar.gz' and 'decklink.tar.gz'"
    tar -xf decklink_sdk.tar.gz
    tar -xf decklink.tar.gz
}

# Function to install prerequisites
install_prerequisites() {
    log_info "Enable EPEL, CRB and Development Tools."
    sudo dnf install -y epel-release
    sudo /usr/bin/crb enable
    sudo dnf groupinstall -y "Development Tools"
    sudo dnf makecache

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

# Function to install Decklink SDK
install_decklink_sdk() {
    log_info "Installing Decklink SDK libraries."
    sudo cp -v -r --no-preserve='ownership' "Blackmagic_DeckLink_SDK_${BM_SDK_VER}/Linux/include"/* /usr/include
    log_info "Installing Decklink 'DeviceConfigure' binary in '/usr/local/bin' folder."
    sudo cp -v --no-preserve='ownership' "Blackmagic_DeckLink_SDK_${BM_SDK_VER}/Linux/Samples/bin/x86_64/DeviceConfigure" /usr/local/bin
}

# Function to install Decklink drivers
install_decklink_drivers() {
    log_info "Installing Decklink drivers via RPM package."
    sudo dnf install -y dkms kernel-headers-$(uname -r)
    sudo dnf install -y "Blackmagic_Desktop_Video_Linux_${BM_DRV_VER}/rpm/x86_64/desktopvideo-${BM_DRV_VER}*.rpm"
    log_warn "Make sure to import 'mokutil key' in UEFI systems with Secure Boot enabled."
}

# Function to install ffmpeg
install_ffmpeg() {
    log_info "Installing 'ffmpeg' version ${PKGVER}."
    cd "${PKGNAME}-n${PKGVER}"
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
WORKDIR="${HOME}/src/release/rocky9-ffmpeg"
PKGNAME="FFmpeg"
PKGVER="7.1"
FFMPEG_VER="https://github.com/${PKGNAME}/${PKGNAME}/archive/refs/tags/n${PKGVER}.tar.gz"
FFMPEG_MD5="03485098fb64a000a4f7cd97e468dfff"
BM_SDK="https://drive.usercontent.google.com/download?id=11LUclY1tBLfkAGvu93PaxVpZEmyoKVTE&confirm=y"
BM_SDK_MD5="8d6d32e917d1ea420ecbb2cb7e5fb68f"
BM_SDK_VER="14.2"
BM_DRV="https://drive.usercontent.google.com/download?id=1YY-b4OD5llO1Phd3EJk7MPPapmO8WW9J&confirm=y"
BM_DRV_MD5="8de96c536c81186d5eb96f7a7a54d33f"
BM_DRV_VER="14.3"
CUDA_VER="12.6.3"
CUDA_RPM="cuda-repo-rhel9-12-6-local-${CUDA_VER}_560.35.05-1.x86_64.rpm"
CUDA_RPM_URL="https://developer.download.nvidia.com/compute/cuda/${CUDA_VER}/local_installers/${CUDA_RPM}"

check_distro
prompt_user
prepare_workdir
download_sources
extract_sources
install_prerequisites
install_external_libraries
install_decklink_sdk
install_decklink_drivers
install_ffmpeg

log_info "All done. Downloaded sources are stored in folder '${WORKDIR}'."
sudo ldconfig
sudo updatedb
log_info "Script completed."
exit 0
