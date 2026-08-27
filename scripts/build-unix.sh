#!/usr/bin/env zsh

# This script creates a macOS DMG file locally using the steps defined in
# macos-release-build.yml. Targets aarch64 (Apple Silicon) and produces an
# unsigned, unnotarized DMG for the English (en-US) language only.
# PGO is skipped for faster local iteration.
#
# Prerequisites (installed by this script via brew/pip/rustup if missing):
#   brew, node (version matching .nvmrc), python3, cargo/rustup
#
# Usage:
#   ./scripts/build-unix.sh [BRANCH] [--clean]
#
# Arguments:
#   BRANCH    'twilight' or 'release' (default: twilight)
#             - 'twilight': Development branch with latest features (recommended for local testing)
#             - 'release': Stable release branch (use for production builds)
#   --clean   Remove engine/ directory before building (forces fresh download)
#
# Examples:
#   ./scripts/build-unix.sh                   # builds twilight branch (default)
#   ./scripts/build-unix.sh twilight          # explicitly build twilight
#   ./scripts/build-unix.sh release           # build stable release branch
#   ./scripts/build-unix.sh twilight --clean  # clean build of twilight
#
# Important Notes:
# - The script includes optimizations to skip steps if already completed:
#   * Firefox source download (if correct version exists)
#   * Surfer installation (if already installed)
#   * mach bootstrap (if mozbuild tools exist)
#   * Language pack setup (if already configured)
# - Use --clean to force all steps to run from scratch
# - If the import step fails with "patch does not apply" errors, the engine/
#   directory has stale patches. Run with --clean or manually remove engine/

# Zsh strict mode: exit on error, treat unset variables as errors.
setopt errexit nounset pipefail

# Trap errors and provide helpful context
trap 'log_error "Build failed at line $LINENO. Check the output above for details."' ERR

# ---------------------------------------------------------------------------
# Color helpers
# Only emit ANSI codes when stdout is a terminal; fall back to plain text
# when piped or redirected.
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
  C_RESET=$'\e[0m'
  C_BOLD=$'\e[1m'
  C_DIM=$'\e[2m'
  C_CYAN=$'\e[36m'
  C_BLUE=$'\e[34m'
  C_GREEN=$'\e[32m'
  C_YELLOW=$'\e[33m'
  C_RED=$'\e[31m'
  C_MAGENTA=$'\e[35m'
else
  C_RESET='' C_BOLD='' C_DIM='' C_CYAN='' C_BLUE=''
  C_GREEN='' C_YELLOW='' C_RED='' C_MAGENTA=''
fi

# log_header  <text>  — bold cyan banner line
log_header()  { print "${C_BOLD}${C_CYAN}$*${C_RESET}" }
# log_step    <text>  — bold blue step label  e.g. "[1/8] Installing..."
log_step()    { print "${C_BOLD}${C_BLUE}$*${C_RESET}" }
# log_info    <text>  — plain green informational note
log_info()    { print "${C_GREEN}  $*${C_RESET}" }
# log_timing  <text>  — dim text for timing lines
log_timing()  { print "${C_DIM}$*${C_RESET}" }
# log_warn    <text>  — yellow warning
log_warn()    { print "${C_YELLOW}  WARNING: $*${C_RESET}" }
# log_note    <text>  — yellow note (softer than warn)
log_note()    { print "${C_YELLOW}  NOTE: $*${C_RESET}" }
# log_success <text>  — bold green success banner
log_success() { print "${C_BOLD}${C_GREEN}$*${C_RESET}" }
# log_error   <text>  — bold red error (does not exit by itself)
log_error()   { print "${C_BOLD}${C_RED}  ERROR: $*${C_RESET}" >&2 }

# ---------------------------------------------------------------------------
# Timing helpers
# ---------------------------------------------------------------------------
BUILD_START=$(date +%s)

# Print elapsed time since BUILD_START in H:MM:SS format.
elapsed() {
  local now delta h m s
  now=$(date +%s)
  delta=$(( now - BUILD_START ))
  h=$(( delta / 3600 ))
  m=$(( (delta % 3600) / 60 ))
  s=$(( delta % 60 ))
  printf "%d:%02d:%02d" "$h" "$m" "$s"
}

