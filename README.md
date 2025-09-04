# rocky9-installers

Rocky Linux 9 installer scripts to simplify complex software installations for users.

## Quick Start

```bash
mkdir -p ~/src && cd ~/src
git clone https://github.com/nt74/rocky9-installers.git
cd rocky9-installers
chmod +x install-*
```

Run any installer script:
```bash
./install-<script>.sh
```

## FFmpeg Installer (install-ffmpeg.sh)

Comprehensive FFmpeg installation with professional broadcast and hardware acceleration support.

### System Requirements

- **OS:** Rocky Linux 9.6 or later
- **RAM:** Minimum 8GB (16GB recommended)
- **Storage:** 10GB free disk space
- **Network:** Internet connection required
- **Permissions:** Must run as regular user (NOT root)

### Features

- **FFmpeg 8.0** - Latest stable release
- **DeckLink SDK 15.0** - Blackmagic capture card support with compatibility patches
- **NVIDIA Hardware Acceleration** - NVENC/NVDEC for GPU encoding/decoding
- **Professional Codecs:**
  - x264/x265 (H.264/H.265)
  - libsrt (Secure Reliable Transport)
  - libzvbi (Teletext/VBI)
  - libklvanc (VANC SMPTE2038)
  - OpenH264, OpenJPEG, Opus
- **Hardware Acceleration:** VAAPI, OpenCL, Intel QSV
- **Broadcast Features:** DeckLink I/O, professional color spaces

### DeckLink SDK 15.0 Compatibility

This installer includes a custom patch (`patch/ffmpeg-decklink-sdk15-compat.patch`) that resolves compatibility issues between FFmpeg 8.0 and DeckLink SDK 15.0. The patch addresses API changes in the `IDeckLinkVideoBuffer` interface and memory allocator deprecation.

### Installation Options

```bash
# Interactive installation (recommended)
./install-ffmpeg.sh

# Force reinstall all components
./install-ffmpeg.sh --force
```

### Installation Process

1. **Prerequisites** - Installs development tools and libraries
2. **External Libraries** - Builds codec libraries from source
3. **NVIDIA CUDA** - Installs CUDA toolkit for GPU acceleration
4. **DeckLink SDK** - Installs drivers and headers
5. **FFmpeg Compilation** - Applies patches and compiles FFmpeg
6. **Verification** - Tests installation and DeckLink device detection

**Estimated Time:** 20-60 minutes depending on hardware

### Post-Installation

After successful installation:
- FFmpeg binaries installed to `/usr/bin/`
- Libraries installed to `/usr/lib64/`
- Source files retained in `~/ffmpeg_sources/` (optional cleanup)

Test your installation:
```bash
ffmpeg -version
ffmpeg -f decklink -list_devices 1 -i dummy
```

### Troubleshooting

**Common Issues:**
- **Compilation fails:** Ensure sufficient RAM and disk space
- **Permission errors:** Do not run as root
- **DeckLink not detected:** Check driver installation and hardware connection
- **CUDA errors:** Verify NVIDIA driver compatibility

**Getting Help:**
Check the installation logs in your terminal output for specific error messages.

## File Structure

```
rocky9-installers/
├── README.md
├── install-ffmpeg.sh
├── patch/
│   └── ffmpeg-decklink-sdk15-compat.patch
└── [additional installers]
```

## Contributing

Pull requests welcome for additional Rocky Linux 9 installers or improvements to existing scripts.

## License

Scripts provided as-is for Rocky Linux 9 systems. See individual software licenses for installed components.
