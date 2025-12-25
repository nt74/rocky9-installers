#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# UNIVERSAL FFmpeg INSTALLER (Rocky Linux 9)
# - Consolidates all FFmpeg installers into one interactive flow
# - Supports grouped codec selection + hardware acceleration
# - Keeps local patch folder usage
# ============================================================

# ----------------------------
# 1) CONFIGURATION & VERSIONS
# ----------------------------

FFMPEG_VERSION="${FFMPEG_VERSION:-8.0.1}"
FFMPEG_URL="https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz"

PREFIX="${PREFIX:-/usr/local}"

# H.264 / H.265
X264_URL="https://code.videolan.org/videolan/x264.git"
X265_VERSION="${X265_VERSION:-4.1}"
X265_URL="http://ftp.videolan.org/pub/videolan/x265/x265_${X265_VERSION}.tar.gz"

# MPEG-5 EVC
XEVD_URL="https://github.com/mpeg5/xevd.git"
XEVE_URL="https://github.com/mpeg5/xeve.git"

# SRT
LIBSRT_VERSION="${LIBSRT_VERSION:-1.5.4}"
LIBSRT_URL="https://github.com/Haivision/srt/archive/refs/tags/v${LIBSRT_VERSION}.tar.gz"

# RPM Fusion
RPMFUSION_FREE_URL="https://mirrors.rpmfusion.org/free/el/rpmfusion-free-release-9.noarch.rpm"
RPMFUSION_NONFREE_URL="https://mirrors.rpmfusion.org/nonfree/el/rpmfusion-nonfree-release-9.noarch.rpm"

# NVIDIA
CUDA_REPO_URL="https://developer.download.nvidia.com/compute/cuda/repos/rhel9/x86_64/cuda-rhel9.repo"
CUDA_PKG="${CUDA_PKG:-cuda-toolkit-12-9}"
CUDA_HOME_VER="${CUDA_HOME_VER:-12.9}"
CUDA_HOME="/usr/local/cuda-${CUDA_HOME_VER}"
NV_CODEC_HEADERS_URL="https://github.com/FFmpeg/nv-codec-headers.git"

# DeckLink SDK
DECKLINK_SDK_URL="${DECKLINK_SDK_URL:-https://drive.usercontent.google.com/download?id=1iNUWVz2yQ2eawwO45x3OKg0tfoy3yfkg&export=download&authuser=0&confirm=t}"
DECKLINK_SDK_MD5="${DECKLINK_SDK_MD5:-6454f6bf36314360981656ae25d7952b}"

# Patch handling (prefer local patch/)
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PATCH_DIR="${SCRIPT_DIR}/patch"
DECKLINK_PATCH_FILE="${PATCH_DIR}/ffmpeg-decklink-sdk15-compat.patch"
DECKLINK_PATCH_MD5="${DECKLINK_PATCH_MD5:-6a193dd59ca9b075461ad2fb42079638}"

# Build dir
BUILD_ROOT="${BUILD_ROOT:-$(pwd)}"
BUILD_DIR="${BUILD_ROOT}/ffmpeg_build"

# ----------------------------
# 2) HELPER FUNCTIONS
# ----------------------------

green() { printf "\033[0;32m%s\033[0m\n" "$*"; }
yellow() { printf "\033[0;33m%s\033[0m\n" "$*"; }
red() { printf "\033[0;31m%s\033[0m\n" "$*"; }
cyan() { printf "\033[0;36m%s\033[0m\n" "$*"; }

die() {
	red "[ERR] $*"
	exit 1
}

require_root() {
	if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
		die "Run as root (this installer performs system-wide installs)."
	fi
}

ask_yes_no() {
	local prompt="$1"
	local default="${2:-N}"
	local ps de ans
	if [[ "$default" == "Y" ]]; then
		ps="[Y/n]"
		de=0
	else
		ps="[y/N]"
		de=1
	fi
	read -r -p "$prompt $ps " ans || true
	if [[ -z "${ans:-}" ]]; then return "$de"; fi
	case "$ans" in
	[yY]*) return 0 ;;
	[nN]*) return 1 ;;
	*) return "$de" ;;
	esac
}

