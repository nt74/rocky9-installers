#!/usr/bin/env bash
# Script: install-alsa-hdspe-dkms.sh
# Author: nikos.toutountzoglou@svt.se
# Upstream link: https://github.com/Schroedingers-Cat/snd-hdspe
# Video: https://youtu.be/jK8XmVoK9WM?si=9iN15IBqC99z18cz
# Description: RME HDSPe MADI/AES/RayDAT/AIO/AIO-Pro DKMS driver installation script for Rocky Linux 9
# Revision: 1.2

# Exit immediately on error, uninitialized variable, or failed pipeline
set -euo pipefail

# Constants
# The PKGDIR variable defines the directory where the source code will be downloaded.
PKGDIR="${HOME}/src/alsa-hdspe-dkms"
# The PKGNAME variable sets the name for the DKMS package.
PKGNAME="alsa-hdspe"
# The RME_DKMS_PKG variable holds the URL for the driver source code.
RME_DKMS_PKG="https://github.com/Schroedingers-Cat/snd-hdspe/archive/refs/heads/support-v6.2.zip"
# The RME_DKMS_VER variable sets the version for the DKMS package.
RME_DKMS_VER="6.2"

# Color codes for script output for better readability.
INFO="\033[1;32mINFO:\033[0m"
WARNING="\033[1;33mWARNING:\033[0m"
ERROR="\033[1;31mERROR:\033[0m"

# Log all script output to a file in the user's home directory.
exec > >(tee -i "${HOME}/install-alsa-hdspe.log") 2>&1

# Function to check if the script is running on a supported Linux distribution.
detect_distro() {
	echo -e "${INFO} Detecting Linux distribution."
	if [[ -f /etc/os-release ]]; then
		# Source the os-release file to get distribution info.
		. /etc/os-release
		OS=${ID}
		VERSION_ID=${VERSION_ID}
	elif command -v lsb_release &>/dev/null; then
		# Use lsb_release command if available.
		OS=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
		VERSION_ID=$(lsb_release -sr)
	elif [[ -f /etc/lsb-release ]]; then
		# Source the lsb-release file as another fallback.
		. /etc/lsb-release
		OS=$(echo "${DISTRIB_ID}" | tr '[:upper:]' '[:lower:]')
		VERSION_ID=${DISTRIB_RELEASE}
	else
		echo -e "${ERROR} Unsupported Linux distribution. Exiting."
		exit 1
	fi

	# Ensure the OS is Rocky Linux version 9.
	if [[ "${OS}" != "rocky" || "${VERSION_ID%%.*}" != "9" ]]; then
		echo -e "${ERROR} This script supports only Rocky Linux 9. Consider using a compatible system. Exiting."
		exit 1
	fi
	echo -e "${INFO} Detected Rocky Linux 9."
}

# Function to prompt the user for a yes/no confirmation.
prompt_user() {
	local prompt_message="${1}"
	while true; do
		read -r -p "${prompt_message} (y/n): " response
		case "${response}" in
		[yY]) return 0 ;; # Return success for yes
		[nN]) return 1 ;; # Return failure for no
		*) echo -e "${WARNING} Invalid input. Please enter 'y' or 'n'." ;;
		esac
	done
}

# Function to set up the source directory.
prepare_source_dir() {
	echo -e "${INFO} Preparing source directory."
	if [[ -d "${PKGDIR}" ]]; then
		echo -e "${INFO} Source directory '${PKGDIR}' already exists."
		if ! prompt_user "Delete and recreate it?"; then
			exit 0
		fi
		# Remove existing directory if user agrees.
		rm -rf "${PKGDIR}"
	fi
	# Create the source directory.
	mkdir -p "${PKGDIR}"
	echo -e "${INFO} Created source directory: ${PKGDIR}"
}

# Function to enable required repositories and install dependencies.
enable_repos_and_install_deps() {
	echo -e "${INFO} Enabling required repositories and installing dependencies."
	# Install EPEL repository for extra packages.
	sudo dnf install -y epel-release
	# Enable the CodeReady Builder (CRB) repository.
	sudo /usr/bin/crb enable
	# Install development tools needed for compilation.
	sudo dnf groupinstall -y "Development Tools"
	# Define kernel headers package based on the running kernel.
	local kernel_headers="kernel-headers-$(uname -r)"
	# Install dkms, kernel headers, and unzip if not already present.
	if ! rpm -q dkms &>/dev/null; then
		sudo dnf install -y dkms "${kernel_headers}" unzip
	else
		echo -e "${INFO} dkms and kernel headers are already installed."
		# Ensure unzip is installed if dkms is already there.
		sudo dnf install -y unzip
	fi
	# Refresh DNF cache.
	sudo dnf makecache
	echo -e "${INFO} Dependencies installed."
}

