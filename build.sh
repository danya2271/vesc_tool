#!/usr/bin/env bash
#
# VESC Tool Build Script
# Supports Linux desktop & mobile builds with automatic compiler & Qt detection.
#

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Color helpers
BOLD='\033[1m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

# Defaults
TARGET_MODE="desktop"
CLEAN_BUILD=false
CLEAN_ONLY=false
EXCLUDE_FW=true
RUN_AFTER=false
JOBS=""

# Determine default jobs (cap at 8 to prevent memory exhaustion & compiler issues)
CPU_COUNT=$(nproc 2>/dev/null || echo 4)
if [ "$CPU_COUNT" -gt 8 ]; then
    DEFAULT_JOBS=8
else
    DEFAULT_JOBS="$CPU_COUNT"
fi
JOBS="$DEFAULT_JOBS"

show_help() {
    echo -e "${BOLD}VESC Tool Build Script${NC}

${BOLD}USAGE:${NC}
  ./build.sh [OPTIONS]

${BOLD}OPTIONS:${NC}
  -d, --desktop         Build desktop GUI version (default)
  -m, --mobile          Build mobile GUI version (standalone)
  -a, --apk, --android  Build Android APK (delegates to ./build_android.sh)
  -c, --clean           Perform a clean before building
      --clean-only      Clean build artifacts and exit
  -j, --jobs <N>        Number of parallel make jobs (default: ${DEFAULT_JOBS})
      --with-fw         Download and bundle full firmware archives (slower)
      --without-fw      Skip downloading firmware archives (default, fast)
  -r, --run             Execute the binary after a successful build
  -h, --help            Show this help message

${BOLD}EXAMPLES:${NC}
  ./build.sh                     # Quick build desktop version
  ./build.sh --mobile            # Build standalone mobile version
  ./build.sh --apk               # Build Android APK (mobile)
  ./build.sh --clean --run       # Clean build desktop and launch
  ./build.sh --mobile --run      # Build and launch mobile UI"
}

# Parse command line options
while [[ $# -gt 0 ]]; do
    case "$1" in
        --apk|--android|apk|android)
            shift
            exec "$SCRIPT_DIR/build_android.sh" "$@"
            ;;
        -d|--desktop|desktop)
            TARGET_MODE="desktop"
            shift
            ;;
        -m|--mobile|mobile)
            TARGET_MODE="mobile"
            shift
            ;;
        -c|--clean)
            CLEAN_BUILD=true
            shift
            ;;
        --clean-only|clean)
            CLEAN_ONLY=true
            shift
            ;;
        -j|--jobs)
            if [[ -n "$2" && "$2" =~ ^[0-9]+$ ]]; then
                JOBS="$2"
                shift 2
            else
                log_error "Option $1 requires a positive integer argument."
                exit 1
            fi
            ;;
        --with-fw)
            EXCLUDE_FW=false
            shift
            ;;
        --without-fw)
            EXCLUDE_FW=true
            shift
            ;;
        -r|--run)
            RUN_AFTER=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Perform clean-only if requested
if [ "$CLEAN_ONLY" = true ]; then
    log_info "Cleaning build artifacts..."
    if [ -f Makefile ]; then
        make clean 2>/dev/null || true
        rm -f Makefile
    fi
    rm -rf build/lin/*
    log_success "Clean completed."
    exit 0
fi

# Detect qmake
QMAKE_BIN=""
for candidate in qmake-qt5 qmake /usr/lib/qt5/bin/qmake /opt/Qt/5.15-static/bin/qmake; do
    if command -v "$candidate" >/dev/null 2>&1; then
        # Check Qt version from candidate
        QT_VER=$("$candidate" -query QT_VERSION 2>/dev/null || true)
        if [[ "$QT_VER" =~ ^5\. ]]; then
            QMAKE_BIN="$candidate"
            break
        elif [ -z "$QMAKE_BIN" ]; then
            QMAKE_BIN="$candidate"
        fi
    fi
done

if [ -z "$QMAKE_BIN" ]; then
    log_error "qmake not found! Please install Qt 5 development tools (e.g. qt5-base, qt5-declarative)."
    exit 1
fi

QT_VERSION_FOUND=$("$QMAKE_BIN" -query QT_VERSION 2>/dev/null || echo "unknown")
log_info "Using qmake: $QMAKE_BIN (Qt $QT_VERSION_FOUND)"

# Detect stable C++ compiler (prefer gcc-14 / g++-14 if available, otherwise default g++)
CXX_BIN="g++"
CC_BIN="gcc"
if command -v g++-14 >/dev/null 2>&1 && command -v gcc-14 >/dev/null 2>&1; then
    CXX_BIN="g++-14"
    CC_BIN="gcc-14"
elif command -v g++ >/dev/null 2>&1; then
    CXX_BIN="g++"
    CC_BIN="gcc"
fi
log_info "Using compiler: $CXX_BIN / $CC_BIN"

# Prepare QMake configuration
CONFIG_FLAGS="CONFIG += release_lin build_original"
if [ "$EXCLUDE_FW" = true ]; then
    CONFIG_FLAGS="$CONFIG_FLAGS exclude_fw"
fi
if [ "$TARGET_MODE" = "mobile" ]; then
    CONFIG_FLAGS="$CONFIG_FLAGS build_mobile"
fi

# Workaround for LTCG ICE on modern GCC versions
QMAKE_EXTRA_ARGS=(
    "CONFIG -= ltcg"
    "QMAKE_CFLAGS_LTCG = "
    "QMAKE_CXXFLAGS_LTCG = "
    "QMAKE_LFLAGS_LTCG = "
    "QMAKE_CXX=$CXX_BIN"
    "QMAKE_CC=$CC_BIN"
    "QMAKE_LINK=$CXX_BIN"
)

log_info "Target mode: $TARGET_MODE"
log_info "Parallel jobs: $JOBS"
log_info "Config flags: $CONFIG_FLAGS"

if [ "$CLEAN_BUILD" = true ]; then
    log_info "Cleaning previous build..."
    if [ -f Makefile ]; then
        make clean 2>/dev/null || true
    fi
    rm -rf build/lin/*
fi

mkdir -p build/lin

log_info "Running qmake..."
"$QMAKE_BIN" -config release "$CONFIG_FLAGS" "${QMAKE_EXTRA_ARGS[@]}"

log_info "Compiling with make (-j$JOBS)..."
if ! make -j"$JOBS"; then
    log_warn "Transient compiler error encountered, retrying parallel compilation..."
    if ! make -j"$JOBS"; then
        log_warn "Retrying remaining files sequentially..."
        make -j1
    fi
fi

# Locate built binary
OUTPUT_BIN=$(find build/lin -maxdepth 1 -type f -name "vesc_tool*" -executable | head -n 1)

if [ -z "$OUTPUT_BIN" ]; then
    log_error "Build finished but executable was not found in build/lin/!"
    exit 1
fi

log_success "Build complete: $OUTPUT_BIN"

# Show version
"$OUTPUT_BIN" --version 2>/dev/null || true

# Run application if requested
if [ "$RUN_AFTER" = true ]; then
    log_info "Launching $OUTPUT_BIN..."
    if [ "$TARGET_MODE" = "mobile" ]; then
        exec "$OUTPUT_BIN"
    else
        exec "$OUTPUT_BIN"
    fi
fi
