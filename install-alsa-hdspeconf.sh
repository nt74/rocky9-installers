#!/usr/bin/env bash
# Script: install-alsa-hdspeconf.sh
# Author: nikos.toutountzoglou@svt.se
# Upstream link: https://github.com/PhilippeBekaert/hdspeconf
# Video: https://youtu.be/jK8XmVoK9WM?si=9iN15IBqC99z18cz
# Description: RME HDSPe MADI/AES/RayDAT/AIO/AIO-Pro sound cards user space configuration tool installation script for Rocky Linux 9
# Revision: 1.2

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

    info "Installing necessary packages for building hdspeconf."
    sudo dnf install -y alsa-lib-devel wxGTK3-devel
}

# Function to download and build hdspeconf
download_and_build() {
    info "Downloading latest upstream source."
    git clone "${HDSPECONF_PKG}"

    cd hdspeconf
    # Insert patches here...

    info "Building package."
    make depend
    make
}

# Function to install hdspeconf
install_hdspeconf() {
    info "Installing package."
    sudo install -vDm755 hdspeconf -t /usr/share/${PKGNAME}
    sudo install -vDm644 dialog-warning.png -t /usr/share/${PKGNAME}

    info "Creating symlink in '/usr/bin'."
    echo '#!/usr/bin/env bash' | sudo tee /usr/bin/hdspeconf
    echo 'cd /usr/share/alsa-hdspeconf' | sudo tee -a /usr/bin/hdspeconf
    echo './hdspeconf' | sudo tee -a /usr/bin/hdspeconf
    sudo chmod +x /usr/bin/hdspeconf
}

# Function to display final steps
display_final_steps() {
    info "Successfully installed hdspeconf user space configuration tool for RME HDSPe MADI/AES/RayDAT/AIO/AIO-Pro cards."
    info "To open the configuration window, open a terminal window and type 'hdspeconf'."
    info "For more information please check: https://github.com/PhilippeBekaert/hdspeconf"
}

# Main function
main() {
    info "Script execution started."

    # Variables
    PKGDIR="$HOME/src/hdspeconf"
    PKGNAME="alsa-hdspeconf"
    HDSPECONF_PKG="https://github.com/PhilippeBekaert/hdspeconf.git"

    check_distro
    prompt_user "Welcome to RME HDSPe sound cards user space configuration tool installation script. Proceed with installation?"
    prepare_workdir
    install_prerequisites
    download_and_build
    install_hdspeconf
    display_final_steps

    info "Script execution finished."
}

# Run the main function
main
