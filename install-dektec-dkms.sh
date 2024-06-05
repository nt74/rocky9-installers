#!/bin/bash
# Author: Nikos Toutountzoglou, nikos.toutountzoglou@svt.se
# Script: install-dektec-dkms.sh
# Description: Install dektec Linux DKMS for Dektec device drivers
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
WORKDIR="$HOME/src/release/dektec"

# Dektec DKMS RPM package
PKGNAME="dektec-dkms"
PKGVER="2024.04.0"
DEKTEC_DKMS_VER="https://github.com/tsduck/${PKGNAME}/releases/download/v${PKGVER}/${PKGNAME}-${PKGVER}-0.el9.noarch.rpm"
DEKTEC_DKMS_MD5="3c8466dd64808ddb53e30d77d4544e73"

# Prompt user with yes/no before continuing
while true
do
	read -r -p "Install dektec Linux DKMS for Dektec device drivers? (y/n) " yesno
	case "$yesno" in
		n|N) exit 0;;
		y|Y) break;;
		*) echo "Please answer 'y/n'.";;
	esac
done

# Download
mkdir -p ${WORKDIR}
cd ${WORKDIR}
# Dektec DKMS upstream source
echo "Downloading 'dektec-dkms' from upstream source."
curl -LO ${DEKTEC_DKMS_VER}

# Checksum
md5sum -c <<< "${DEKTEC_DKMS_MD5} ${PKGNAME}-${PKGVER}-0.el9.noarch.rpm" || exit 1

# Enable Extra Packages for Enterprise Linux 9
echo "Enable EPEL, CRB and Development Tools."
sudo dnf install epel-release
sudo /usr/bin/crb enable
# Enable Development Tools
sudo dnf groupinstall "Development Tools"
# Update package repos cache
sudo dnf makecache

# Install decklink driver RPM package
echo "Installing 'dektec-dkms' via RPM package."
sudo dnf install dkms kernel-headers-$(uname -r)
sudo rpm -Uvh ${PKGNAME}-${PKGVER}-0.el9.noarch.rpm

# Exit
echo "All done. Downloaded sources are stored in folder '${WORKDIR}'."
exit 0
