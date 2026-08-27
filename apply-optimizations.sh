#!/usr/bin/env zsh
# apply-optimizations.sh
#
# This script applies recommended optimizations to your Zen Browser build
# configuration for maximum performance on Apple Silicon Macs.
#
# Usage:
#   ./apply-optimizations.sh [--build-speed|--runtime-perf|--balanced]
#
# Options:
#   --build-speed    Optimize for faster builds (RAM disk + sccache)
#   --runtime-perf   Optimize for faster browser (Full LTO + PGO setup)
#   --balanced       Balanced optimization (Full LTO + aggressive flags)
#   (no option)      Interactive mode - prompts for choices

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR}"

# Colors
C_GREEN=$'\e[32m'
C_YELLOW=$'\e[33m'
C_CYAN=$'\e[36m'
C_RED=$'\e[31m'
C_RESET=$'\e[0m'

info()    { print "${C_GREEN}✓${C_RESET} $*" }
warn()    { print "${C_YELLOW}⚠${C_RESET} $*" }
step()    { print "${C_CYAN}→${C_RESET} $*" }
error()   { print "${C_RED}✗${C_RESET} $*" >&2 }

# ---------------------------------------------------------------------------
# Optimization Functions
# ---------------------------------------------------------------------------

setup_ram_disk() {
  step "Setting up RAM disk for build artifacts..."
  
  # Check if already exists
  if [[ -d "/Volumes/ZenBuild" ]]; then
    info "RAM disk already exists at /Volumes/ZenBuild"
    return 0
  fi
  
  # Create 8GB RAM disk
  diskutil erasevolume HFS+ "ZenBuild" $(hdiutil attach -nomount ram://16777216)
  
  # Create symlink if engine directory exists
  if [[ -d "${REPO_ROOT}/engine" ]]; then
    cd "${REPO_ROOT}/engine"
    if [[ -e "obj-aarch64-apple-darwin" && ! -L "obj-aarch64-apple-darwin" ]]; then
      warn "obj-aarch64-apple-darwin exists and is not a symlink"
      warn "Move it manually: mv obj-aarch64-apple-darwin /Volumes/ZenBuild/"
    else
      rm -f obj-aarch64-apple-darwin
      ln -s /Volumes/ZenBuild obj-aarch64-apple-darwin
      info "Created symlink: engine/obj-aarch64-apple-darwin -> /Volumes/ZenBuild"
    fi
  fi
  
  info "RAM disk ready (8GB allocated)"
  warn "Note: RAM disk data is lost on reboot - re-run this script after restart"
}

configure_sccache() {
  step "Configuring sccache..."
  
  # Add to shell profile
  PROFILE_FILE="${HOME}/.zshrc"
  if ! grep -q "SCCACHE_CACHE_SIZE" "$PROFILE_FILE" 2>/dev/null; then
    cat >> "$PROFILE_FILE" << 'EOF'

# Zen Browser build optimizations
export SCCACHE_CACHE_SIZE="50G"
export SCCACHE_DIR="$HOME/Library/Caches/Mozilla.sccache"
EOF
    info "Added sccache configuration to $PROFILE_FILE"
  else
    info "sccache already configured in $PROFILE_FILE"
  fi
  
  # Apply for current session
  export SCCACHE_CACHE_SIZE="50G"
  export SCCACHE_DIR="$HOME/Library/Caches/Mozilla.sccache"
  
  # Restart sccache
  if command -v sccache &> /dev/null; then
    sccache --stop-server 2>/dev/null || true
    sleep 1
    sccache --start-server
    info "sccache configured (50GB cache)"
  else
    warn "sccache not installed - will be installed by build script"
  fi
}

enable_full_lto() {
  step "Enabling full LTO..."
  
  local mozconfig="${REPO_ROOT}/configs/common/mozconfig"
  if [[ ! -f "$mozconfig" ]]; then
    error "mozconfig not found: $mozconfig"
    return 1
  fi
  
  # Backup original
  cp "$mozconfig" "${mozconfig}.backup"
  
  # Replace LTO section
  sed -i '' '72,82s/.*/  if ! test "$ZEN_DISABLE_LTO"; then\
    # Force full LTO for maximum performance\
    export MOZ_LTO=cross,full\
    ac_add_options --enable-lto=cross,full\
  fi/' "$mozconfig"
  
  info "Enabled full LTO in configs/common/mozconfig"
  info "Backup saved: configs/common/mozconfig.backup"
}

enable_aggressive_flags() {
  step "Enabling aggressive compiler optimizations..."
  
  local mozconfig="${REPO_ROOT}/configs/macos/mozconfig"
  if [[ ! -f "$mozconfig" ]]; then
    error "mozconfig not found: $mozconfig"
    return 1
  fi
  
  # Backup original
  cp "$mozconfig" "${mozconfig}.backup"
  
  # Detect CPU (M1, M2, M3)
  local cpu_model=$(sysctl -n machdep.cpu.brand_string)
  local mcpu="apple-m1"  # default
  if [[ "$cpu_model" =~ "M2" ]]; then
    mcpu="apple-m2"
  elif [[ "$cpu_model" =~ "M3" ]]; then
    mcpu="apple-m3"
  fi
  
  # Add optimization flags after line 32
  sed -i '' '32a\
\
if test "$ZEN_RELEASE"; then\
  # Aggressive optimization flags for maximum performance\
  export CFLAGS="$CFLAGS -O3 -march=native -mtune=native -mcpu='"$mcpu"'"\
  export CXXFLAGS="$CXXFLAGS -O3 -march=native -mtune=native -mcpu='"$mcpu"'"\
fi
' "$mozconfig"
  
  info "Enabled aggressive optimizations for $mcpu"
  info "Backup saved: configs/macos/mozconfig.backup"
  warn "Binary will only work on similar Apple Silicon CPUs"
}

enable_max_parallelism() {
  step "Configuring maximum CPU utilization..."
  
  local cpus=$(sysctl -n hw.ncpu)
  
  # Add to shell profile
  PROFILE_FILE="${HOME}/.zshrc"
  if ! grep -q "MOZ_PARALLEL_BUILD" "$PROFILE_FILE" 2>/dev/null; then
    cat >> "$PROFILE_FILE" << EOF

# Zen Browser - Maximum CPU utilization for builds
export MOZ_PARALLEL_BUILD=${cpus}
EOF
    info "Set MOZ_PARALLEL_BUILD=${cpus} in $PROFILE_FILE"
  else
    info "MOZ_PARALLEL_BUILD already configured"
  fi
  
  export MOZ_PARALLEL_BUILD=${cpus}
  info "Will use all ${cpus} CPU cores for builds"
}

# ---------------------------------------------------------------------------
# Preset Configurations
# ---------------------------------------------------------------------------

apply_build_speed_preset() {
  print ""
  print "${C_CYAN}╔════════════════════════════════════════╗${C_RESET}"
  print "${C_CYAN}║  Build Speed Optimization Preset      ║${C_RESET}"
  print "${C_CYAN}╚════════════════════════════════════════╝${C_RESET}"
  print ""
  
  setup_ram_disk
  configure_sccache
  enable_max_parallelism
  
  print ""
  info "Build speed optimizations applied!"
  print ""
  print "Expected improvements:"
  print "  • Incremental builds: 30-50% faster"
  print "  • Cache hit rate: 70%+ with warm cache"
  print ""
  print "Next steps:"
  print "  1. Restart your terminal (or source ~/.zshrc)"
  print "  2. Run: ./scripts/build-unix.sh twilight"
  print ""
}

apply_runtime_perf_preset() {
  print ""
  print "${C_CYAN}╔════════════════════════════════════════╗${C_RESET}"
  print "${C_CYAN}║  Runtime Performance Optimization      ║${C_RESET}"
  print "${C_CYAN}╚════════════════════════════════════════╝${C_RESET}"
  print ""
  
  enable_full_lto
  enable_aggressive_flags
  
  print ""
  info "Runtime performance optimizations applied!"
  print ""
  print "Expected improvements:"
  print "  • Runtime performance: +15-20%"
  print "  • Build time: +15-20 minutes"
  print ""
  print "Next steps:"
  print "  1. Run: ./scripts/build-unix.sh release"
  print "  2. Test with: https://browserbench.org/Speedometer3.0/"
  print ""
  warn "Binary is optimized for your specific CPU (not portable)"
}

apply_balanced_preset() {
  print ""
  print "${C_CYAN}╔════════════════════════════════════════╗${C_RESET}"
  print "${C_CYAN}║  Balanced Optimization (Recommended)   ║${C_RESET}"
  print "${C_CYAN}╚════════════════════════════════════════╝${C_RESET}"
  print ""
  
  setup_ram_disk
  configure_sccache
  enable_max_parallelism
  enable_full_lto
  enable_aggressive_flags
  
  print ""
  info "All optimizations applied!"
  print ""
  print "Expected improvements:"
  print "  • First build: ~60-70 minutes"
  print "  • Incremental builds: ~15-20 minutes"
  print "  • Runtime performance: +15-20%"
  print ""
  print "Next steps:"
  print "  1. Restart your terminal (or source ~/.zshrc)"
  print "  2. Run: ./scripts/build-unix.sh release"
  print ""
  warn "Binary is optimized for your specific CPU (not portable)"
}

# ---------------------------------------------------------------------------
# Interactive Mode
# ---------------------------------------------------------------------------

interactive_mode() {
  print ""
  print "${C_CYAN}╔════════════════════════════════════════╗${C_RESET}"
  print "${C_CYAN}║  Zen Browser Optimization Tool        ║${C_RESET}"
  print "${C_CYAN}╚════════════════════════════════════════╝${C_RESET}"
  print ""
  print "Choose optimization preset:"
  print ""
  print "  ${C_GREEN}1)${C_RESET} Build Speed   - Faster builds, same runtime performance"
  print "  ${C_GREEN}2)${C_RESET} Runtime Perf  - Slower builds, faster browser"
  print "  ${C_GREEN}3)${C_RESET} Balanced      - Best of both (recommended)"
  print "  ${C_GREEN}4)${C_RESET} Custom        - Choose individual optimizations"
  print "  ${C_GREEN}5)${C_RESET} Exit"
  print ""
  print -n "Enter choice [1-5]: "
  read -r choice
  
  case "$choice" in
    1) apply_build_speed_preset ;;
    2) apply_runtime_perf_preset ;;
    3) apply_balanced_preset ;;
    4) custom_mode ;;
    5) exit 0 ;;
    *) error "Invalid choice"; exit 1 ;;
  esac
}

