#!/usr/bin/env bash
################################################################################
# Script: install-ffmpeg.sh
# Description: Installs FFmpeg with DeckLink, NVIDIA GPU, and other support.
# Revision: 3.2
# Date: 2025-09-04
# Updated for: DeckLink SDK 15.0, FFmpeg 8.0, and Rocky Linux 9.6
#              - Includes FFmpeg source patch for SDK 15.0 compatibility.
#              - Looks for patch file in the 'patch' subdirectory.
#              - Updated all checksums and versions.
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
NVIDIA_CUDA_VERSION="12.9.1"

# URLs and Checksums
FFMPEG_URL="https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz"
FFMPEG_FILENAME="ffmpeg-${FFMPEG_VERSION}.tar.xz"
FFMPEG_MD5SUM="2c91c725fb1b393618554ff429e4ae43"

DECKLINK_SDK_URL="https://drive.usercontent.google.com/download?id=1UvOe7UnwgJMTCDvZZwrwxvWtE9CeepWS&confirm=y"
DECKLINK_SDK_FILENAME="decklink_sdk_drivers.tar.gz"
DECKLINK_SDK_MD5SUM="ef3000b4b0aa0d50ec391cece9ff12e1"

DECKLINK_RPM_FILENAME_15="desktopvideo-15.0a62.x86_64.rpm"

NVIDIA_CUDA_URL="https://developer.download.nvidia.com/compute/cuda/12.9.1/local_installers/cuda-repo-rhel9-12-9-local-12.9.1_575.57.08-1.x86_64.rpm"
NVIDIA_CUDA_RPM_FILENAME="cuda-repo-rhel9-local.rpm"
NVIDIA_CUDA_MD5SUM="419434bd6c568133da5421db0ff7f0b2"

# Directories in the user's home
SOURCE_DIR="${USER_HOME}/ffmpeg_sources"
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

check_cuda_installed() {
    if command -v nvcc >/dev/null 2>&1; then
        nvcc --version | grep "release" | sed -E 's/.*release ([0-9.]+).*/\1/' | head -1
        return 0
    elif [ -x "/usr/local/cuda/bin/nvcc" ]; then
        /usr/local/cuda/bin/nvcc --version | grep "release" | sed -E 's/.*release ([0-9.]+).*/\1/' | head -1
        return 0
    else
        return 1
    fi
}

run_sudo() {
    # Run a command with sudo, prompting password if needed
    sudo "$@"
}

log "Script started. This will install FFmpeg ${FFMPEG_VERSION} with DeckLink ${DECKLINK_SDK_VERSION} and NVIDIA support."

if [[ "$1" == "--force" ]]; then
    log "Force mode enabled. Cleaning up previous installation."
    rm -rf "${SOURCE_DIR}"
fi

log "Preparing source directory at ${SOURCE_DIR}"
mkdir -p "${SOURCE_DIR}"
mkdir -p "${STATUS_DIR}"
cd "${SOURCE_DIR}"

# 1. Prerequisites
if is_installed "prerequisites" "1.0"; then
    if ask_reinstall_component "prerequisites" "1.0"; then
        log "Re-installing prerequisites as requested."
        rm -f "${STATUS_DIR}/prerequisites"
    else
        log "Skipping prerequisites."
    fi
fi
if ! is_installed "prerequisites" "1.0"; then
    log "Installing prerequisite packages..."
    run_sudo dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
    run_sudo /usr/bin/crb enable
    run_sudo dnf -y groupinstall "Development Tools"
    run_sudo dnf -y install \
        AMF-devel autoconf automake clang cmake dkms elfutils-libelf-devel glibc \
        intel-gmmlib-devel intel-mediasdk-devel lame-devel libass-devel libdrm-devel \
        libogg-devel libpciaccess-devel libssh-devel libtool libva-devel libva-utils \
        libvorbis-devel libvpl-devel libvpx-devel libX11-devel mercurial mlocate nasm \
        mesa-libGL-devel mesa-libEGL-devel vulkan-headers valgrind-devel \
        numactl-devel numactl-libs ocl-icd-devel opencl-headers openh264-devel \
        openjpeg2-devel openssl-devel opus-devel perl-devel pkgconf-pkg-config \
        SDL2-devel srt-devel texinfo wget xorg-x11-server-devel \
        xwayland-devel yasm zlib-devel kernel-devel patch
    set_status_flag "prerequisites" "1.0"
fi

# 2. External Libraries from Source

