#!/usr/bin/env bash
# Script: install-alsa-hdspeconf.sh
# Author: nikos.toutountzoglou@svt.se
# Upstream link: https://github.com/PhilippeBekaert/hdspeconf
# Video: https://youtu.be/jK8XmVoK9WM?si=9iN15IBqC99z18cz
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
PKGDIR="$HOME/src/hdspeconf"
PKGNAME="alsa-hdspeconf"
PKGVER="0.0"
HDSPECONF_PKG="https://github.com/PhilippeBekaert/hdspeconf.git"
HDSPECONF_VER="0.0"
HDSPECONF_MD5=

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
printf "Welcome to RME HDSPe sound cards user space configuration tool installation script.\n"
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

# Prerequisites

# Packages necessary for building hdspeconf
sudo dnf install -y alsa-lib-devel wxGTK3-devel

# Download latest driver from upstream source
printf "Downloading latest upstream source.\n"
git clone ${HDSPECONF_PKG}

# Patches and fixes
cd hdspeconf
# insert patches here...

# Build binary
make depend
make

# Install binary
sudo install -vDm755 hdspeconf -t /usr/share/${PKGNAME}
sudo install -vDm644 dialog-warning.png -t /usr/share/${PKGNAME}

# Create symlink in /usr/bin
sudo ln -s /usr/share/${PKGNAME}/hdspeconf /usr/bin/${PKGNAME}

# Prompt about final steps
printf "\nSuccessfully installed hdspeconf user space configuration tool for RME HDSPe MADI/AES/RayDAT/AIO/AIO-Pro cards\nTo open the configuration window open a terminal window and type 'hdspeconf'.\n"
printf "\nFor more information please check: https://github.com/PhilippeBekaert/hdspeconf\n"

exit 0
