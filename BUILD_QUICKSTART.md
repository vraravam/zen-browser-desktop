# Zen Browser - Local macOS Build Quick Start

**Goal**: Create a `.dmg` installer for local testing on Apple Silicon Macs.

## Prerequisites

- macOS 13.0 or later (Apple Silicon recommended)
- ~20GB free disk space
- Xcode Command Line Tools (`xcode-select --install`)
- [Homebrew](https://brew.sh)
- [mise](https://mise.jdx.dev) (installed automatically by script)

## Quick Build

```bash
cd ~/dev/oss/zen-browser-desktop
./scripts/build-unix.sh twilight
```

**Build time**: 45-60 minutes (first build), 15-25 minutes (incremental)

## Build Output

```
dist/zen-macos-aarch64-<version>.dmg
```

To install:
1. Open the DMG file
2. Drag Zen Browser to Applications
3. Right-click Zen Browser in Applications → Open (bypass Gatekeeper)

## Options

### Build Release Branch
```bash
./scripts/build-unix.sh release
```

### Clean Build (Force Fresh Download)
```bash
./scripts/build-unix.sh twilight --clean
```

## What Gets Built

- **Architecture**: aarch64 (Apple Silicon) only
- **Language**: English (en-US) only
- **Optimization**: Release mode, no PGO
- **Signing**: Unsigned/unnotarized (local testing only)

## Troubleshooting

### Build Fails with "Rust too old"
```bash
# Update Rust to version in .rust-toolchain
mise install rust
```

### Build Fails with "Permission Denied"
```bash
# Fix executable permissions
chmod +x scripts/build-unix.sh
chmod +x scripts/mar_sign.sh
chmod +x scripts/copy_language_pack.py
```

### Build Fails with "No space left on device"
```bash
# Check available space (need 20GB+)
df -h .

# Clean previous builds
rm -rf engine/obj-*
rm -rf dist/*.dmg
```

### Build Fails with "sccache error"
```bash
# Clear sccache cache
sccache --stop-server
rm -rf ~/Library/Caches/Mozilla.sccache
sccache --start-server
```

### DMG Won't Open (Gatekeeper)
```bash
# Remove quarantine attribute
xattr -d com.apple.quarantine dist/*.dmg

# Or use right-click → Open in Finder
```

## Performance Tips

1. **First build is slow** (45-60 min) - subsequent builds are much faster
2. **sccache cache** is stored in `~/Library/Caches/Mozilla.sccache`
3. **Incremental builds** reuse compiled objects (15-25 min)
4. **Clean build** (`--clean`) takes same time as first build

## Build Artifacts

```
dist/
├── zen-macos-aarch64-<version>.dmg   # Main installer
└── zen-macos-aarch64-<version>.app/  # Application bundle

engine/
└── obj-aarch64-apple-darwin/
    └── dist/
        ├── bin/                       # Compiled binaries
        └── Zen Browser.app/          # Unsigned app bundle
```

## Advanced Usage

### Custom API Keys (Optional)
```bash
export ZEN_SAFEBROWSING_API_KEY="your-key"
export ZEN_MOZILLA_API_KEY="your-key"
export ZEN_GOOGLE_LOCATION_SERVICE_API_KEY="your-key"

./scripts/build-unix.sh twilight
```

### Parallel Build Jobs
```bash
# Script auto-detects CPUs and uses (CPUs - 1)
# To override:
export MOZ_PARALLEL_BUILD=8
./scripts/build-unix.sh twilight
```

### Debug Build
```bash
# Edit configs/macos/mozconfig
# Change: ac_add_options --enable-optimize
# To:     ac_add_options --enable-debug
#         ac_add_options --disable-optimize

./scripts/build-unix.sh twilight
```

## Comparison: Local vs CI Builds

| Feature | Local Build | CI Build |
|---------|-------------|----------|
| Platform | macOS (native) | Linux (cross-compile) |
| Architectures | aarch64 only | x86_64 + aarch64 |
| PGO | Disabled | Enabled (2-stage) |
| Signing | Unsigned | Signed + Notarized |
| Language Packs | en-US only | All ~40 languages |
| Build Time | 45-60 min | 90-120 min |
| Use Case | Testing | Production |

## Need Help?

- **Build script issues**: Check `BUILD_REVIEW.md` for detailed analysis
- **CI workflow changes**: Check `.github/workflows/macos-release-build.yml`
- **Zen Browser docs**: https://docs.zen-browser.app
- **Upstream Firefox**: https://firefox-source-docs.mozilla.org/

---

**Last Updated**: August 23, 2026  
**Script Version**: build-unix.sh (reviewed 2026-08-23)  
**CI Workflow**: macos-release-build.yml (commit 13edb480)