# ffnvcodec-headers
if is_installed "ffnvcodec-headers" "git"; then
    if ask_reinstall_component "ffnvcodec-headers" "git"; then
        rm -f "${STATUS_DIR}/ffnvcodec-headers"
        rm -rf nv-codec-headers
    else
        log "Skipping ffnvcodec-headers."
    fi
fi
if ! is_installed "ffnvcodec-headers" "git"; then
    log "Installing 'ffnvcodec-headers'..."
    if [ ! -d "nv-codec-headers" ]; then git clone https://git.videolan.org/git/ffmpeg/nv-codec-headers.git; fi
    cd nv-codec-headers && git pull
    make PREFIX=/usr && run_sudo make PREFIX=/usr install
    cd "${SOURCE_DIR}"
    set_status_flag "ffnvcodec-headers" "git"
fi

# libx264
if is_installed "libx264" "git"; then
    if ask_reinstall_component "libx264" "git"; then
        rm -f "${STATUS_DIR}/libx264"
        rm -rf x264
    else
        log "Skipping libx264."
    fi
fi
if ! is_installed "libx264" "git"; then
    log "Installing 'libx264'..."
    if [ ! -d "x264" ]; then git clone https://code.videolan.org/videolan/x264.git; fi
    cd x264 && git pull
    ./configure --prefix=/usr --libdir=/usr/lib64 --disable-avs --enable-lto --enable-pic --enable-shared
    make -j$(nproc) && run_sudo make install
    cd "${SOURCE_DIR}"
    set_status_flag "libx264" "git"
fi

# libx265
if is_installed "libx265" "git"; then
    if ask_reinstall_component "libx265" "git"; then
        rm -f "${STATUS_DIR}/libx265"
        rm -rf x265_git
    else
        log "Skipping libx265."
    fi
fi
if ! is_installed "libx265" "git"; then
    log "Installing 'libx265'..."
    if [ ! -d "x265_git" ]; then git clone https://bitbucket.org/multicoreware/x265_git; fi
    cd x265_git && git pull
    cd build/linux
    cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX=/usr -DENABLE_SHARED:bool=on ../../source
    make -j$(nproc) && run_sudo make install
    cd "${SOURCE_DIR}"
    set_status_flag "libx265" "git"
fi

# libsrt
if is_installed "libsrt" "git"; then
    if ask_reinstall_component "libsrt" "git"; then
        rm -f "${STATUS_DIR}/libsrt"
        rm -rf srt
    else
        log "Skipping libsrt."
    fi
fi
if ! is_installed "libsrt" "git"; then
    log "Installing 'libsrt' from source..."
    if [ ! -d "srt" ]; then git clone https://github.com/Haivision/srt.git; fi
    cd srt && git pull
    rm -rf build && mkdir build && cd build
    cmake .. -DCMAKE_INSTALL_PREFIX=/usr -DENABLE_SHARED:bool=on
    make -j$(nproc) && run_sudo make install
    cd "${SOURCE_DIR}"
    set_status_flag "libsrt" "git"
fi

# libzvbi
if is_installed "libzvbi" "0.2.35"; then
    if ask_reinstall_component "libzvbi" "0.2.35"; then
        rm -f "${STATUS_DIR}/libzvbi"
        rm -rf zvbi-0.2.35
    else
        log "Skipping libzvbi."
    fi
fi
if ! is_installed "libzvbi" "0.2.35"; then
    log "Installing 'libzvbi' (Teletext)..."
    download_if_missing "zvbi-0.2.35.tar.bz2" "https://sourceforge.net/projects/zapping/files/zvbi/0.2.35/zvbi-0.2.35.tar.bz2/download"
    if [ ! -d "zvbi-0.2.35" ]; then tar -xf "zvbi-0.2.35.tar.bz2"; fi
    cd zvbi-0.2.35
    ./configure --prefix=/usr --sbindir=/usr/bin
    make -j$(nproc) && run_sudo make install
    cd "${SOURCE_DIR}"
    set_status_flag "libzvbi" "0.2.35"
fi

# libklvanc
if is_installed "libklvanc" "git"; then
    if ask_reinstall_component "libklvanc" "git"; then
        rm -f "${STATUS_DIR}/libklvanc"
        rm -rf libklvanc
    else
        log "Skipping libklvanc."
    fi
