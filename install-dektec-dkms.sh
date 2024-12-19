#!/usr/bin/env bash
# Author: Nikos Toutountzoglou, nikos.toutountzoglou@svt.se
# Upstream link: https://www.dektec.com/downloads/SDK/#linux
# Script: install-dektec-dkms.sh
# Description: Install dektec Linux DKMS for Dektec device drivers
# Revision: 1.3

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

# Function to install prerequisites
install_prerequisites() {
    info "Enabling Extra Packages for Enterprise Linux 9 and Development Tools."
    sudo dnf install -y epel-release
    sudo /usr/bin/crb enable
    sudo dnf groupinstall -y "Development Tools"
    sudo dnf makecache

    info "Installing DKMS and kernel headers."
    sudo dnf install -y dkms kernel-headers-$(uname -r)
}

# Function to download and verify dektec source
download_and_verify() {
    info "Downloading 'dektec-dkms' from upstream source."
    curl -fSL -o "LinuxSDK_v${PKGVER}.tar.gz" "${DEKTEC_DKMS_VER}"

    echo "${DEKTEC_DKMS_MD5} LinuxSDK_v${PKGVER}.tar.gz" | md5sum -c || {
        error "Checksum verification failed. Exiting."
        exit 1
    }
}

# Function to install dektec drivers
install_dektec_drivers() {
    info "Installing 'dektec-dkms' via testing, building, and installing DKMS package."
    tar -xf "LinuxSDK_v${PKGVER}.tar.gz"
    cd LinuxSDK/Drivers/
    sudo ./Install
    sudo ./Install -t
}

# Function to display final steps
display_final_steps() {
    info "All done. Downloaded sources are stored in folder '${WORKDIR}'."
    info "If SecureBoot is enabled, you will need the following steps:
1. Type 'mokutil --import /var/lib/dkms/mok.pub'
2. You'll be prompted to create a password. Enter it twice.
3. Reboot the computer. At boot you'll see the MOK Manager EFI interface
4. Press any key to enter it, then select 'Enroll MOK'
5. Then select 'Continue'
6. And confirm with 'Yes' when prompted
7. After this, enter the password you set up with 'mokutil --import' in the previous step
8. At this point you are done, select 'OK' and the computer will reboot trusting the key for your modules
9. After reboot, you can inspect the MOK certificates with the following command 'mokutil --list-enrolled | grep DKMS'"
}

# Main function
main() {
    info "Script execution started."

    # Variables
    WORKDIR="$HOME/src/release/dektec"
    PKGNAME="dektec-dkms"
    PKGVER="2024.11.0"
    DEKTEC_DKMS_VER="https://www.dektec.com/products/SDK/DTAPI/Downloads/LinuxSDK_v${PKGVER}.tar.gz"
    DEKTEC_DKMS_MD5="3e9b70ed0ed71ef244d7c3a6500f6aba"

    check_distro
    prompt_user "Install dektec Linux DKMS for Dektec device drivers?"
    prepare_workdir
    install_prerequisites
    download_and_verify
    install_dektec_drivers
    display_final_steps

    info "Script execution finished."
}

# Run the main function
main