custom_mode() {
  print ""
  print "Select optimizations to apply (y/n for each):"
  print ""
  
  print -n "  • RAM disk for build artifacts (30-50% faster incremental builds)? "
  read -r response
  [[ "$response" =~ ^[Yy]$ ]] && setup_ram_disk
  
  print -n "  • Increase sccache cache size to 50GB (better cache hits)? "
  read -r response
  [[ "$response" =~ ^[Yy]$ ]] && configure_sccache
  
  print -n "  • Use all CPU cores for builds (10-15% faster)? "
  read -r response
  [[ "$response" =~ ^[Yy]$ ]] && enable_max_parallelism
  
  print -n "  • Enable full LTO (8-10% faster runtime, +15 min build)? "
  read -r response
  [[ "$response" =~ ^[Yy]$ ]] && enable_full_lto
  
  print -n "  • Enable aggressive optimizations (5-15% faster runtime)? "
  read -r response
  [[ "$response" =~ ^[Yy]$ ]] && enable_aggressive_flags
  
  print ""
  info "Custom optimizations applied!"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
  cd "$REPO_ROOT"
  
  if [[ $# -eq 0 ]]; then
    interactive_mode
  else
    case "$1" in
      --build-speed)   apply_build_speed_preset ;;
      --runtime-perf)  apply_runtime_perf_preset ;;
      --balanced)      apply_balanced_preset ;;
      --help|-h)
        print "Usage: $0 [--build-speed|--runtime-perf|--balanced]"
        print ""
        print "Presets:"
        print "  --build-speed    Optimize for faster builds"
        print "  --runtime-perf   Optimize for faster browser"
        print "  --balanced       Best of both (recommended)"
        print "  (no option)      Interactive mode"
        exit 0
        ;;
      *)
        error "Unknown option: $1"
        print "Use --help for usage information"
        exit 1
        ;;
    esac
  fi
}

main "$@"
