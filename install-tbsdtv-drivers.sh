#!/usr/bin/env bash
# Author: Nikos Toutountzoglou, nikos.toutountzoglou@svt.se
# Script: install-tbsdtv-drivers.sh
# Description: Install TBSDTV Open Source Linux Driver Offline Package
# Upstream source instructions: https://www.tbsdtv.com/forum/viewtopic.php?f=87&t=25949
# Revision: 1.0

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
WORKDIR="$HOME/src/release/tbsdtv"

# TSDuck RPM package
PKGNAME="tbs-open-linux-drivers"
PKGVER="20240829"
TBSDTV_VER="https://www.tbsiptv.com/download/common/${PKGNAME}_v${PKGVER}.zip"
TBSDTV_MD5="79d8e913a679f87bcbe74a8ce0b93858"

# Prompt user with yes/no before continuing
while true; do
        read -r -p "Install TBSDTV Open Source Linux Driver Offline Package? (y/n) " yesno
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

# Enable Extra Packages for Enterprise Linux 9
printf "Enabling Extra Packages for Enterprise Linux 9 and Development Tools.\n"
sudo dnf install -y epel-release
sudo /usr/bin/crb enable
sudo dnf makecache

# TSDuck upstream source
printf "Downloading TBSDTV source linux driver from upstream source.\n"
curl -# -LO ${TBSDTV_VER}

# Checksum
echo ${TBSDTV_MD5} ${PKGNAME}_v${PKGVER}.zip | md5sum -c || exit 1

printf "Downloaded file(s) have successfully passed MD5 checksum test. Continuing.\n"

# Prerequisites

# Packages necessary for building tsduck
printf "Installing prerequisite packages.\n"
sudo dnf install -y bzip2 curl gcc kernel-devel kernel-headers patch patchutils perl perl-devel perl-ExtUtils-CBuilder perl-ExtUtils-MakeMaker perl-Proc-ProcessTable tar zip

# Install TBSDTV driver package
printf "Installing 'tbs-open-linux-drivers' via upstream offline source.\n"

# Step 1 - Unpack package
unzip ${PKGNAME}_v${PKGVER}.zip
tar -xf media_build-2024-08-29.tar.bz2

# Step 2 - Patch and fix
sed -e 's/ dvb_math\.o//g' -i media_build/linux/drivers/media/dvb-core/Makefile
rm -v \
        media_build/backports/v6.3_class_create.patch \
        media_build/backports/v6.2_class.patch \
        media_build/backports/v6.1_class.patch \
        media_build/backports/v5.18_rc.patch \
        media_build/backports/v5.17_iosys.patch \
        media_build/backports/v5.14_bus_void_return.patch

cd media_build
./patch-kernel.sh

# Step 3 - Build
make

# Step 4 - Install
printf "Final step - Installation of TBSDTV drivers in the current system and kernel\n"
while true; do
        read -r -p "Proceed with installation? (y/n) " yesno
        case "$yesno" in
        n | N) exit 0 ;;
        y | Y) break ;;
        *) printf "Please answer 'y/n'.\n" ;;
        esac
done

sudo make install

# Exit
printf "All done. Downloaded sources are stored in folder '${WORKDIR}'.\n"
printf 'NOTE: To uninstall/remove TBSDTV drivers, type:\nsudo rm -rf /lib/modules/$(uname -r)/updates/extra\n'

exit 0
