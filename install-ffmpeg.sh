#!/bin/bash
# Author: Nikos Toutountzoglou, nikos.toutountzoglou@svt.se
# Script: install-ffmpeg.sh
# Description: Install ffmpeg with Decklink, Intel QSV, NVIDIA GPU and AMF-AMD GPU support
# Revision: 1.2

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
WORKDIR="$HOME/src/release"

# FFmpeg
FFMPEG_VER="https://github.com/FFmpeg/FFmpeg/archive/refs/tags/n7.0.tar.gz"
FFMPEG_MD5="863b21e113d5fc7d7fd88f852fa11493"
PKGNAME="FFmpeg"
PKGVER="7.0"

# Blackmagic Decklink Drivers (v12.8.1) and SDK (v12.8)
BM_SDK="https://drive.usercontent.google.com/download?id=1fhrMWzObej_y4trdQocvKUY38zZhqwtl&confirm=y"
BM_SDK_MD5="3db11e07c032e9d17db8ad79d8b382de"
BM_DRV="https://drive.usercontent.google.com/download?id=1KEp4Q9589DLNk1PASKQHrhVOuKBLP2rg&confirm=y"
BM_DRV_MD5="117b9ee5dfb9b50a1c704dd2093a4bb7"

# Prompt user with yes/no before continuing
while true
do
	read -r -p "Install ffmpeg with Decklink, Intel QSV, NVIDIA GPU and AMF-AMD GPU support? (y/n) " yesno
	case "$yesno" in
		n|N) exit 0;;
		y|Y) break;;
		*) echo "Please answer 'y/n'.";;
	esac
done

# Download
mkdir -p ${WORKDIR}
cd ${WORKDIR}
# FFmpeg upstream source
echo "Downloading FFmpeg from upstream source."
curl -o ${PKGNAME}-n${PKGVER}.tar.gz -LO ${FFMPEG_VER}
# Decklink Drivers and SDK upstream source
echo "Downloading Decklink Drivers (12.8.1) and SDK (12.8)."
curl -o decklink_sdk.tar.gz -L ${BM_SDK}
curl -o decklink.tar.gz -L ${BM_DRV}

# Checksum
md5sum -c <<< "${FFMPEG_MD5} ${PKGNAME}-n${PKGVER}.tar.gz" && \
md5sum -c <<< "${BM_SDK_MD5} decklink_sdk.tar.gz" && \
md5sum -c <<< "${BM_DRV_MD5} decklink.tar.gz" || exit 1

echo "Downloaded files have successfully passed MD5 checksum test. Continuing."

# Unpack
echo "Extracting file '${PKGNAME}-n${PKGVER}.tar.gz'"
tar -xf ${PKGNAME}-n${PKGVER}.tar.gz
echo "Extracting files 'decklink_sdk.tar.gz' and 'decklink.tar.gz'"
tar -xf decklink_sdk.tar.gz
tar -xf decklink.tar.gz

# Enable Extra Packages for Enterprise Linux 9
echo "Enable EPEL, CRB and Development Tools."
sudo dnf install epel-release
sudo /usr/bin/crb enable
# Enable Development Tools
sudo dnf groupinstall "Development Tools"
# Update package repos cache
sudo dnf makecache