# Record the start time of the current step; call step_end to print duration.
STEP_START=0
step_start() {
  STEP_START=$(date +%s)
}

# Print how long the most recent step took.
step_end() {
  local now delta h m s
  now=$(date +%s)
  delta=$(( now - STEP_START ))
  h=$(( delta / 3600 ))
  m=$(( (delta % 3600) / 60 ))
  s=$(( delta % 60 ))
  log_timing "    (step took ${h}:$(printf '%02d' $m):$(printf '%02d' $s) | total elapsed $(elapsed))"
}

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
UPDATE_BRANCH="${1:-twilight}"   # 'release' or 'twilight'
CLEAN_BUILD=false

# Parse arguments
for arg in "$@"; do
  case "$arg" in
    --clean)
      CLEAN_BUILD=true
      shift
      ;;
    release|twilight)
      UPDATE_BRANCH="$arg"
      shift
      ;;
  esac
done

# Validate branch argument
if [[ "$UPDATE_BRANCH" != "release" && "$UPDATE_BRANCH" != "twilight" ]]; then
  log_error "Invalid branch: '$UPDATE_BRANCH'"
  log_error "Valid options: 'release' or 'twilight'"
  log_error ""
  log_error "Usage: $0 [BRANCH]"
  log_error "  BRANCH: 'twilight' (default, recommended for local builds) or 'release'"
  log_error ""
  log_error "Examples:"
  log_error "  $0              # builds twilight branch"
  log_error "  $0 twilight     # builds twilight branch"
  log_error "  $0 release      # builds release branch"
  exit 1
fi

ARCH="aarch64"                   # aarch64 (Apple Silicon) only
RUST_TARGET="${ARCH}-apple-darwin"
# ${0:A} resolves the script path to an absolute path (zsh parameter expansion).
# :h gives the directory (equivalent to dirname).
SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR}/.."

log_header "=========================================="
log_header "Zen Browser Local Build (macOS, unsigned)"
log_header "Branch  : $UPDATE_BRANCH"
log_header "Arch    : $ARCH"
log_header "Language: en-US only"
if [[ "$CLEAN_BUILD" == true ]]; then
  log_header "Mode    : Clean build (engine/ will be removed)"
fi
log_header "Started : $(date '+%Y-%m-%d %H:%M:%S')"
log_header "=========================================="

# Check available disk space (need ~20GB for build)
AVAILABLE_GB=$(df -g . | awk 'NR==2 {print $4}')
if (( AVAILABLE_GB < 20 )); then
  log_warn "Low disk space: ${AVAILABLE_GB}GB available (recommend 20GB+)"
  log_warn "Build may fail if space runs out. Free up space and try again."
  print "Continue anyway? (y/N): "
  read -r response
  if [[ ! "$response" =~ ^[Yy]$ ]]; then
    log_info "Build cancelled by user."
    exit 0
  fi
fi

cd "$REPO_ROOT"

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
print ""
log_info "Running pre-flight checks..."

# Check for required files
REQUIRED_FILES=(".nvmrc" ".python-version" ".rust-toolchain" "surfer.json" "package.json")
for file in "${REQUIRED_FILES[@]}"; do
  if [[ ! -f "$file" ]]; then
    log_error "Required file missing: $file"
    log_error "Are you in the zen-browser-desktop repository root?"
    exit 1
  fi
done

log_info "✓ All required files present"

# ---------------------------------------------------------------------------
# 1. System dependencies
# Mirrors 'Install system dependencies' in macos-release-build.yml
# Note: CI now cross-compiles from Linux (commit 13edb480), but for local
# macOS builds, native compilation is faster and simpler.
# ---------------------------------------------------------------------------
print ""
log_step "[1/8] Installing system dependencies..."
step_start

# Check if brew is available
if ! command -v brew &> /dev/null; then
  log_error "Homebrew not found. Please install it first:"
  log_error "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
  exit 1
fi

brew update
brew install cairo gnu-tar mercurial sccache terminal-notifier watchman

# Setup git config for local builds (mirrors 'Setup Git' step in workflow)
# git config --global user.name "${USER:-local-user}"
# git config --global user.email "${USER:-local-user}@local"

