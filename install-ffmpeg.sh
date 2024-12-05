#!/usr/bin/env bash
# Author: Nikos Toutountzoglou, nikos.toutountzoglou@svt.se
# Script: install-ffmpeg.sh
# Description: Install ffmpeg with Decklink, Intel QSV, NVIDIA GPU and AMF-AMD GPU support
# Revision: 1.8

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
WORKDIR="$HOME/src/release/rocky9-ffmpeg"

# FFmpeg
PKGNAME="FFmpeg"
PKGVER="7.1"
FFMPEG_VER="https://github.com/${PKGNAME}/${PKGNAME}/archive/refs/tags/n${PKGVER}.tar.gz"
FFMPEG_MD5="03485098fb64a000a4f7cd97e468dfff"

# Blackmagic Decklink Drivers and SDK
BM_SDK="https://drive.usercontent.google.com/download?id=11LUclY1tBLfkAGvu93PaxVpZEmyoKVTE&confirm=y"
BM_SDK_MD5="8d6d32e917d1ea420ecbb2cb7e5fb68f"
BM_SDK_VER="14.2"
BM_DRV="https://drive.usercontent.google.com/download?id=1l-H996Tc6bT8IWe0V74VcHC2NFPwJQKG&confirm=y"
BM_DRV_MD5="5132e25f441c6a3af9fbdc45d2fc4d75"
BM_DRV_VER="14.2"

# Prompt user with yes/no before continuing
while true; do
	read -r -p "Install ffmpeg with Decklink, Intel QSV, NVIDIA GPU and AMF-AMD GPU support? (y/n) " yesno
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

# FFmpeg upstream source
echo "Downloading FFmpeg from upstream source."
curl -# -o ${PKGNAME}-n${PKGVER}.tar.gz -LO ${FFMPEG_VER}

# Decklink Drivers and SDK upstream source
echo "Downloading Decklink Drivers v${BM_DRV_VER} and SDK v${BM_SDK_VER}."
curl -# -o decklink_sdk.tar.gz -LO ${BM_SDK}
curl -# -o decklink.tar.gz -LO ${BM_DRV}

# Checksum
echo ${FFMPEG_MD5} ${PKGNAME}-n${PKGVER}.tar.gz | md5sum -c &&
	echo ${BM_SDK_MD5} decklink_sdk.tar.gz | md5sum -c &&
	echo ${BM_DRV_MD5} decklink.tar.gz | md5sum -c || exit 1

echo "Downloaded files have successfully passed MD5 checksum test. Continuing."

# Unpack
echo "Extracting file '${PKGNAME}-n${PKGVER}.tar.gz'"
tar -xf ${PKGNAME}-n${PKGVER}.tar.gz
echo "Extracting files 'decklink_sdk.tar.gz' and 'decklink.tar.gz'"
tar -xf decklink_sdk.tar.gz
tar -xf decklink.tar.gz

# Enable Extra Packages for Enterprise Linux 9
echo "Enable EPEL, CRB and Development Tools."
sudo dnf install -y epel-release
sudo /usr/bin/crb enable
# Enable Development Tools
sudo dnf groupinstall -y "Development Tools"
# Update package repos cache
sudo dnf makecache

