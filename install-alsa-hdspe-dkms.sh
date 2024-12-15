#!/usr/bin/env bash
# Script: install-alsa-hdspe-dkms.sh
# Author: nikos.toutountzoglou@svt.se
# Upstream link: https://github.com/PhilippeBekaert/snd-hdspe
# Video: https://youtu.be/jK8XmVoK9WM?si=9iN15IBqC99z18cz
# Description: RME HDSPe MADI/AES/RayDAT/AIO/AIO-Pro DKMS driver installation script for Rocky Linux 9
# Revision: 1.1

# Exit immediately on error, uninitialized variable, or failed pipeline
set -euo pipefail

# Constants
PKGDIR="${HOME}/src/alsa-hdspe-dkms"
PKGNAME="alsa-hdspe"
RME_DKMS_PKG="https://github.com/PhilippeBekaert/snd-hdspe.git"
RME_DKMS_VER="0.0"

# Color codes
INFO="\033[1;32mINFO:\033[0m"
WARNING="\033[1;33mWARNING:\033[0m"
ERROR="\033[1;31mERROR:\033[0m"

# Log actions
exec > >(tee -i "${HOME}/install-alsa-hdspe.log") 2>&1

# Function to check Linux distribution
detect_distro() {
	echo -e "${INFO} Detecting Linux distribution."
	if [[ -f /etc/os-release ]]; then
		. /etc/os-release
		OS=${ID}
		VERSION_ID=${VERSION_ID}
	elif command -v lsb_release &>/dev/null; then
		OS=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
		VERSION_ID=$(lsb_release -sr)
	elif [[ -f /etc/lsb-release ]]; then
		. /etc/lsb-release
		OS=$(echo "${DISTRIB_ID}" | tr '[:upper:]' '[:lower:]')
		VERSION_ID=${DISTRIB_RELEASE}
	else
		echo -e "${ERROR} Unsupported Linux distribution. Exiting."
		exit 1
	fi

	if [[ "${OS}" != "rocky" || "${VERSION_ID%%.*}" != "9" ]]; then
		echo -e "${ERROR} This script supports only Rocky Linux 9. Consider using a compatible system. Exiting."
		exit 1
	fi
	echo -e "${INFO} Detected Rocky Linux 9."
}

# Prompt user for confirmation
prompt_user() {
	local prompt_message="${1}"
	while true; do
		read -r -p "${prompt_message} (y/n): " response
		case "${response}" in
		[yY]) return 0 ;;
		[nN]) return 1 ;;
		*) echo -e "${WARNING} Invalid input. Please enter 'y' or 'n'." ;;
		esac
	done
}

# Prepare the source directory
prepare_source_dir() {
	echo -e "${INFO} Preparing source directory."
	if [[ -d "${PKGDIR}" ]]; then
		echo -e "${INFO} Source directory '${PKGDIR}' already exists."
		if ! prompt_user "Delete and recreate it?"; then
			exit 0
		fi
		rm -rf "${PKGDIR}"
	fi
	mkdir -p "${PKGDIR}"
	echo -e "${INFO} Created source directory: ${PKGDIR}"
}

# Install dependencies
enable_repos_and_install_deps() {
	echo -e "${INFO} Enabling required repositories and installing dependencies."
	sudo dnf install -y epel-release
	sudo /usr/bin/crb enable
	sudo dnf groupinstall -y "Development Tools"
	local kernel_headers="kernel-headers-$(uname -r)"
	if ! rpm -q dkms &>/dev/null; then
		sudo dnf install -y dkms "${kernel_headers}"
	else
		echo -e "${INFO} dkms and kernel headers are already installed."
	fi
	sudo dnf makecache
	echo -e "${INFO} Dependencies installed."
}

# Download and prepare DKMS driver
download_and_prepare_driver() {
	echo -e "${INFO} Downloading driver from upstream."
	cd "${PKGDIR}"
	git clone "${RME_DKMS_PKG}"
	cd "${PKGDIR}/snd-hdspe"

	echo -e "${INFO} Creating DKMS configuration."
	mkdir -p build/usr/src/${PKGNAME}-${RME_DKMS_VER}
	cat <<EOF >build/usr/src/${PKGNAME}-${RME_DKMS_VER}/dkms.conf
PACKAGE_NAME="${PKGNAME}"
PACKAGE_VERSION="${RME_DKMS_VER}"
AUTOINSTALL="yes"
MAKE[0]="make KVER=\$kernelver"
CLEAN="make clean"
BUILT_MODULE_NAME[0]="snd-hdspe"
BUILT_MODULE_LOCATION[0]="sound/pci/hdsp/hdspe"
DEST_MODULE_LOCATION[0]="/kernel/sound/pci/"
SUPPORTED_KERNELS="5.10.0-*.el9.x86_64"
EOF

	cp -Pr {sound,Makefile} build/usr/src/${PKGNAME}-${RME_DKMS_VER}
	sudo cp -Pr build/usr/src/${PKGNAME}-${RME_DKMS_VER} /usr/src
	echo -e "${INFO} Driver downloaded and prepared."
}

# Install DKMS driver
install_dkms_driver() {
	echo -e "${INFO} Installing DKMS driver."
	sudo dkms install -m "${PKGNAME}" -v "${RME_DKMS_VER}"
	echo -e "${INFO} DKMS driver installed."
}

# Blacklist conflicting drivers
blacklist_conflicting_driver() {
	echo -e "${INFO} Blacklisting conflicting drivers."
	local blacklist_file="/usr/lib/modprobe.d/hdspe.conf"
	if lsmod | grep -q snd-hdspm; then
		if [[ ! -f "${blacklist_file}" ]]; then
			echo "blacklist snd-hdspm" | sudo tee "${blacklist_file}" >/dev/null
			echo -e "${INFO} Blacklisted snd-hdspm driver."
		else
			echo -e "${INFO} snd-hdspm driver already blacklisted."
		fi
	else
		echo -e "${INFO} No conflicting driver loaded."
	fi
}

# Main script execution
echo -e "${INFO} Starting RME HDSPe DKMS driver installation."
detect_distro

if ! prompt_user "Proceed with installation?"; then
	exit 0
fi

prepare_source_dir
enable_repos_and_install_deps
download_and_prepare_driver
install_dkms_driver
blacklist_conflicting_driver

if prompt_user "Reboot now?"; then
	sudo reboot
fi

echo -e "${INFO} Installation complete. Please reboot and verify the module with:"
echo -e "  lsmod | grep snd-hdspe"

echo -e "${INFO} If Secure Boot is enabled, follow these steps:"
echo -e "  1. mokutil --import /var/lib/dkms/mok.pub"
echo -e "  2. Reboot and enroll the MOK key."
echo -e "  3. Verify with: mokutil --list-enrolled | grep DKMS"

echo -e "${INFO} For more details, visit: https://github.com/PhilippeBekaert/snd-hdspe"

exit 0