# gnu-tar must precede BSD tar on PATH (mirrors 'Force usage of gnu-tar' step)
GNU_TAR_PATH="$(brew --prefix gnu-tar)/libexec/gnubin"
if [[ -d "$GNU_TAR_PATH" && ":$PATH:" != *":$GNU_TAR_PATH:"* ]]; then
  export PATH="$GNU_TAR_PATH:$PATH"
fi

mise install # will install languages (node, python & rust) if missing, but won't downgrade if already present

# Verify required versions are available
log_info "Verifying language versions..."
if command -v node &> /dev/null; then
  NODE_VERSION=$(node --version | tr -d 'v')
  log_info "Node.js: v${NODE_VERSION} (required: $(cat .nvmrc))"
fi
if command -v python3 &> /dev/null; then
  PYTHON_VERSION=$(python3 --version | awk '{print $2}')
  log_info "Python: ${PYTHON_VERSION} (required: $(cat .python-version))"
fi
if command -v rustc &> /dev/null; then
  RUST_VERSION=$(rustc --version | awk '{print $2}')
  log_info "Rust: ${RUST_VERSION} (required: $(cat .rust-toolchain))"
fi

# Python setuptools and mercurial installation
sudo pip install setuptools 2>/dev/null || true
export PATH="$(python3 -m site --user-base)/bin:$PATH"
python3 -m pip install --user mercurial 2>/dev/null || true

# Clean up conflicting Python versions if present (mirrors workflow lines 85-94)
# This prevents Python version conflicts during the Firefox build process.
# Ignore errors if these symlinks don't exist (local env may differ from CI).
# rm -f /usr/local/bin/2to3-3.11 /usr/local/bin/2to3-3.12 /usr/local/bin/2to3 2>/dev/null || true
# rm -f /usr/local/bin/idle3.11 /usr/local/bin/idle3.12 /usr/local/bin/idle3 2>/dev/null || true
# rm -f /usr/local/bin/pydoc3.11 /usr/local/bin/pydoc3.12 /usr/local/bin/pydoc3 2>/dev/null || true
# rm -f /usr/local/bin/python3.11 /usr/local/bin/python3.12 /usr/local/bin/python3 2>/dev/null || true
# rm -f /usr/local/bin/python3.11-config /usr/local/bin/python3.12-config /usr/local/bin/python3-config 2>/dev/null || true

# Uninstall conflicting Python 3.12 brew package if present
# brew uninstall --ignore-dependencies python@3.12 -f 2>/dev/null || true

# Rust toolchain (ensure cargo env is sourced)
source "$HOME/.cargo/env" 2>/dev/null || true
rustup target add "$RUST_TARGET"

export RUSTC_WRAPPER=sccache

# Enable parallel builds (use all cores minus 1 to keep system responsive)
CPUS=$(sysctl -n hw.ncpu)
JOBS=$((CPUS > 1 ? CPUS - 1 : 1))
log_info "Enabling parallel builds with ${JOBS} jobs (${CPUS} CPUs available)"
export MOZ_PARALLEL_BUILD="${JOBS}"

# Show sccache statistics before build
if command -v sccache &> /dev/null; then
  log_info "sccache statistics (before build):"
  sccache --show-stats | head -5 | sed 's/^/    /'
fi

# If RUSTUP_TOOLCHAIN is pinned to a specific version in the shell environment,
# it can override the .rust-toolchain file and cause "Rust too old" errors.
# Unset it so rustup uses the toolchain declared in .rust-toolchain.
if [[ -n "${RUSTUP_TOOLCHAIN:-}" ]]; then
  log_note "Unsetting RUSTUP_TOOLCHAIN=$RUSTUP_TOOLCHAIN to allow .rust-toolchain to take effect."
  unset RUSTUP_TOOLCHAIN
fi

step_end

# ---------------------------------------------------------------------------
# 2. Node.js dependencies
# ---------------------------------------------------------------------------
print ""
log_step "[2/8] Installing Node.js dependencies..."
step_start
npm ci
step_end

