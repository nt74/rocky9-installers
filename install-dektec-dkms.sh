#!/usr/bin/env bash
# Author: Nikos Toutountzoglou, nikos.toutountzoglou@svt.se
# Upstream link: https://www.dektec.com/downloads/SDK/#linux
# Script: install-dektec-dkms.sh
# Description: Install dektec Linux DKMS for Dektec device drivers
# Revision: 1.4
# Updated: 2025-06-21

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

# Function to check if running as root
check_not_root() {
    if [[ $EUID -eq 0 ]]; then
       error "This script should not be run as root. It will use 'sudo' when necessary."
       exit 1
    fi
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
        info "Removing existing working directory: ${WORKDIR}"
        rm -rf "${WORKDIR}"
    fi

    info "Creating working directory: ${WORKDIR}"
    mkdir -p "${WORKDIR}"
    cd "${WORKDIR}"
}

# Function to install prerequisites
install_prerequisites() {
    info "Enabling CRB repository and installing Development Tools."
    sudo dnf install -y epel-release
    sudo /usr/bin/crb enable
    sudo dnf groupinstall -y "Development Tools"
    sudo dnf makecache

    info "Installing DKMS and kernel headers for the current kernel."
    sudo dnf install -y dkms kernel-headers-$(uname -r)
}

# Function to download and verify dektec source
download_and_verify() {
    info "Downloading 'dektec-dkms' from upstream source."
    # Use curl with -L to follow redirects, -f to fail silently on server errors,
    # -S to show errors, and -o to specify output file.
    curl -fSL -o "LinuxSDK_v${PKGVER}.tar.gz" "${DEKTEC_DKMS_VER}"

    info "Verifying checksum..."
    echo "${DEKTEC_DKMS_MD5} LinuxSDK_v${PKGVER}.tar.gz" | md5sum -c --status || {
        error "Checksum verification failed. The downloaded file may be corrupt or the MD5 is incorrect. Exiting."
        exit 1
    }
    info "Checksum verification successful."
}

# Function to patch and install dektec drivers
install_dektec_drivers() {
    info "Extracting driver source..."
    tar -xf "LinuxSDK_v${PKGVER}.tar.gz"
    cd "LinuxSDK"
    
    # --- FIRST PATCH for DtUtility.c ---
    info "Build would fail on kernel $(uname -r) due to MAX_ORDER. Applying patch..."
    local patch_file1="Drivers/DtSal/Source/DtUtility.c"
    if [[ ! -f "$patch_file1" ]]; then
        error "Could not find file to patch: ${patch_file1}. The SDK package structure may have changed."
        exit 1
    fi
    sed -i 's/if (get_order(Size) < MAX_ORDER)/if (get_order(Size) < MAX_PAGE_ORDER)/g' "$patch_file1"
    info "Successfully patched '${patch_file1}'."

    # --- SECOND PATCH for DtPcieNwIal.c ---
    info "Build would fail on kernel $(uname -r) due to ethtool ops incompatibility. Applying patch..."
    local patch_file2="Drivers/DtPcieNw/Source/Linux/DtPcieNwIal.c"
     if [[ ! -f "$patch_file2" ]]; then
        error "Could not find file to patch: ${patch_file2}. The SDK package structure may have changed."
        exit 1
    fi
    # Use a type cast to (void *) to resolve the incompatible pointer type warning that is treated as an error.
    sed -i 's/.get_ts_info = DtPcieNwEvtGetTsInfo,/.get_ts_info = (void *)DtPcieNwEvtGetTsInfo,/g' "$patch_file2"
    info "Successfully patched '${patch_file2}'."
    
    # Check for Drivers directory before proceeding
    if [[ ! -d "Drivers" ]]; then
        error "Could not find the 'Drivers' directory in the extracted SDK. The package structure may have changed."
        exit 1
    fi
    
    info "Installing 'dektec-dkms' via testing, building, and installing DKMS package."
    cd Drivers/
    sudo ./Install
    # The -t flag is for testing, which might not be necessary or could be interactive.
    # It's included here to match the original script's logic.
    sudo ./Install -t
}


# Function to display final steps
display_final_steps() {
    info "All done. Downloaded sources are stored in folder '${WORKDIR}'."
    info "If SecureBoot is enabled, you will need the following steps:
1. Type 'sudo mokutil --import /var/lib/dkms/mok.pub'
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
    # --- UPDATED VARIABLES ---
    PKGVER="2025.04.0"
    DEKTEC_DKMS_MD5="b46e889ad546591c13f162d1e67e2e37" # MD5 for LinuxSDK_v2025.04.0.tar.gz
    # --- END UPDATED VARIABLES ---
    DEKTEC_DKMS_VER="https://www.dektec.com/products/SDK/DTAPI/Downloads/LinuxSDK_v${PKGVER}.tar.gz"

    check_not_root
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