# Function to download the driver source and prepare it for DKMS.
download_and_prepare_driver() {
	echo -e "${INFO} Downloading driver from upstream."
	cd "${PKGDIR}"
	# Download the source code zip file.
	wget -O driver.zip "${RME_DKMS_PKG}"
	# Unzip the archive, overwriting existing files.
	unzip -o driver.zip
	# The extracted folder is named snd-hdspe-support-v6.2, rename for consistency.
	mv snd-hdspe-support-v6.2 snd-hdspe
	cd "${PKGDIR}/snd-hdspe"

	echo -e "${INFO} Creating DKMS configuration."
	# Create the directory structure for DKMS.
	sudo mkdir -p "/usr/src/${PKGNAME}-${RME_DKMS_VER}"
	# Create the dkms.conf file with the necessary configuration.
	sudo tee "/usr/src/${PKGNAME}-${RME_DKMS_VER}/dkms.conf" >/dev/null <<EOF
PACKAGE_NAME="${PKGNAME}"
PACKAGE_VERSION="${RME_DKMS_VER}"
AUTOINSTALL="yes"
MAKE[0]="make -C \${kernel_source_dir} M=\$(pwd)"
CLEAN="make clean"
BUILT_MODULE_NAME[0]="snd-hdspe"
BUILT_MODULE_LOCATION[0]="."
DEST_MODULE_LOCATION[0]="/kernel/sound/pci/"
EOF

	# Copy the source files to the DKMS source directory.
	sudo cp -Pr ./* "/usr/src/${PKGNAME}-${RME_DKMS_VER}/"
	echo -e "${INFO} Driver downloaded and prepared."
}

# Function to add, build, and install the DKMS driver.
install_dkms_driver() {
	echo -e "${INFO} Adding, building, and installing DKMS driver."
	# Add the new module to DKMS.
	sudo dkms add -m "${PKGNAME}" -v "${RME_DKMS_VER}"
	# Build the module.
	sudo dkms build -m "${PKGNAME}" -v "${RME_DKMS_VER}"
	# Install the module.
	sudo dkms install -m "${PKGNAME}" -v "${RME_DKMS_VER}" --force
	echo -e "${INFO} DKMS driver installed."
}

# Function to blacklist the conflicting snd_hdspm driver.
blacklist_conflicting_driver() {
	echo -e "${INFO} Blacklisting conflicting drivers."
	local blacklist_file="/usr/lib/modprobe.d/hdspe.conf"
	# Check if the conflicting module is loaded. Note the underscore.
	if lsmod | grep -q snd_hdspm; then
		if [[ ! -f "${blacklist_file}" ]]; then
			# Create a modprobe conf file to blacklist the driver.
			echo "blacklist snd_hdspm" | sudo tee "${blacklist_file}" >/dev/null
			echo -e "${INFO} Blacklisted snd_hdspm driver."
		else
			echo -e "${INFO} snd_hdspm driver already blacklisted."
		fi
	else
		echo -e "${INFO} No conflicting driver loaded."
	fi
}

# Main script execution flow
echo -e "${INFO} Starting RME HDSPe DKMS driver installation."
detect_distro

if ! prompt_user "Proceed with installation?"; then
	echo -e "${INFO} Installation aborted by user."
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
# Updated verification command to reflect the correct module name.
echo -e "  lsmod | grep snd_hdspe"

echo -e "${INFO} If Secure Boot is enabled, you must enroll the new MOK key:"
echo -e "  1. Run 'sudo mokutil --import /var/lib/dkms/mok.pub' and enter a password."
echo -e "  2. Reboot. The MOK manager (a blue screen) will start."
echo -e "  3. Select 'Enroll MOK', continue, and enter the password you created."
echo -e "  4. After enrolling, select 'Reboot'."
echo -e "  5. You can verify the key is enrolled with: mokutil --list-enrolled | grep DKMS"

echo -e "${INFO} For more details, visit: https://github.com/Schroedingers-Cat/snd-hdspe"

exit 0