# Install SDK libs and DeviceConfigure binary
echo "Installing Decklink SDK libraries."
sudo cp -v -r --no-preserve='ownership' "Blackmagic_DeckLink_SDK_${BM_SDK_VER}/Linux/include"/* /usr/include
echo "Installing Decklink 'DeviceConfigure' binary in '/usr/local/bin' folder."
sudo cp -v --no-preserve='ownership' "Blackmagic_DeckLink_SDK_${BM_SDK_VER}/Linux/Samples/bin/x86_64/DeviceConfigure" /usr/local/bin

# Install decklink driver RPM package
echo "Installing Decklink drivers via RPM package."
sudo dnf install dkms kernel-headers-$(uname -r)
sudo rpm -Uvh "Blackmagic_Desktop_Video_Linux_${BM_DRV_VER}/rpm/x86_64/desktopvideo-${BM_DRV_VER}*.rpm"
echo "Make sure to import 'mokutil key' in UEFI systems with Secure Boot enabled."

# Prerequisites

# Packages necessary for building ffmpeg
echo "Installing prerequisite packages."
sudo dnf install -y \
	AMF-devel \
	autoconf \
	automake \
	clang \
	cmake \
	glibc \
	intel-gmmlib-devel \
	intel-mediasdk-devel \
	libass-devel \
	libdrm-devel \
	libogg-devel \
	libpciaccess-devel \
	libssh-devel \
	libtool \
	libva-devel \
	libva-utils \
	libvorbis-devel \
	libvpl-devel \
	libX11-devel \
	mercurial \
	mlocate \
	nasm \
	numactl-devel \
	numactl-libs \
	ocl-icd-devel \
	opencl-headers \
	openh264-devel \
	openjpeg2-devel \
	openssl-devel \
	perl-devel \
	pkgconf-pkg-config \
	SDL2-devel \
	srt \
	srt-devel \
	texinfo \
	xorg-x11-server-devel \
	xwayland-devel \
	yasm \
	zlib-devel

# Install external libraries

# Install nvidia-cuda-toolkit
# https://developer.nvidia.com/cuda-downloads?target_os=Linux&target_arch=x86_64&Distribution=Rocky&target_version=9
echo "Enable NVIDIA CUDA Toolkit repo."
CUDA_VER="12.6.3"
CUDA_RPM="cuda-repo-rhel9-12-6-local-${CUDA_VER}_560.35.05-1.x86_64.rpm"
CUDA_RPM_URL="https://developer.download.nvidia.com/compute/cuda/${CUDA_VER}/local_installers/${CUDA_RPM}"

if [ $(dnf list installed cuda-toolkit-12-* &>/dev/null && echo $? || echo $?) -eq 1 ]; then
	curl -# -o ${CUDA_RPM} -LO ${CUDA_RPM_URL}
	sudo rpm -i ${CUDA_RPM}
	sudo dnf clean all
	sudo dnf -y install cuda-toolkit-12-6
	sudo ldconfig
else
	echo "Already enabled, skipping."
fi

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
	--disable-avs \
	--enable-lto \
	--enable-pic \
	--enable-shared
make
sudo make install
cd ${WORKDIR}

# Install libx265
echo "Installing 'libx265'."
git clone https://bitbucket.org/multicoreware/x265_git
cd x265_git/build/linux
cmake -G "Unix Makefiles" ../../source -DCMAKE_INSTALL_PREFIX=/usr -Wno-dev
cmake ../../source -DCMAKE_INSTALL_PREFIX=/usr -Wno-dev
make
sudo make install
cd ${WORKDIR}

# Install zvbi (Teletext)
echo "Installing 'libzvbi' (Teletext)."
curl -# -LO https://sourceforge.net/projects/zapping/files/zvbi/0.2.35/zvbi-0.2.35.tar.bz2
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

# Install ffmpeg
echo "Installing 'ffmpeg' version ${PKGVER}."
cd ${PKGNAME}-n${PKGVER}
export PKG_CONFIG_PATH="$PKG_CONFIG_PATH:/usr/lib/pkgconfig:/usr/lib64/pkgconfig"
./configure \
	--prefix='/usr' \
	--disable-debug \
	--disable-htmlpages \
	--enable-amf \
	--enable-decklink \
	--enable-gpl \
	--enable-libdrm \
	--enable-libklvanc \
	--enable-libopenh264 \
	--enable-libopenjpeg \
	--enable-libsrt \
	--enable-libssh \
	--enable-libvpl \
	--enable-libx264 \
	--enable-libx265 \
	--enable-libzvbi \
	--enable-nonfree \
	--enable-nvdec \
	--enable-nvenc \
	--enable-opencl \
	--enable-openssl \
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