check_md5() {
	local f="$1"
	local expected="$2"
	[[ -z "$expected" ]] && return 0
	[[ ! -f "$f" ]] && return 0

	if command -v md5sum >/dev/null 2>&1; then
		local actual
		actual="$(md5sum "$f" | awk '{print $1}')"
		if [[ "$actual" != "$expected" ]]; then
			red "[ERR] MD5 mismatch for $f"
			red "      Expected: $expected"
			red "      Actual:   $actual"
			ask_yes_no "Continue anyway?" "N" || exit 1
		else
			green "[OK] MD5 verified: $f"
		fi
	else
		yellow "[WARN] md5sum not found; skipping checksum validation for $f"
	fi
}

safe_install_url() {
	local url="$1"
	local desc="$2"
	cyan "Checking availability for: $desc"
	if ! curl --output /dev/null --silent --head --fail --connect-timeout 7 "$url"; then
		red "[ERR] Cannot reach URL for $desc: $url"
		if ask_yes_no "Retry?" "Y"; then
			safe_install_url "$url" "$desc"
			return $?
		elif ask_yes_no "Skip this package?" "N"; then
			return 1
		else
			exit 1
		fi
	fi

	dnf install -y --nogpgcheck "$url" || die "Install failed for $desc"
	green "[OK] Installed: $desc"
}

ensure_cmd() {
	local cmd="$1"
	local pkg="$2"
	if ! command -v "$cmd" >/dev/null 2>&1; then
		dnf install -y "$pkg" >/dev/null 2>&1 || true
	fi
}

# ----------------------------
# 3) HARDWARE DETECTION
# ----------------------------

detect_hw() {
	ensure_cmd lspci pciutils

	CPU_VENDOR="$(grep -m1 "vendor_id" /proc/cpuinfo | awk '{print $3}' || true)"
	CPU_MODEL="$(grep -m1 "model name" /proc/cpuinfo | awk -F: '{print $2}' | xargs || true)"

	HW_NV=false
	HW_QSV=false
	HW_AMF=false
	HW_DL=false

	if lspci -nn | grep -E "\[03..\]" | grep -q "\[10de:"; then HW_NV=true; fi
	if lspci -nn | grep -E "\[03..\]" | grep -q "\[8086:"; then HW_QSV=true; fi
	if lspci -nn | grep -E "\[03..\]" | grep -q "\[1002:"; then HW_AMF=true; fi
	if lspci | grep -i "blackmagic" >/dev/null 2>&1; then HW_DL=true; fi

	DEF_CUDA="N"
	[[ "$HW_NV" == "true" ]] && DEF_CUDA="Y"
	DEF_QSV="N"
	[[ "$HW_QSV" == "true" ]] && DEF_QSV="Y"
	DEF_AMF="N"
	[[ "$HW_AMF" == "true" ]] && DEF_AMF="Y"
	DEF_DECK="N"
	[[ "$HW_DL" == "true" ]] && DEF_DECK="Y"
}

print_hw_summary() {
	green "############################################################"
	green "###  UNIVERSAL FFMPEG INSTALLER (Rocky 9)                ###"
	green "############################################################"
	echo ""
	echo "System Information:"
	cyan "  CPU Vendor: $CPU_VENDOR"
	cyan "  CPU Model:  $CPU_MODEL"
	echo ""
	echo "Graphics & Accelerators:"
	[[ "$HW_NV" == "true" ]] && green "  [+] NVIDIA GPU found (NVENC Available)" || yellow "  [-] No NVIDIA GPU detected"
	[[ "$HW_QSV" == "true" ]] && green "  [+] Intel iGPU found (QuickSync Available)" || yellow "  [-] No Intel Graphics detected"
	[[ "$HW_AMF" == "true" ]] && green "  [+] AMD GPU found (AMF Available)" || yellow "  [-] No AMD GPU detected"
	[[ "$HW_DL" == "true" ]] && green "  [+] DeckLink Device found" || yellow "  [-] No DeckLink Device found"
	echo ""
}

# ----------------------------
# 4) USER CONFIGURATION
# ----------------------------

