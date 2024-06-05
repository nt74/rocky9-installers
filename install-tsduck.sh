#!/bin/bash
# Author: Nikos Toutountzoglou, nikos.toutountzoglou@svt.se
# Script: install-tsduck.sh
# Description: Install tsduck MPEG Transport Stream Toolkit
# Revision: 1.0

# Check Linux distro
if [ -f /etc/os-release ]; then
	# freedesktop.org and systemd
	. /etc/os-release
	OS=${ID}
	VERS_ID=${VERSION_ID}
	OS_ID="${VERS_ID:0:1}"
elif type lsb_release &> /dev/null; then
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
TSDUCK_VER="https://github.com/tsduck/tsduck/releases/download/v3.37-3670/tsduck-3.37-3670.el9.x86_64.rpm"
TSDUCK_MD5="c540b2c5f3ef69fca6c50f666e22537b"
PKGNAME="tsduck"
PKGVER="3.37-3670"

# Prerequisites script
PREREQ="https://raw.githubusercontent.com/tsduck/tsduck/master/scripts/install-prerequisites.sh"
PREREQ_MD5="3314fa16a324d9cefcb9f26e9e775fdf"

# License
LICENSE="https://raw.githubusercontent.com/tsduck/tsduck/master/LICENSE.txt"

# Prompt user with yes/no before continuing
while true
do
	read -r -p "Install tsduck MPEG Transport Stream Toolkit? (y/n) " yesno
	case "$yesno" in
		n|N) exit 0;;
		y|Y) break;;
		*) echo "Please answer 'y/n'.";;
	esac
done

# Download
mkdir -p ${WORKDIR}
cd ${WORKDIR}
# TSDuck upstream source
echo "Downloading TSDuck from upstream source."
curl -LO ${TSDUCK_VER}
# TSDuck prerequisites script
echo "Downloading TSDuck prerequisites script."
curl -LO ${PREREQ}
# TSDuck License
curl -LO ${LICENSE}

# Checksum
md5sum -c <<< "${TSDUCK_MD5} ${PKGNAME}-${PKGVER}.el9.x86_64.rpm" && \
md5sum -c <<< "${PREREQ_MD5} install-prerequisites.sh" || exit 1

if [ $? -eq 0 ]; then
	echo "Downloaded files have successfully passed MD5 checksum test. Continuing."
else
	echo "Downloaded files have failed to pass MD5 checksum test. Exiting."
	exit 1
fi

# Prerequisites

# Packages necessary for building tsduck
echo "Installing prerequisite packages."
chmod +x install-prerequisites.sh
./install-prerequisites.sh

# Install decklink driver RPM package
echo "Installing 'tsduck' via RPM package."
sudo rpm -Uvh ${PKGNAME}-${PKGVER}.el9.x86_64.rpm

# Exit
echo "All done. Downloaded sources are stored in folder '${WORKDIR}'."
sudo ldconfig
sudo updatedb
exit 0