# ---------------------------------------------------------------------------
# 3. Setup Surfer (installed globally to match CI)
# ---------------------------------------------------------------------------
print ""
log_step "[3/8] Setting up Surfer..."
step_start

# Check if Surfer is already installed globally
if command -v surfer &> /dev/null; then
  SURFER_VERSION=$(surfer --version 2>/dev/null || echo "unknown")
  log_info "Surfer already installed (version: ${SURFER_VERSION})"
  log_info "Skipping installation (will use existing version)"
else
  log_info "Installing Surfer globally..."
  npm i -g @zen-browser/surfer
fi

step_end

# ---------------------------------------------------------------------------
# 4. Get version and configure Surfer CI mode
# ---------------------------------------------------------------------------
print ""
log_step "[4/8] Configuring Surfer..."
step_start
# Read the displayVersion directly from surfer.json.
# We cannot call 'surfer get version' before 'surfer ci' because surfer
# requires the brand to be set first — reading from JSON avoids the
# chicken-and-egg problem and avoids xargs quote-parsing issues.
VERSION=$(python3 -c "import json; d=json.load(open('surfer.json')); print(d['brands']['${UPDATE_BRANCH}']['release']['displayVersion'])")
log_info "Detected version: $VERSION"
npm run surfer -- ci --brand "$UPDATE_BRANCH" --display-version "$VERSION"
step_end

# ---------------------------------------------------------------------------
# 5. Download Firefox source
# Mirrors 'Download Firefox source' step in macos-release-build.yml
# ---------------------------------------------------------------------------
print ""
log_step "[5/8] Downloading Firefox source..."
step_start

# Clean build: remove engine directory if requested
if [[ "$CLEAN_BUILD" == true ]] && [[ -d "$REPO_ROOT/engine" ]]; then
  log_info "Removing existing engine/ directory for clean build..."
  rm -rf "$REPO_ROOT/engine"
fi

# Check if Firefox source is already downloaded with the correct version
EXPECTED_FF_VERSION=$(python3 -c "import json; d=json.load(open('surfer.json')); print(d['version']['version'])")
SKIP_DOWNLOAD=false

if [[ -f "$REPO_ROOT/engine/browser/config/version.txt" ]]; then
  CURRENT_FF_VERSION=$(cat "$REPO_ROOT/engine/browser/config/version.txt")
  if [[ "$CURRENT_FF_VERSION" == "$EXPECTED_FF_VERSION" ]]; then
    log_info "Firefox source v${CURRENT_FF_VERSION} already present (matches expected v${EXPECTED_FF_VERSION})"
    log_info "Skipping download (use --clean to force re-download)"
    SKIP_DOWNLOAD=true
  else
    log_warn "Firefox version mismatch: current=${CURRENT_FF_VERSION}, expected=${EXPECTED_FF_VERSION}"
    log_info "Re-downloading Firefox source..."
  fi
fi

# Download only if needed
if [[ "$SKIP_DOWNLOAD" == false ]]; then
  # Use --force so that a stale or wrong-version engine/ directory is replaced.
  # The CI always starts from a fresh checkout, so this matches that behaviour.
  surfer download --force
fi
step_end

# ---------------------------------------------------------------------------
# 6. Import Zen Browser modifications
# ---------------------------------------------------------------------------
print ""
log_step "[6/8] Importing Zen Browser modifications..."
step_start

# Check if the engine directory has uncommitted changes (indicating patches were already applied)
# If so, reset it to allow patches to apply cleanly
if [[ -d "$REPO_ROOT/engine/.git" ]]; then
  cd "$REPO_ROOT/engine"
  # Check if there are staged or unstaged changes (patches already applied)
  if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
    log_warn "Engine directory has uncommitted changes (patches already applied)"
    log_info "Resetting engine to clean state for patch application..."
    # Reset all changes - unstage and discard modifications
    git reset --hard HEAD 2>/dev/null || git reset --hard 2>/dev/null || true
    git clean -fd 2>/dev/null || true
    log_info "Engine reset complete"
  else
    log_info "Engine directory is clean"
  fi
  cd "$REPO_ROOT"
fi

SURFER_COMPAT="$ARCH" npm run import
step_end