# Install SDK libs and DeviceConfigure binary
echo "Installing Decklink SDK libraries."
sudo cp -v -r --no-preserve='ownership' "Blackmagic_DeckLink_SDK_12.8/Linux/include"/* /usr/include
echo "Installing Decklink 'DeviceConfigure' binary in '/usr/local/bin' folder."
sudo cp -v --no-preserve='ownership' "Blackmagic_DeckLink_SDK_12.8/Linux/Samples/bin/x86_64/DeviceConfigure" /usr/local/bin

# Install decklink driver RPM package
echo "Installing Decklink drivers via RPM package."
sudo dnf install dkms kernel-headers-$(uname -r)
sudo rpm -Uvh "Blackmagic_Desktop_Video_Linux_12.8.1/rpm/x86_64/desktopvideo-12.8.1a1.x86_64.rpm"
echo "Make sure to import 'mokutil key' in UEFI systems with Secure Boot enabled."

# Prerequisites

# Packages necessary for building ffmpeg
echo "Installing prerequisite packages."
sudo dnf install \
	autoconf \
	automake \
 	AMF-devel \
	cmake \
	intel-gmmlib-devel \
	intel-mediasdk-devel \
	libass-devel \
	libdrm-devel \
	libtool \
	libva-devel \
	libvorbis-devel \
	libogg-devel \
	libX11-devel \
	libva-devel \
	libva-utils \
	libssh-devel \
	libvpl-devel \
	libpciaccess-devel \
	mercurial \
	nasm \
	opencl-headers \
	ocl-icd-devel \
	openssl-devel \
	openjpeg2-devel \
 	openh264-devel \
	pkgconf-pkg-config \
	perl-devel \
	SDL2-devel \
	srt-devel \
	srt \
	texinfo \
	xwayland-devel \
	xorg-x11-server-devel \
	yasm \
	zlib-devel

# Install external libraries

# Install nvidia-cuda-toolkit
# https://developer.nvidia.com/cuda-downloads?target_os=Linux&target_arch=x86_64&Distribution=Rocky&target_version=9
echo "Enable NVIDIA CUDA Toolkit repo."
sudo dnf config-manager \
	--add-repo https://developer.download.nvidia.com/compute/cuda/repos/rhel9/x86_64/cuda-rhel9.repo
sudo dnf clean all
sudo dnf install cuda-toolkit-12-4

# Install ffnvcodec-headers
echo "Installing 'ffnvcodec-headers'."
git clone https://git.videolan.org/git/ffmpeg/nv-codec-headers.git
cd nv-codec-headers
make PREFIX='/usr'
sudo make PREFIX='/usr' install
cd ${WORKDIR}

# Install libx264
echo "Installing 'libx264'."
git clone https://code.videolan.org/videolan/x264.git
cd x264
./configure \
	--prefix='/usr' \
	--enable-shared \
	--enable-pic \
	--enable-lto \
	--disable-avs
make
sudo make install
cd ${WORKDIR}

# Install libx265
echo "Installing 'libx265'."
git clone https://bitbucket.org/multicoreware/x265_git
cd x265_git/build/linux
cmake -G "Unix Makefiles" ../../source -DCMAKE_INSTALL_PREFIX=/usr
cmake ../../source -DCMAKE_INSTALL_PREFIX=/usr
make
sudo make install
cd ${WORKDIR}

# Install zvbi (Teletext)
echo "Installing 'libzvbi' (Teletext)."
curl -LO https://sourceforge.net/projects/zapping/files/zvbi/0.2.35/zvbi-0.2.35.tar.bz2
tar -xf zvbi-0.2.35.tar.bz2
cd zvbi-0.2.35
./configure --prefix='/usr' --sbindir='/usr/bin'
make
sudo make install
cd ${WORKDIR}

# Install klvanc (VANC SMPTE2038)
echo "Installing 'libklvanc' (VANC SMPTE2038)."
git clone https://github.com/stoth68000/libklvanc.git
cd libklvanc
./autogen.sh --build
./configure --prefix='/usr'
make
sudo make install
cd ${WORKDIR}

# Update ldconfig
echo "Updating 'ldconfig' and 'updatedb'."
sudo ldconfig
sudo updatedb

# Install ffmpeg release n7.0
echo "Installing 'ffmpeg' version ${PKGVER}."
cd ${PKGNAME}-n${PKGVER}
export PKG_CONFIG_PATH="$PKG_CONFIG_PATH:/usr/lib/pkgconfig:/usr/lib64/pkgconfig"
./configure \
	--prefix='/usr' \
	--disable-htmlpages \
	--disable-debug \
 	--enable-amf \
	--enable-decklink \
	--enable-gpl \
	--enable-libdrm \
	--enable-libopenjpeg \
	--enable-libklvanc \
 	--enable-libopenh264 \
	--enable-libssh \
	--enable-libsrt \
	--enable-libvpl \
	--enable-libzvbi \
	--enable-libx264 \
	--enable-libx265 \
	--enable-nvdec \
	--enable-nvenc \
	--enable-nonfree \
	--enable-openssl \
	--enable-opencl \
	--enable-pic \
	--enable-runtime-cpudetect \
	--enable-vaapi
make
sudo make install

# Exit
echo "All done. Downloaded sources are stored in folder '${WORKDIR}'."
sudo ldconfig
sudo updatedb
exit 0
