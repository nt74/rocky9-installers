# Rocky 9 Installers — Universal FFmpeg Installer

This repository provides a **universal, interactive FFmpeg installer** for **Rocky Linux 9 / RHEL 9** focused on broadcast / production deployments.

It consolidates all prior FFmpeg installer variants into **one standardized script** that supports:
- Logical library grouping (video / audio / network / broadcast I/O)
- Hardware acceleration options (NVIDIA NVENC, Intel QSV/VAAPI, AMD AMF)
- Optional DeckLink SDK installation
- Optional FFmpeg patching (using repository `patch/` files)
- Reproducible builds and clean configuration defaults

---

## Supported OS

- Rocky Linux 9.x
- RHEL 9.x compatible distributions

---

## What This Installer Builds / Enables

Depending on your selections, the installer can build and enable:

### Video codec libraries
- x264 (H.264)
- x265 (H.265 / HEVC)
- MPEG-5 EVC decoder/encoder (xevd / xeve)
- dav1d (AV1 decoder)
- SVT-AV1 (AV1 encoder)
- libvpx (VP8/VP9)

### Audio codec libraries
- fdk-aac
- libmp3lame
- opus
- vorbis

### Audio I/O
- ALSA
- PulseAudio

### Network / transport
- SRT (libsrt)
- RIST (librist) (installed via system packages when available)

### Broadcast / professional features
- DeckLink SDK support (`--enable-decklink`)
- KLVAnc support (if installed via system packages)

### Hardware acceleration
- NVIDIA CUDA / NVENC (via CUDA repo + nv-codec-headers)
- Intel QuickSync (QSV) + VAAPI
- AMD AMF

---

## Repository Structure

- `install-ffmpeg.sh`
  The **only** FFmpeg installer users should run.

- `patch/`
  Patch files used to modify FFmpeg sources (e.g. DeckLink compatibility patches).
  These are applied **only if the user opts in**.

---

## Requirements

### Important: Root is required

This installer performs:
- `dnf` installs
- system repository configuration
- writes into `/usr/local` (default)
- updates `ldconfig`

Run it as root:

```bash
sudo -i
./install-ffmpeg.sh
```

Or:

```bash
sudo ./install-ffmpeg.sh
```

---

## Quick Start

```bash
git clone https://github.com/nt74/rocky9-installers.git
cd rocky9-installers
chmod +x install-ffmpeg.sh
sudo ./install-ffmpeg.sh
```

The installer will guide you through:

* repo setup (EPEL, CRB, RPMFusion)
* selecting feature groups (video/audio/network/broadcast)
* selecting GPU acceleration options
* optional DeckLink SDK setup
* optional FFmpeg patching
* building and installing FFmpeg

---

## Build Directory (Important)

By default, the installer builds in:

* **`/var/tmp/ffmpeg_build`**

This is intentional:

* avoids clutter in the repo directory
* keeps build artifacts available for troubleshooting
* persists across reboot (unlike `/tmp`)

You can override this by setting `BUILD_DIR` or `BUILD_ROOT`.

### Examples

Use a custom build directory:

```bash
sudo BUILD_DIR=/opt/build/ffmpeg_build ./install-ffmpeg.sh
```

Use a different build root:

```bash
sudo BUILD_ROOT=/opt/build ./install-ffmpeg.sh
```

---

## Installation Prefix

By default, FFmpeg and custom-built libraries are installed into:

* **`/usr/local`**

You can override this with `PREFIX`:

```bash
sudo PREFIX=/opt/ffmpeg ./install-ffmpeg.sh
```

If you change `PREFIX`, ensure your runtime environment and `ldconfig` paths match.
When verifying, use `${PREFIX}/bin/ffmpeg` instead of `/usr/local/bin/ffmpeg`.

---

## DeckLink SDK + Patching

If enabled, the installer will:

1. Download and extract the DeckLink SDK
2. Copy the headers into `${PREFIX}/include` (defaults to `/usr/local/include`)
3. Optionally apply a patch from:

* `patch/ffmpeg-decklink-sdk15-compat.patch`

Patch application is always **opt-in**. The installer will confirm before applying.

---

## Verification

After installation, validate FFmpeg:

```bash
/usr/local/bin/ffmpeg -hide_banner -version
```

Check codec support:

```bash
/usr/local/bin/ffmpeg -hide_banner -codecs | grep -E 'x264|x265|evc|svt|dav1d'
```

If DeckLink was enabled:

```bash
/usr/local/bin/ffmpeg -hide_banner -sources decklink
/usr/local/bin/ffmpeg -hide_banner -sinks decklink
```

If you changed `PREFIX`, run the same commands using `${PREFIX}/bin/ffmpeg`.

---

## Non-Interactive / Automation

This installer is designed to be interactive by default.

For automation use-cases, you can control behavior via environment variables:

* `PREFIX`
* `BUILD_ROOT`
* `BUILD_DIR`
* version variables (e.g. `FFMPEG_VERSION`, `X265_VERSION`, `LIBSRT_VERSION`)

If you want full non-interactive support (`--profile full`, `--defaults`, `--non-interactive`), that can be added cleanly as a next step.

---

## Notes and Caveats

* Using `--enable-nonfree` enables features that may have licensing restrictions.
  You are responsible for compliance and redistribution rights.

* NVIDIA support requires compatible GPU hardware and driver stack.
  The installer can install CUDA tooling but does not manage your full driver lifecycle.

* Intel QSV support depends on the installed Intel media drivers and available iGPU.

* AMD AMF depends on system availability of AMF headers and compatible drivers.

---

## License

This repository contains installer scripts and patches.
Individual third-party components built by the installer (FFmpeg, codecs, SDKs) are governed by their respective licenses.

---

## Support / Contributions

If you encounter issues:

* capture the installer output (or share your build log)
* include: OS version, kernel version, and selected installer options

Pull requests to improve the universal installer structure, codec grouping, or patch handling are welcome.
