#!/usr/bin/env bash
# Script: install-alsa-tools.sh
# Author: nikos.toutountzoglou@svt.se
# Upstream link: https://www.alsa-project.org
# Description: Alsa tools for Rocky Linux 9
# Revision: 1.1

set -euo pipefail
IFS=$'\n\t'

# Color codes
INFO_COLOR="\033[1;34m"   # Blue
WARN_COLOR="\033[1;33m"   # Yellow
ERROR_COLOR="\033[1;31m"  # Red
RESET_COLOR="\033[0m"     # Reset to default

# Function to print INFO messages
info() {
    echo -e "${INFO_COLOR}[INFO] $1${RESET_COLOR}"
}

# Function to print WARN messages
warn() {
    echo -e "${WARN_COLOR}[WARN] $1${RESET_COLOR}"
}

# Function to print ERROR messages
error() {
    echo -e "${ERROR_COLOR}[ERROR] $1${RESET_COLOR}"
}

# Function to check Linux distro
check_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=${ID}
        VERS_ID=${VERSION_ID}
        OS_ID="${VERS_ID:0:1}"
    elif command -v lsb_release &>/dev/null; then
        OS=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
    elif [[ -f /etc/lsb-release ]]; then
        . /etc/lsb-release
        OS=$(echo "${DISTRIB_ID}" | tr '[:upper:]' '[:lower:]')
    elif [[ -f /etc/debian_version ]]; then
        OS=debian
    else
        error "Unknown Linux distro. Exiting!"
        exit 1
    fi

    if [[ "$OS" == "rocky" && "$OS_ID" == "9" ]]; then
        info "Detected 'Rocky Linux 9'. Continuing."
    else
        error "Could not detect 'Rocky Linux 9'. Exiting."
        exit 1
    fi
}

# Function to prompt user
prompt_user() {
    while true; do
        read -r -p "$1 (y/n) " yesno
        case "$yesno" in
            [nN]) exit 0 ;;
            [yY]) break ;;
            *) warn "Please answer 'y/n'." ;;
        esac
    done
}

# Function to prepare working directory
prepare_workdir() {
    if [[ -d "${PKGDIR}" ]]; then
        while true; do
            warn "Source directory '${PKGDIR}' already exists."
            read -r -p "Delete it and reinstall? (y/n) " yesno
            case "$yesno" in
                [nN]) exit 0 ;;
                [yY]) break ;;
                *) warn "Please answer 'y/n'." ;;
            esac
        done
        rm -rf "${PKGDIR}"
    fi

    mkdir -p "${PKGDIR}"
    cd "${PKGDIR}"
}

# Function to install prerequisites
install_prerequisites() {
    info "Enabling Extra Packages for Enterprise Linux 9 and Development Tools."
    sudo dnf install -y epel-release
    sudo /usr/bin/crb enable
    sudo dnf groupinstall -y "Development Tools"
    sudo dnf makecache

    info "Installing necessary packages for building alsa-tools."
    sudo dnf install -y alsa-lib-devel hicolor-icon-theme fltk-devel gtk2-devel gtk3-devel
}

# Function to download and verify source
download_and_verify() {
    info "Downloading latest upstream source."
    curl -fSL -o "${PKGNAME}-${PKGVER}.tar.bz2" "${ATOOLS_PKG}"

    echo "${ATOOLS_MD5} ${PKGNAME}-${PKGVER}.tar.bz2" | md5sum -c || {
        error "Checksum verification failed. Exiting."
        exit 1
    }

    info "Downloaded files have successfully passed MD5 checksum test. Continuing."
    tar -xf "${PKGNAME}-${PKGVER}.tar.bz2"
}

# Function to prepare and build tools
prepare_and_build() {
    cd "${PKGNAME}-${PKGVER}"

    # Uncomment to install more tools
    TOOLS=(
        #as10k1
        #echomixer
        #envy24control
        #hda-verb
        # hdajackretask  # fails to build
        #hdajacksensetest
        #hdspconf
        #hdsploader
        hdspmixer
        #hwmixvolume
        #ld10k1
        #mixartloader
        #pcxhrloader
        # qlo10k1  # disabled, because build is broken
        rmedigicontrol
        #sb16_csp
        #seq/sbiload
        #sscape_ctl
        #vxloader
        #us428control
        #usx2yloader
    )

    info "Preparing package."
    for tool in "${TOOLS[@]}"; do
        (
            cd "${PKGDIR}/${PKGNAME}-${PKGVER}/$tool"
            autoreconf -vfi
        )
    done

    info "Building package."
    for tool in "${TOOLS[@]}"; do
        (
            cd "${PKGDIR}/${PKGNAME}-${PKGVER}/$tool"
            ./configure --prefix=/usr --sbindir=/usr/bin
            make
        )
    done
}

# Function to install tools
install_tools() {
    info "Installing package."
    for tool in "${TOOLS[@]}"; do
        sudo make install -C "${PKGDIR}/${PKGNAME}-${PKGVER}/$tool"
    done
}

# Function to display final steps
display_final_steps() {
    info "Successfully installed alsa tools: ${TOOLS[*]}"
    info "For more information please check: https://www.alsa-project.org"
}

# Main function
main() {
    info "Script execution started."

    # Variables
    PKGDIR="$HOME/src/alsa-tools"
    PKGNAME="alsa-tools"
    PKGVER="1.2.11"
    ATOOLS_PKG="http://www.alsa-project.org/files/pub/tools/${PKGNAME}-${PKGVER}.tar.bz2"
    ATOOLS_MD5="bc5f5e5689f46a9d4a0b85dc6661732c"

    check_distro
    prompt_user "Welcome to alsa-tools installation script. Proceed with installation?"
    prepare_workdir
    install_prerequisites
    download_and_verify
    prepare_and_build
    install_tools
    display_final_steps

    info "Script execution finished."
}

# Run the main function
main
