#!/usr/bin/env bash
# Script: install-alsa-hdspe-dkms.sh
# Author: nikos.toutountzoglou@svt.se
# Upstream link: https://github.com/PhilippeBekaert/snd-hdspe
# Description: RME HDSPe MADI/AES/RayDAT/AIO/AIO-Pro DKMS driver installation script for Rocky Linux 9
# Revision: 1.0

# Stop script on NZEC
set -e
# Stop script if unbound variable found (use ${var:-} if intentional)
set -u
# By default cmd1 | cmd2 returns exit code of cmd2 regardless of cmd1 success
# This is causing it to fail
set -o pipefail

# Variables
PKGDIR="$HOME/src/alsa-hdspe-dkms"
PKGNAME="alsa-hdspe"
PKGVER="0.0"
RME_DKMS_PKG="https://github.com/PhilippeBekaert/snd-hdspe.git"
RME_DKMS_VER="0.0"
RME_DKMS_MD5=

# Check Linux distro
if [ -f /etc/os-release ]; then
	# freedesktop.org and systemd
	. /etc/os-release
	OS=${ID}
	VERS_ID=${VERSION_ID}
	OS_ID="${VERS_ID:0:1}"
elif type lsb_release &>/dev/null; then
	# linuxbase.org
	OS=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
elif [ -f /etc/lsb-release ]; then
	# For some versions of Debian/Ubuntu without lsb_release command
	. /etc/lsb-release
	OS=$(printf ${DISTRIB_ID} | tr '[:upper:]' '[:lower:]')
elif [ -f /etc/debian_version ]; then
	# Older Debian/Ubuntu/etc.
	OS=debian
else
	# Unknown
	printf "Unknown Linux distro. Exiting!\n"
	exit 1
fi

# Check if distro is Rocky Linux 9
if [ $OS = "rocky" ] && [ $OS_ID = "9" ]; then
	printf "Detected 'Rocky Linux 9'. Continuing.\n"
else
	printf "Could not detect 'Rocky Linux 9'. Exiting.\n"
	exit 1
fi

# Prompt user with yes/no before proceeding
printf "Welcome to RME HDSPe sound cards DKMS driver intallation script.\n"
while true; do
	read -r -p "Proceed with installation? (y/n) " yesno
	case "$yesno" in
	n | N) exit 0 ;;
	y | Y) break ;;
	*) printf "Please answer 'y/n'.\n" ;;
	esac
done

# Create a working source dir
if [ -d "${PKGDIR}" ]; then
	while true; do
		printf "Source directory '${PKGDIR}' already exists.\n"
		read -r -p "Delete it and reinstall? (y/n) " yesno
		case "$yesno" in
		n | N) exit 0 ;;
		y | Y) break ;;
		*) printf "Please answer 'y/n'.\n" ;;
		esac
	done
fi

rm -fr ${PKGDIR}
mkdir -v -p ${PKGDIR}
cd ${PKGDIR}

# Enable Extra Packages for Enterprise Linux 9
printf "Enabling Extra Packages for Enterprise Linux 9 and Development Tools.\n"
sudo dnf install -y epel-release
sudo /usr/bin/crb enable

# Enable Development Tools
sudo dnf groupinstall -y "Development Tools"

# Update package repos cache
sudo dnf makecache

# Install Rocky Linux 9 dkms package
sudo dnf install -y dkms kernel-headers-$(uname -r)

# Download latest driver from upstream source
printf "Downloading latest driver from upstream source.\n"
git clone ${RME_DKMS_PKG}

# Patches and fixes
cd snd-hdspe
# insert patches here...

# Create DKMS driver build dir
mkdir -p build/usr/src/${PKGNAME}-${RME_DKMS_VER}

# Create a custom dkms.conf file and set correct version
printf 'PACKAGE_NAME=alsa-hdspe\nPACKAGE_VERSION=0.0\n\nMAKE=\"\u0027make\u0027 KERNELDIR=/lib/modules/${kernelver}/build\"\nCLEAN=\"make clean\"\nAUTOINSTALL=yes\n\nBUILT_MODULE_NAME[0]=snd-hdspe\nBUILT_MODULE_LOCATION[0]=sound/pci/hdsp/hdspe\nDEST_MODULE_LOCATION[0]=/kernel/sound/pci/\n' >dkms-custom.conf

# Copy DKMS driver to correct build dirs
install -Dm644 dkms-custom.conf build/usr/src/${PKGNAME}-${RME_DKMS_VER}/dkms.conf
install -Dm644 Makefile build/usr/src/${PKGNAME}-${RME_DKMS_VER}/Makefile
cp -a --no-preserve='mode,ownership' sound build/usr/src/${PKGNAME}-${RME_DKMS_VER}

# Copy final DKMS driver to kernel source dir
cd build/usr/src
sudo cp -R ${PKGNAME}-${RME_DKMS_VER} /usr/src

# Install DKMS driver
printf "Installing DKMS driver.\n"
sudo dkms install -m ${PKGNAME} -v ${RME_DKMS_VER}

# Blacklist conflicting rme9652 driver
if [ ! -f /usr/lib/modprobe.d/hdspe.conf ]; then
	printf "blacklist snd-hdspm" | sudo tee -a /usr/lib/modprobe.d/hdspe.conf
fi

# Prompt about final steps
printf "Successfully installed DKMS drivers, now reboot and check\nif the module is loaded by typing 'lsmod | grep snd-hdspe'.\n"
printf "\nFor more information please check: https://github.com/PhilippeBekaert/snd-hdspe\n"

exit 0
