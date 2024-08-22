#!/usr/bin/env bash
# Author: Nikos Toutountzoglou, nikos.toutountzoglou@svt.se
# Script: install-tsduck.sh
# Description: Install tsduck MPEG Transport Stream Toolkit
# Revision: 1.3

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
	OS=$(echo ${DISTRIB_ID} | tr '[:upper:]' '[:lower:]')
elif [ -f /etc/debian_version ]; then
	# Older Debian/Ubuntu/etc.
	OS=debian
else
	# Unknown
	echo "Unknown Linux distro. Exiting!"
	exit 1
fi

# Check if distro is Rocky Linux 9
if [ $OS = "rocky" ] && [ $OS_ID = "9" ]; then
	echo "Detected 'Rocky Linux 9'. Continuing."
else
	echo "Could not detect 'Rocky Linux 9'. Exiting."
	exit 1
fi

# Variables
WORKDIR="$HOME/src/release/tsduck"

# TSDuck RPM package
PKGNAME="tsduck"
PKGVER="3.38-3822"
TSDUCK_VER="https://github.com/${PKGNAME}/${PKGNAME}/releases/download/v${PKGVER}/${PKGNAME}-${PKGVER}.el9.x86_64.rpm"
TSDUCK_MD5="566f1cee31cffc8277bba28bb8e59801"

# Prerequisites script
PREREQ="https://raw.githubusercontent.com/${PKGNAME}/${PKGNAME}/master/scripts/install-prerequisites.sh"

# License
LICENSE="https://raw.githubusercontent.com/${PKGNAME}/${PKGNAME}/master/LICENSE.txt"

# Prompt user with yes/no before continuing
while true; do
	read -r -p "Install tsduck MPEG Transport Stream Toolkit? (y/n) " yesno
	case "$yesno" in
	n | N) exit 0 ;;
	y | Y) break ;;
	*) echo "Please answer 'y/n'." ;;
	esac
done

# Create a working source dir
if [ -d "${WORKDIR}" ]; then
	while true; do
		echo "Source directory '${WORKDIR}' already exists."
		read -r -p "Delete it and reinstall? (y/n) " yesno
		case "$yesno" in
		n | N) exit 0 ;;
		y | Y) break ;;
		*) echo "Please answer 'y/n'." ;;
		esac
	done
fi

rm -f ${WORKDIR}
mkdir -p ${WORKDIR}
cd ${WORKDIR}

# TSDuck upstream source
echo "Downloading TSDuck from upstream source."
curl -# -LO ${TSDUCK_VER}

# TSDuck prerequisites script
echo "Downloading TSDuck prerequisites script."
curl -# -LO ${PREREQ}

# TSDuck License
curl -# -LO ${LICENSE}

# Checksum
echo ${TSDUCK_MD5} ${PKGNAME}-${PKGVER}.el9.x86_64.rpm | md5sum -c || exit 1

echo "Downloaded files have successfully passed MD5 checksum test. Continuing."

# Prerequisites

# Packages necessary for building tsduck
echo "Installing prerequisite packages."
chmod +x install-prerequisites.sh
./install-prerequisites.sh
sudo dnf install -y glibc mlocate

# Install decklink driver RPM package
echo "Installing 'tsduck' via RPM package."
sudo rpm -Uvh ${PKGNAME}-${PKGVER}.el9.x86_64.rpm

# Exit
echo "All done. Downloaded sources are stored in folder '${WORKDIR}'."
sudo ldconfig
sudo updatedb
exit 0