choose_profile() {
	cyan "Choose installation profile:"
	echo "  1) Minimal (FFmpeg + basic libs from dnf)"
	echo "  2) Broadcast (DeckLink + pro libs)"
	echo "  3) GPU Accelerated (NVENC/QSV/AMF)"
	echo "  4) Full (everything)"
	echo "  5) Custom (answer prompts)"
	echo ""

	local choice
	read -r -p "Select profile [1-5] (default: 5): " choice || true
	choice="${choice:-5}"

	# Defaults
	DO_REPOS=true
	DO_BUILD_VIDEO_LIBS=false
	DO_BUILD_AUDIO_LIBS=false
	DO_BUILD_NETWORK_LIBS=false
	DO_ENABLE_AUDIO_IO=false
	DO_CUDA=false
	DO_QSV=false
	DO_AMF=false
	DO_DECK=false
	DO_PATCH=false
	DO_FFMPEG=true

	case "$choice" in
	1)
		# Minimal
		DO_REPOS=true
		DO_FFMPEG=true
		;;
	2)
		# Broadcast
		DO_REPOS=true
		DO_BUILD_VIDEO_LIBS=true
		DO_BUILD_AUDIO_LIBS=true
		DO_BUILD_NETWORK_LIBS=true
		DO_ENABLE_AUDIO_IO=true
		DO_DECK=true
		DO_PATCH=true
		;;
	3)
		# GPU
		DO_REPOS=true
		DO_BUILD_VIDEO_LIBS=true
		DO_BUILD_AUDIO_LIBS=true
		DO_BUILD_NETWORK_LIBS=true
		DO_ENABLE_AUDIO_IO=true
		DO_CUDA=true
		DO_QSV=true
		DO_AMF=true
		;;
	4)
		# Full
		DO_REPOS=true
		DO_BUILD_VIDEO_LIBS=true
		DO_BUILD_AUDIO_LIBS=true
		DO_BUILD_NETWORK_LIBS=true
		DO_ENABLE_AUDIO_IO=true
		DO_CUDA=true
		DO_QSV=true
		DO_AMF=true
		DO_DECK=true
		DO_PATCH=true
		;;
	*)
		# Custom (interactive)
		ask_yes_no "1. Run DNF Setup (Repos & System Libs)?" "Y" && DO_REPOS=true || DO_REPOS=false

		echo ""
		cyan "Codec/Feature Groups:"
		ask_yes_no "2. Build video codec libs (x264/x265/EVC)?" "Y" && DO_BUILD_VIDEO_LIBS=true
		ask_yes_no "3. Build audio codec libs (fdk-aac/opus/lame/vorbis)?" "Y" && DO_BUILD_AUDIO_LIBS=true
		ask_yes_no "4. Build network libs (SRT)?" "Y" && DO_BUILD_NETWORK_LIBS=true
		ask_yes_no "5. Enable ALSA/PulseAudio I/O support?" "Y" && DO_ENABLE_AUDIO_IO=true

		echo ""
		cyan "Hardware Acceleration:"
		ask_yes_no "6. Enable NVIDIA CUDA/NVENC?" "$DEF_CUDA" && DO_CUDA=true
		ask_yes_no "7. Enable Intel QSV (QuickSync) & VAAPI?" "$DEF_QSV" && DO_QSV=true
		ask_yes_no "8. Enable AMD AMF Headers?" "$DEF_AMF" && DO_AMF=true

		echo ""
		cyan "Broadcast:"
		ask_yes_no "9. Enable DeckLink SDK (15.x)?" "$DEF_DECK" && DO_DECK=true
		if [[ "$DO_DECK" == "true" ]]; then
			ask_yes_no "10. Apply DeckLink compatibility patch from ./patch/ ?" "Y" && DO_PATCH=true
		fi

		echo ""
		ask_yes_no "11. Build & install FFmpeg ${FFMPEG_VERSION}?" "Y" && DO_FFMPEG=true || DO_FFMPEG=false
		;;
	esac
}

# ----------------------------
# 5) REPOS & SYSTEM PACKAGES
# ----------------------------

