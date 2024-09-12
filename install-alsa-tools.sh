#!/usr/bin/env bash
# Script: install-alsa-tools.sh
# Author: nikos.toutountzoglou@svt.se
# Upstream link: https://www.alsa-project.org
# Description: Alsa tools for Rocky Linux 9
# Revision: 1.0

# Stop script on NZEC
set -e
# Stop script if unbound variable found (use ${var:-} if intentional)
set -u
# By default cmd1 | cmd2 returns exit code of cmd2 regardless of cmd1 success
# This is causing it to fail
set -o pipefail

# Variables
PKGDIR="$HOME/src/alsa-tools"
PKGNAME="alsa-tools"
PKGVER="1.2.11"
ATOOLS_PKG="http://www.alsa-project.org/files/pub/tools/${PKGNAME}-${PKGVER}.tar.bz2"
ATOOLS_MD5="bc5f5e5689f46a9d4a0b85dc6661732c"

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
printf "Welcome to alsa-tools installation script.\n"
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
sudo dnf install -y alsa-lib-devel hicolor-icon-theme fltk-devel gtk2-devel gtk3-devel

# Download latest driver from upstream source
printf "Downloading latest upstream source.\n"
curl -# -LO ${ATOOLS_PKG}

# Checksum
echo ${ATOOLS_MD5} ${PKGNAME}-${PKGVER}.tar.bz2 | md5sum -c || exit 1

printf "Downloaded files have successfully passed MD5 checksum test. Continuing.\n"
tar -xf ${PKGNAME}-${PKGVER}.tar.bz2

# Prepare and build
cd ${PKGNAME}-${PKGVER}

# Uncomment to install more tools
TOOLS=(
	#as10k1
	#echomixer
	#envy24control
	#hda-verb
	# hdajackretask  # fails to build
	#hdajacksensetest
	#hdspconf
	#hdsploader
	hdspmixer
	#hwmixvolume
	#ld10k1
	#mixartloader
	#pcxhrloader
	# qlo10k1  # disabled, because build is broken
	rmedigicontrol
	#sb16_csp
	#seq/sbiload
	#sscape_ctl
	#vxloader
	#us428control
	#usx2yloader
)

# Prepare
printf "Preparing package.\n\n"
sleep 3

for tool in "${TOOLS[@]}"; do
	(
		cd ${PKGDIR}/${PKGNAME}-${PKGVER}/$tool
		autoreconf -vfi
	)
done

# Build
printf "Building package.\n\n"
sleep 3

for tool in "${TOOLS[@]}"; do
	(
		cd ${PKGDIR}/${PKGNAME}-${PKGVER}/$tool
		./configure --prefix=/usr --sbindir=/usr/bin
		make
	)
done

# Install
printf "Installing package.\n\n"
sleep 3

for tool in "${TOOLS[@]}"; do
	sudo make install -C ${PKGDIR}/${PKGNAME}-${PKGVER}/$tool
done

# Prompt about final steps
echo "Successfully installed alsa tools: "${TOOLS[@]}""
printf "\nFor more information please check: https://www.alsa-project.org\n"

exit 0