# ---------------------------------------------------------------------------
# 7. Bootstrap mach
# Mirrors 'Bootstrap' step in macos-release-build.yml
# Note: language packs are downloaded AFTER bootstrap (matches CI order)
# ---------------------------------------------------------------------------
print ""
log_step "[7/8] Running mach bootstrap..."
step_start
export SURFER_PLATFORM="darwin"
git submodule update --init --recursive --remote --rebase --force

# Check if mach bootstrap has already been run
MOZBUILD_DIR="${HOME}/.mozbuild"
MOZBUILD_CLANG_BIN="${MOZBUILD_DIR}/clang/bin"
SKIP_BOOTSTRAP=false

if [[ -d "$MOZBUILD_CLANG_BIN" ]] && [[ -f "${MOZBUILD_CLANG_BIN}/clang" ]]; then
  log_info "mozbuild tools already installed at ${MOZBUILD_DIR}"
  log_info "Skipping mach bootstrap (use --clean and remove ~/.mozbuild to force)"
  SKIP_BOOTSTRAP=true
fi

if [[ "$SKIP_BOOTSTRAP" == false ]]; then
  log_info "Running mach bootstrap..."
  cd "$REPO_ROOT/engine"
  ./mach --no-interactive bootstrap --application-choice browser --exclude macos-sdk || true
  cd "$REPO_ROOT"
fi

# Add mozbuild clang/lld to PATH (Firefox's bundled LLVM toolchain)
# This ensures configure finds lld when using -fuse-ld=lld
if [[ -d "${MOZBUILD_CLANG_BIN}" && ":${PATH}:" != *":${MOZBUILD_CLANG_BIN}:"* ]]; then
  export PATH="${MOZBUILD_CLANG_BIN}:${PATH}"
  log_info "Added mozbuild clang/lld to PATH: ${MOZBUILD_CLANG_BIN}"
fi

# Install cbindgen if not already present (required by Firefox build)
# mach bootstrap should install this, but sometimes it doesn't.
if ! command -v cbindgen &> /dev/null; then
  log_info "Installing cbindgen..."
  cargo install cbindgen
fi

step_end

# ---------------------------------------------------------------------------
# 7b. Build English (en-US) language pack only
# The full download-language-packs.sh clones the entire firefox-l10n repo
# and processes all ~40 languages. For an English-only DMG we only need to
# run copy_language_pack.py for en-US (the en-US locale files are already
# present in ./locales/en-US from the Zen source tree; no network clone is
# needed for this language).
# Mirrors the 'Build language packs' step but restricted to en-US.
# ---------------------------------------------------------------------------
print ""
log_step "[7b/8] Setting up en-US language pack..."
step_start

# Check if language pack is already set up
EN_US_LOCALE_DIR="$REPO_ROOT/engine/browser/locales/en-US"
if [[ -d "$EN_US_LOCALE_DIR" ]] && [[ -n "$(ls -A "$EN_US_LOCALE_DIR" 2>/dev/null)" ]]; then
  log_info "en-US language pack already set up in $EN_US_LOCALE_DIR"
  log_info "Skipping language pack setup (use --clean to force re-setup)"
else
  log_info "Setting up en-US language pack..."
  python3 scripts/copy_language_pack.py en-US
fi

step_end

# ---------------------------------------------------------------------------
# 8. Build and Package
# Mirrors 'Build Zen' and 'Package' steps in macos-release-build.yml.
# PGO is intentionally skipped (local builds only).
#
# release-build.sh (used by CI) also:
#   - creates ~/.zen-keys/ with API key files
#   - calls scripts/mar_sign.sh -i  (imports MAR signing key into NSS db)
#   - sources $HOME/.cargo/env
#   - sets ulimit -n 4096
# We replicate all of those steps here.
# ---------------------------------------------------------------------------
print ""
log_step "[8/8] Building Zen Browser (no PGO)..."
step_start

# The macOS SDK detection is already handled by configs/macos/mozconfig
# (lines 25-31), which checks for allowed SDKs and uses the first available.
# Similarly, WASI sysroot is already configured in mozconfig (line 69).
# No need to modify the file - let the mozconfig handle it.
log_info "macOS SDK and WASI sysroot will be auto-detected by mozconfig"