install_prereqs() {
	cyan "--- Configuring Base Repos ---"
	dnf install -y epel-release
	crb enable || true

	if ! dnf repolist | grep -q "rpmfusion-free"; then
		safe_install_url "$RPMFUSION_FREE_URL" "RPMFusion Free"
	fi
	if ! dnf repolist | grep -q "rpmfusion-nonfree"; then
		safe_install_url "$RPMFUSION_NONFREE_URL" "RPMFusion Non-Free"
	fi

	cyan "--- Installing Build Tools ---"
	dnf groupinstall -y "Development Tools"
	dnf install -y cmake nasm yasm pkgconfig wget curl git automake autoconf libtool \
		bzip2 xz zlib-devel openssl-devel libgomp \
		dkms kernel-devel kernel-headers

	cyan "--- Installing Core Multimedia Development Libs ---"
	# Baseline set (works for most)
	dnf install -y \
		mbedtls-devel cjson-devel \
		libdav1d-devel svt-av1-devel fdk-aac-free-devel \
		libklvanc-devel libvpx-devel libvorbis-devel opus-devel lame-devel \
		libass-devel freetype-devel \
		openjpeg2-devel libxml2-devel zeromq-devel libv4l-devel \
		librsvg2-devel \
		libjpeg-turbo-devel libpng-devel libtiff-devel libwebp-devel jbigkit-devel

	# Optional network libs / broadcast libs (still OK to install even if group disabled)
	dnf install -y librist-devel || true

	if [[ "${DO_ENABLE_AUDIO_IO}" == "true" ]]; then
		dnf install -y alsa-lib-devel pulseaudio-libs-devel
	fi

	if [[ "${DO_QSV}" == "true" ]]; then
		dnf install -y libmfx-devel intel-media-driver libva-intel-driver libvpl-devel libva-devel libdrm-devel || true
	else
		# still good to have VAAPI libs if doing video work
		dnf install -y libva-devel libdrm-devel || true
	fi

	if [[ "${DO_AMF}" == "true" ]]; then
		dnf install -y mesa-dri-drivers libva-utils AMF-devel || true
	fi
}

export_paths() {
	export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig:${PREFIX}/lib64/pkgconfig:${PKG_CONFIG_PATH:-}"
	export LD_LIBRARY_PATH="${PREFIX}/lib:${PREFIX}/lib64:${LD_LIBRARY_PATH:-}"
	export PATH="${PREFIX}/bin:$PATH"
}

# ----------------------------
# 6) HARDWARE SETUP (OPTIONAL)
# ----------------------------

setup_nvidia() {
	cyan "--- Setting up NVIDIA CUDA + nv-codec-headers ---"

	if ! command -v nvcc >/dev/null 2>&1; then
		dnf config-manager --add-repo "$CUDA_REPO_URL" || true
		dnf install -y "$CUDA_PKG" --setopt=install_weak_deps=False
	fi

	[[ -d "$CUDA_HOME" ]] && export PATH="${CUDA_HOME}/bin:$PATH"

	cd "$BUILD_DIR"
	if [[ ! -d "nv-codec-headers" ]]; then
		git clone "$NV_CODEC_HEADERS_URL" nv-codec-headers
	fi
	cd nv-codec-headers
	make -j"$(nproc)" PREFIX="${PREFIX}"
	make install PREFIX="${PREFIX}"
}

setup_decklink() {
	cyan "--- Setting up DeckLink SDK ---"

	cd "$BUILD_DIR"
	if [[ ! -f "decklink_sdk.tar.gz" ]]; then
		wget -O "decklink_sdk.tar.gz" "$DECKLINK_SDK_URL"
	fi
	check_md5 "decklink_sdk.tar.gz" "$DECKLINK_SDK_MD5"

	rm -rf decklink_sdk
	mkdir -p decklink_sdk
	tar xf "decklink_sdk.tar.gz" -C decklink_sdk --strip-components=1 2>/dev/null || tar xf "decklink_sdk.tar.gz" -C decklink_sdk

	local dl_inc
	dl_inc="$(find "${BUILD_DIR}/decklink_sdk" -name "DeckLinkAPI.h" -printf "%h\n" | head -n 1 || true)"

	if [[ -n "$dl_inc" ]]; then
		mkdir -p "${PREFIX}/include"
		find "$dl_inc" -type f \( -name '*.h' -o -name '*.cpp' \) -exec cp -f {} "${PREFIX}/include/" \;
		green "[OK] DeckLink SDK headers installed into ${PREFIX}/include."
	else
		die "DeckLink headers not found in extracted SDK."
	fi
}

# ----------------------------
# 7) SOURCE BUILDS (OPTIONAL)
# ----------------------------

build_srt() {
	cyan "--- Building SRT (v${LIBSRT_VERSION}) ---"
	cd "$BUILD_DIR"

	if [[ -d "srt-source" ]]; then
		yellow "SRT already present; skipping."
		return
	fi

	wget -O srt.tar.gz "$LIBSRT_URL"
	mkdir -p srt-source
	tar xf srt.tar.gz -C srt-source --strip-components=1
	cd srt-source
	cmake -DCMAKE_INSTALL_PREFIX="${PREFIX}" -DENABLE_SHARED=ON -DENABLE_STATIC=ON -DENABLE_APPS=OFF .
	make -j"$(nproc)"
	make install
}

