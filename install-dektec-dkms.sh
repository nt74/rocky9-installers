#!/usr/bin/env bash
# Author: Nikos Toutountzoglou, nikos.toutountzoglou@svt.se
# Upstream link: https://www.dektec.com/downloads/SDK/#linux
# Script: install-dektec-dkms.sh
# Description: Install dektec Linux DKMS for Dektec device drivers
# Revision: 1.2

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
WORKDIR="$HOME/src/release/dektec"

# Dektec DKMS RPM package
PKGNAME="dektec-dkms"
PKGVER="2024.06.0"
DEKTEC_DKMS_VER="https://www.dektec.com/products/SDK/DTAPI/Downloads/LinuxSDK_v${PKGVER}.tar.gz"
DEKTEC_DKMS_MD5="897aa00d43f1e42cbb778cfa5cc47262"

# Prompt user with yes/no before continuing
while true; do
	read -r -p "Install dektec Linux DKMS for Dektec device drivers? (y/n) " yesno
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

# Dektec DKMS upstream source
echo "Downloading 'dektec-dkms' from upstream source."
curl -# -LO ${DEKTEC_DKMS_VER}

# Checksum
echo ${DEKTEC_DKMS_MD5} LinuxSDK_v${PKGVER}.tar.gz | md5sum -c || exit 1

# Enable Extra Packages for Enterprise Linux 9
echo "Enable EPEL, CRB and Development Tools."
sudo dnf install -y epel-release
sudo /usr/bin/crb enable
# Enable Development Tools
sudo dnf groupinstall -y "Development Tools"
# Update package repos cache
sudo dnf makecache

# Install dektec driver DKMS package
echo "Installing 'dektec-dkms' via testing, building and installing DKMS package."
sudo dnf install dkms kernel-headers-$(uname -r)
tar -xf LinuxSDK_v${PKGVER}.tar.gz
cd LinuxSDK/Drivers/
sudo ./Install
sudo ./Install -t

# Exit
echo "All done. Downloaded sources are stored in folder '${WORKDIR}'."
printf "\nIf SecureBoot is enabled, you will need the following steps:
1. Type 'mokutil --import /var/lib/dkms/mok.pub'
2. You'll be prompted to create a password. Enter it twice.
3. Reboot the computer. At boot you'll see the MOK Manager EFI interface
4. Press any key to enter it, then select 'Enroll MOK'
5. Then select 'Continue'
6. And confirm with 'Yes' when prompted
7. After this, enter the password you set up with 'mokutil --import' in the previous step
8. At this point you are done, select 'OK' and the computer will reboot trusting the key for your modules
9. After reboot, you can inspect the MOK certificates with the following command 'mokutil --list-enrolled | grep DKMS'\n"
exit 0