# Create API key files only when the corresponding env var is non-empty.
# If the env vars are empty (local unsigned build), do NOT create the files —
# configs/common/mozconfig uses 'if test -f ...' guards, so absent files are
# silently skipped. Creating empty files causes mach to error "file is empty".
mkdir -p ~/.zen-keys
[[ -n "${ZEN_SAFEBROWSING_API_KEY:-}" ]]            && print -n "$ZEN_SAFEBROWSING_API_KEY"            > ~/.zen-keys/safebrowsing.dat           || rm -f ~/.zen-keys/safebrowsing.dat
[[ -n "${ZEN_MOZILLA_API_KEY:-}" ]]                 && print -n "$ZEN_MOZILLA_API_KEY"                 > ~/.zen-keys/mozilla.dat                || rm -f ~/.zen-keys/mozilla.dat
[[ -n "${ZEN_GOOGLE_LOCATION_SERVICE_API_KEY:-}" ]] && print -n "$ZEN_GOOGLE_LOCATION_SERVICE_API_KEY" > ~/.zen-keys/google_location_service.dat || rm -f ~/.zen-keys/google_location_service.dat

# Import the MAR signing key into the NSS database (required before build)
zsh ./scripts/mar_sign.sh -i

# Raise open-file-descriptor limit (matches release-build.sh)
ulimit -n 4096

# Ensure Rust/Cargo toolchain is on PATH
source "$HOME/.cargo/env" 2>/dev/null || true

# Ensure RUSTUP_TOOLCHAIN doesn't override the .rust-toolchain file
unset RUSTUP_TOOLCHAIN 2>/dev/null || true

export SURFER_PLATFORM="darwin"
export SURFER_COMPAT="$ARCH"
export ZEN_RELEASE_BRANCH="$UPDATE_BRANCH"
export ZEN_GA_DISABLE_PGO=true
export ZEN_RELEASE=1

npm run build
step_end

# Show sccache statistics after build
if command -v sccache &> /dev/null; then
  print ""
  log_info "sccache statistics (after build):"
  sccache --show-stats | head -10 | sed 's/^/    /'
fi

print ""
log_step "  Packaging (creating DMG)..."
step_start
SURFER_COMPAT="$ARCH" SURFER_PLATFORM="darwin" ZEN_RELEASE=1 ZEN_GA_DISABLE_PGO=true npm run package
step_end

# Clean up API key files
rm -rf ~/.zen-keys

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
TOTAL_END=$(date +%s)
TOTAL_DELTA=$(( TOTAL_END - BUILD_START ))
TOTAL_H=$(( TOTAL_DELTA / 3600 ))
TOTAL_M=$(( (TOTAL_DELTA % 3600) / 60 ))
TOTAL_S=$(( TOTAL_DELTA % 60 ))

# Find the actual DMG file
DMG_FILE=$(find "$REPO_ROOT/dist" -name "*.dmg" -type f 2>/dev/null | head -1)
if [[ -z "$DMG_FILE" ]]; then
  DMG_FILE=$(find "$REPO_ROOT/engine/obj-${ARCH}-apple-darwin/dist" -name "*.dmg" -type f 2>/dev/null | head -1)
fi

print ""
log_success "=========================================="
log_success "Build complete!"
log_success "Finished : $(date '+%Y-%m-%d %H:%M:%S')"
log_success "$(printf 'Total    : %d:%02d:%02d' $TOTAL_H $TOTAL_M $TOTAL_S)"
if [[ -n "$DMG_FILE" ]]; then
  DMG_SIZE=$(du -h "$DMG_FILE" | cut -f1)
  log_success "DMG file : $DMG_FILE"
  log_success "Size     : $DMG_SIZE"
else
  log_warn "DMG file not found in expected locations"
  log_info "Check: $REPO_ROOT/dist/ or engine/obj-${ARCH}-apple-darwin/dist/"
fi
log_success ""
log_success "Note: This DMG is unsigned, unnotarized, and English (en-US) only."
log_success "To install: Open the DMG and drag Zen Browser to Applications."
log_success "=========================================="