build_x264() {
	cyan "--- Building x264 ---"
	cd "$BUILD_DIR"

	if [[ -d "x264-source" ]]; then
		yellow "x264 already present; skipping."
		return
	fi

	git clone "$X264_URL" x264-source
	cd x264-source
	./configure --prefix="${PREFIX}" --bindir="${PREFIX}/bin" --enable-static --enable-pic
	make -j"$(nproc)"
	make install
}

build_x265() {
	cyan "--- Building x265 (v${X265_VERSION}) ---"
	cd "$BUILD_DIR"

	if [[ -d "x265-source" ]]; then
		yellow "x265 already present; skipping."
		return
	fi

	wget -O x265.tar.gz "$X265_URL"
	mkdir -p x265-source
	tar xf x265.tar.gz -C x265-source --strip-components=1
	cd x265-source/build/linux
	cmake -G "Unix Makefiles" ../../source -DCMAKE_INSTALL_PREFIX="${PREFIX}" -DENABLE_SHARED=ON
	make -j"$(nproc)"
	make install
}

build_xevd() {
	cyan "--- Building MPEG-5 EVC Decoder (xevd) ---"
	cd "$BUILD_DIR"

	if [[ -d "xevd-source" ]]; then
		yellow "xevd already present; skipping."
		return
	fi

	git clone "$XEVD_URL" xevd-source
	cd xevd-source
	mkdir -p build
	cd build
	cmake -DCMAKE_INSTALL_PREFIX="${PREFIX}" -DCMAKE_BUILD_TYPE=Release ..
	make -j"$(nproc)"
	make install
}

build_xeve() {
	cyan "--- Building MPEG-5 EVC Encoder (xeve) ---"
	cd "$BUILD_DIR"

	if [[ -d "xeve-source" ]]; then
		yellow "xeve already present; skipping."
		return
	fi

	git clone "$XEVE_URL" xeve-source
	cd xeve-source
	mkdir -p build
	cd build
	cmake -DCMAKE_INSTALL_PREFIX="${PREFIX}" -DCMAKE_BUILD_TYPE=Release ..
	make -j"$(nproc)"
	make install
}

# ----------------------------
# 8) FFMPEG BUILD
# ----------------------------

fetch_ffmpeg() {
	cd "$BUILD_DIR"
	cyan "--- Fetching FFmpeg ${FFMPEG_VERSION} ---"

	if ! wget -q --spider "$FFMPEG_URL"; then
		yellow "FFmpeg tarball not found at ${FFMPEG_URL}. Falling back to Git master."
		rm -rf ffmpeg-src
		git clone https://git.ffmpeg.org/ffmpeg.git ffmpeg-src
	else
		[[ -f ffmpeg.tar.xz ]] || wget -c -O ffmpeg.tar.xz "$FFMPEG_URL"
		rm -rf ffmpeg-src
		mkdir -p ffmpeg-src
		tar xf ffmpeg.tar.xz -C ffmpeg-src --strip-components=1
	fi
}

apply_decklink_patch() {
	[[ "${DO_PATCH}" != "true" ]] && return 0

	if [[ ! -f "$DECKLINK_PATCH_FILE" ]]; then
		die "Patch file not found: $DECKLINK_PATCH_FILE"
	fi

	cyan "--- Applying DeckLink patch: ${DECKLINK_PATCH_FILE} ---"
	check_md5 "$DECKLINK_PATCH_FILE" "$DECKLINK_PATCH_MD5"

	patch -p1 <"$DECKLINK_PATCH_FILE" || yellow "[WARN] Patch failed or already applied."
}

