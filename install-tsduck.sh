#!/usr/bin/env bash
# Author: Nikos Toutountzoglou, nikos.toutountzoglou@svt.se
# Script: install-tsduck.sh
# Description: Install tsduck MPEG Transport Stream Toolkit
# Revision: 1.5

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
    if [[ -d "${WORKDIR}" ]]; then
        while true; do
            warn "Source directory '${WORKDIR}' already exists."
            read -r -p "Delete it and reinstall? (y/n) " yesno
            case "$yesno" in
                [nN]) exit 0 ;;
                [yY]) break ;;
                *) warn "Please answer 'y/n'." ;;
            esac
        done
        rm -rf "${WORKDIR}"
    fi

    mkdir -p "${WORKDIR}"
    cd "${WORKDIR}"
}

# Function to download files
download_files() {
    info "Downloading TSDuck from upstream source."
    curl -fSL -o "${PKGNAME}-${PKGVER}.el9.x86_64.rpm" "${TSDUCK_VER}"

    info "Downloading TSDuck development RPM."
    curl -fSL -o "${PKGNAME}-devel-${PKGVER}.el9.x86_64.rpm" "${TSDUCKDEVEL_VER}"

    info "Downloading TSDuck prerequisites script."
    curl -fSL -o "install-prerequisites.sh" "${PREREQ}"

    info "Downloading TSDuck License."
    curl -fSL -o "LICENSE.txt" "${LICENSE}"
}

# Function to verify checksum
verify_checksum() {
    echo "${TSDUCK_MD5} ${PKGNAME}-${PKGVER}.el9.x86_64.rpm" | md5sum -c || {
        error "Checksum verification failed for TSDuck RPM. Exiting."
        exit 1
    }

    echo "${TSDUCKDEVEL_MD5} ${PKGNAME}-devel-${PKGVER}.el9.x86_64.rpm" | md5sum -c || {
        error "Checksum verification failed for TSDuck development RPM. Exiting."
        exit 1
    }

    info "Downloaded files have successfully passed MD5 checksum test. Continuing."
}

# Function to install prerequisites
install_prerequisites() {
    info "Installing prerequisite packages."
    chmod +x install-prerequisites.sh
    ./install-prerequisites.sh
    sudo dnf install -y glibc mlocate
}

# Function to install TSDuck
install_tsduck() {
    info "Installing 'tsduck' via DNF."
    sudo dnf install -y "${PKGNAME}-${PKGVER}.el9.x86_64.rpm"
    sudo dnf install -y "${PKGNAME}-devel-${PKGVER}.el9.x86_64.rpm"
}

# Function to display final steps
display_final_steps() {
    info "All done. Downloaded sources are stored in folder '${WORKDIR}'."
    sudo ldconfig
    sudo updatedb
}

# Main function
main() {
    info "Script execution started."

    # Variables
    WORKDIR="$HOME/src/release/tsduck"
    PKGNAME="tsduck"
    PKGVER="3.39-3956"
    TSDUCK_VER="https://github.com/${PKGNAME}/${PKGNAME}/releases/download/v${PKGVER}/${PKGNAME}-${PKGVER}.el9.x86_64.rpm"
    TSDUCK_MD5="6694b4168c04fcffe0bfb305ff9dcef0"
    TSDUCKDEVEL_VER="https://github.com/${PKGNAME}/${PKGNAME}/releases/download/v${PKGVER}/${PKGNAME}-devel-${PKGVER}.el9.x86_64.rpm"
    TSDUCKDEVEL_MD5="a3b2d123074da731d5f644bd7d8f0c4e"
    PREREQ="https://raw.githubusercontent.com/${PKGNAME}/${PKGNAME}/master/scripts/install-prerequisites.sh"
    LICENSE="https://raw.githubusercontent.com/${PKGNAME}/${PKGNAME}/master/LICENSE.txt"

    check_distro
    prompt_user "Install tsduck MPEG Transport Stream Toolkit?"
    prepare_workdir
    download_files
    verify_checksum
    install_prerequisites
    install_tsduck
    display_final_steps

    info "Script execution finished."
}

# Run the main function
main