fi
if ! is_installed "libklvanc" "git"; then
    log "Installing 'libklvanc' (VANC SMPTE2038)..."
    if [ ! -d "libklvanc" ]; then git clone https://github.com/stoth68000/libklvanc.git; fi
    cd libklvanc && git pull
    ./autogen.sh --build
    ./configure --prefix=/usr --libdir=/usr/lib64
    make -j$(nproc) && run_sudo make install
    cd "${SOURCE_DIR}"
    set_status_flag "libklvanc" "git"
fi

# 3. NVIDIA CUDA Toolkit
cuda_installed_version=$(check_cuda_installed || echo "")
if [ -n "$cuda_installed_version" ]; then
    log "CUDA detected: version $cuda_installed_version"
    if [ "$cuda_installed_version" = "$NVIDIA_CUDA_VERSION" ]; then
        if ask_reinstall_component "CUDA Toolkit" "$cuda_installed_version"; then
            log "Reinstalling CUDA as requested."
            rm -f "${STATUS_DIR}/cuda_toolkit"
        else
            set_status_flag "cuda_toolkit" "${NVIDIA_CUDA_VERSION}"
        fi
    else
        log "CUDA version mismatch, will attempt install/upgrade."
        rm -f "${STATUS_DIR}/cuda_toolkit"
    fi
fi

if ! is_installed "cuda_toolkit" "${NVIDIA_CUDA_VERSION}"; then
    log "Installing NVIDIA CUDA Toolkit..."
    if [ ! -f "${NVIDIA_CUDA_RPM_FILENAME}" ]; then
        download_if_missing "${NVIDIA_CUDA_RPM_FILENAME}" "${NVIDIA_CUDA_URL}"
        verify_checksum "${NVIDIA_CUDA_RPM_FILENAME}" "${NVIDIA_CUDA_MD5SUM}"
    fi
    if ! rpm -q cuda-repo-rhel9-12-9-local > /dev/null; then
        if ask_force_install "NVIDIA CUDA"; then
            run_sudo dnf -y localinstall --allowerasing "${NVIDIA_CUDA_RPM_FILENAME}"
        else
            run_sudo dnf -y localinstall "${NVIDIA_CUDA_RPM_FILENAME}"
        fi
    fi
    run_sudo dnf clean all && run_sudo dnf -y install cuda-toolkit
    set_status_flag "cuda_toolkit" "${NVIDIA_CUDA_VERSION}"
fi

# 4. Decklink SDK and Drivers
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

# 5. Download and Compile FFmpeg
ffmpeg_installed_and_skipped=0
if is_installed "ffmpeg" "${FFMPEG_VERSION}"; then
    if ask_reinstall_component "ffmpeg" "${FFMPEG_VERSION}"; then
        rm -f "${STATUS_DIR}/ffmpeg"
        rm -rf "ffmpeg-${FFMPEG_VERSION}"
    else
        log "FFmpeg ${FFMPEG_VERSION} is already fully installed."
        log "Use './install-ffmpeg.sh --force' to re-install from scratch."
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

    # --- FFMPEG SOURCE PATCHING ---
    log "Applying DeckLink SDK 15.0 compatibility patch to FFmpeg..."
    FFMPEG_PATCH_FILE="${SCRIPT_DIR}/patch/ffmpeg-decklink-sdk15-compat.patch"
    if [ -f "${FFMPEG_PATCH_FILE}" ]; then
        log "Found patch file at: ${FFMPEG_PATCH_FILE}"
        patch -p1 < "${FFMPEG_PATCH_FILE}"
        log "Patch applied successfully."
    else
        log "ERROR: FFmpeg patch file not found at ${FFMPEG_PATCH_FILE}"
        log "Please ensure the patch directory exists and contains the required patch file."
        exit 1
    fi
    # --- END FFMPEG PATCHING ---

    log "Configuring FFmpeg ${FFMPEG_VERSION} build..."
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
    set_status_flag "ffmpeg" "${FFMPEG_VERSION}"

    log "========================================================================"
    log "      Installation finished successfully!"
    log "      FFmpeg ${FFMPEG_VERSION} with DeckLink ${DECKLINK_SDK_VERSION} and NVIDIA support is ready."
    log "      Sources are located in '${SOURCE_DIR}'."
    log "========================================================================"
fi

log "Verifying FFmpeg installation..."
if /usr/bin/ffmpeg -version | head -1; then
    log "DeckLink devices (if any):"
    /usr/bin/ffmpeg -f decklink -list_devices 1 -i dummy 2>&1 | grep -E "(decklink|Blackmagic)" || log "No DeckLink devices found or driver not loaded."
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