build_ffmpeg() {
	cd "$BUILD_DIR/ffmpeg-src"
	cyan "--- Configuring FFmpeg ---"

	local cfg=(
		"--prefix=${PREFIX}"
		"--bindir=${PREFIX}/bin"
		"--pkg-config-flags=--static"
		"--extra-cflags=-I${PREFIX}/include"
		"--extra-ldflags=-L${PREFIX}/lib -L${PREFIX}/lib64"
		"--extra-libs=-lpthread -lm"
		"--enable-gpl"
		"--enable-nonfree"
		"--enable-version3"
		"--enable-openssl"
		"--enable-protocol=https"
		"--enable-libopenjpeg"
		"--enable-libxml2"
		"--enable-libzmq"
		"--enable-librsvg"
		"--enable-libv4l2"
		"--enable-libass"
		"--enable-libfreetype"
		"--enable-libvpx"
	)

	# --- Network libs ---
	if [[ "${DO_BUILD_NETWORK_LIBS}" == "true" ]]; then
		cfg+=("--enable-libsrt")
	fi
	cfg+=("--enable-librist") # installed via dnf in prereqs (safe even if unused)

	# --- Audio codecs ---
	if [[ "${DO_BUILD_AUDIO_LIBS}" == "true" ]]; then
		cfg+=(
			"--enable-libfdk-aac"
			"--enable-libvorbis"
			"--enable-libopus"
			"--enable-libmp3lame"
		)
	fi

	# --- Audio I/O ---
	if [[ "${DO_ENABLE_AUDIO_IO}" == "true" ]]; then
		cfg+=("--enable-alsa" "--enable-libpulse")
	fi

	# --- Video libs ---
	if [[ "${DO_BUILD_VIDEO_LIBS}" == "true" ]]; then
		cfg+=("--enable-libx264" "--enable-libx265" "--enable-libxevd" "--enable-libxeve")
	fi

	# --- AV1 libs ---
	cfg+=("--enable-libsvtav1" "--enable-libdav1d")

	# --- VAAPI baseline (if libs exist) ---
	cfg+=("--enable-vaapi")

	# --- DeckLink ---
	if [[ "${DO_DECK}" == "true" ]]; then
		cfg+=("--enable-decklink")
	fi

	# --- NVIDIA ---
	if [[ "${DO_CUDA}" == "true" ]]; then
		cfg+=(
			"--enable-cuda-nvcc"
			"--enable-nvenc"
			"--enable-libnpp"
			"--extra-cflags=-I${CUDA_HOME}/include"
			"--extra-ldflags=-L${CUDA_HOME}/lib64"
		)
	fi

	# --- Intel QSV ---
	if [[ "${DO_QSV}" == "true" ]]; then
		cfg+=("--enable-libmfx")
	fi

	# --- AMD AMF ---
	if [[ "${DO_AMF}" == "true" ]]; then
		cfg+=("--enable-amf")
	fi

	echo ""
	yellow "FFmpeg configuration flags:"
	printf '  %s\n' "${cfg[@]}"
	echo ""

	./configure "${cfg[@]}"
	make -j"$(nproc)"
	make install

	echo "${PREFIX}/lib" >/etc/ld.so.conf.d/ffmpeg-custom.conf
	echo "${PREFIX}/lib64" >>/etc/ld.so.conf.d/ffmpeg-custom.conf
	ldconfig

	green "FFmpeg installed into: ${PREFIX}/bin/ffmpeg"
}

verify_install() {
	echo ""
	green "DONE! Suggested verification:"
	echo "  ${PREFIX}/bin/ffmpeg -hide_banner -version"
	echo "  ${PREFIX}/bin/ffmpeg -hide_banner -codecs | grep -E 'evc|jpeg|x264|x265|svt|dav1d' || true"
	if [[ "${DO_DECK}" == "true" ]]; then
		echo "  ${PREFIX}/bin/ffmpeg -hide_banner -sinks decklink || true"
		echo "  ${PREFIX}/bin/ffmpeg -hide_banner -sources decklink || true"
	fi
}

# ----------------------------
# MAIN
# ----------------------------

main() {
	require_root
	clear

	detect_hw
	print_hw_summary
	choose_profile

	mkdir -p "$BUILD_DIR"
	cd "$BUILD_DIR"

	export_paths

	if [[ "${DO_REPOS}" == "true" ]]; then
		install_prereqs
	fi

	if [[ "${DO_CUDA}" == "true" ]]; then
		setup_nvidia
	fi

	if [[ "${DO_DECK}" == "true" ]]; then
		setup_decklink
	fi

	# Source builds (only build what user selected)
	if [[ "${DO_BUILD_NETWORK_LIBS}" == "true" ]]; then
		build_srt
	fi

	if [[ "${DO_BUILD_VIDEO_LIBS}" == "true" ]]; then
		build_x264
		build_x265
		build_xevd
		build_xeve
	fi

	if [[ "${DO_FFMPEG}" == "true" ]]; then
		fetch_ffmpeg
		cd "$BUILD_DIR/ffmpeg-src"
		if [[ "${DO_DECK}" == "true" && "${DO_PATCH}" == "true" ]]; then
			apply_decklink_patch
		fi
		build_ffmpeg
		verify_install
	else
		yellow "FFmpeg build/install was skipped by user selection."
	fi
}

main "$@"
