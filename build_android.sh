#!/usr/bin/env bash
#
# VESC Tool Android APK Build Script
#
# Builds Android APK (mobile and/or full version) with automatic
# detection of Android SDK, NDK, JDK, and Qt 5 for Android.
#

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
BOLD='\033[1m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
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
BUILD_MOBILE=true
BUILD_FULL=false
TARGET_ARCH="arm64-v8a"
CLEAN_BUILD=false
CLEAN_ONLY=false
CREATE_ZIP=false
INSTALL_ADB=false
SETUP_DEPS=false

SDK_PATH=""
NDK_PATH=""
QT_PATH=""
JAVA_PATH=""
PLATFORM_API=""

CPU_COUNT=$(nproc 2>/dev/null || echo 4)
if [ "$CPU_COUNT" -gt 8 ]; then
    DEFAULT_JOBS=8
else
    DEFAULT_JOBS="$CPU_COUNT"
fi
JOBS="$DEFAULT_JOBS"

show_help() {
    echo -e "${BOLD}VESC Tool Android APK Build Script${NC}

${BOLD}USAGE:${NC}
  ./build_android.sh [OPTIONS]

${BOLD}BUILD TARGETS:${NC}
  -m, --mobile          Build mobile UI APK (default: vesc_tool_mobile.apk)
  -f, --full            Build full desktop-in-mobile APK (vesc_tool_full.apk)
  -a, --all             Build both mobile and full APKs

${BOLD}OPTIONS:${NC}
      --arch <ABI>      Target ABI: arm64-v8a (default), armeabi-v7a, x86_64, x86
  -j, --jobs <N>        Parallel make jobs (default: ${DEFAULT_JOBS})
  -c, --clean           Perform a clean before building
      --clean-only      Clean android build artifacts and exit
      --zip             Create build/android/vesc_tool_android.zip
  -i, --install         Install built APK to connected device via 'adb install -r'

${BOLD}ENVIRONMENT OVERRIDES:${NC}
      --sdk <PATH>      Path to Android SDK (e.g. ~/Android/Sdk)
      --ndk <PATH>      Path to Android NDK (e.g. ~/Android/Sdk/ndk/23.1.7779620)
      --qt <PATH>       Path to Qt 5 Android (e.g. ~/Qt/5.15.2/android)
      --java <PATH>     Path to JAVA_HOME (e.g. /usr/lib/jvm/java-11-openjdk)
      --platform <API>  Android API level (e.g. android-34, auto-detected if omitted)

${BOLD}DEPENDENCY SETUP:${NC}
      --setup-deps      Automatically download & install Qt 5.15.2 Android and NDK r23c
                        using aqtinstall into local user directories (~/Qt and ~/Android/Sdk/ndk).

${BOLD}EXAMPLES:${NC}
  ./build_android.sh                     # Build mobile APK (arm64-v8a)
  ./build_android.sh --all               # Build both mobile & full APKs
  ./build_android.sh -m -i               # Build mobile APK and deploy to phone via ADB
  ./build_android.sh --setup-deps        # Auto-download Qt Android & NDK r23c if missing"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -m|--mobile)
            BUILD_MOBILE=true
            BUILD_FULL=false
            shift
            ;;
        -f|--full)
            BUILD_MOBILE=false
            BUILD_FULL=true
            shift
            ;;
        -a|--all)
            BUILD_MOBILE=true
            BUILD_FULL=true
            shift
            ;;
        --arch)
            TARGET_ARCH="$2"
            shift 2
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
        -c|--clean)
            CLEAN_BUILD=true
            shift
            ;;
        --clean-only)
            CLEAN_ONLY=true
            shift
            ;;
        --zip)
            CREATE_ZIP=true
            shift
            ;;
        -i|--install)
            INSTALL_ADB=true
            shift
            ;;
        --sdk)
            SDK_PATH="$2"
            shift 2
            ;;
        --ndk)
            NDK_PATH="$2"
            shift 2
            ;;
        --qt)
            QT_PATH="$2"
            shift 2
            ;;
        --java)
            JAVA_PATH="$2"
            shift 2
            ;;
        --platform)
            PLATFORM_API="$2"
            shift 2
            ;;
        --setup-deps)
            SETUP_DEPS=true
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
    log_info "Cleaning Android build artifacts..."
    if [ -f Makefile ]; then
        make clean 2>/dev/null || true
        rm -f Makefile
    fi
    rm -rf build/android/*
    rm -f android-vesc_tool-deployment-settings.json
    log_success "Clean completed."
    exit 0
fi

# Function to auto-install dependencies if requested
if [ "$SETUP_DEPS" = true ]; then
    log_info "Running dependency setup for Qt 5.15.2 Android & NDK..."
    VENV_DIR="$HOME/.cache/vesc_tool_android_aqt_venv"
    if [ ! -f "$VENV_DIR/bin/aqt" ]; then
        log_info "Creating helper venv at $VENV_DIR..."
        python3 -m venv "$VENV_DIR"
        "$VENV_DIR/bin/pip" install --upgrade pip aqtinstall
    fi
    TARGET_QT_DIR="$HOME/Qt"
    if [ ! -f "$TARGET_QT_DIR/5.15.2/android/bin/qmake" ]; then
        log_info "Downloading Qt 5.15.2 for Android into $TARGET_QT_DIR..."
        "$VENV_DIR/bin/aqt" install-qt linux android 5.15.2 -O "$TARGET_QT_DIR" \
            --archives qtbase qtconnectivity qtandroidextras qtsvg qtdeclarative \
                       qtserialport qtlocation qtquickcontrols qtquickcontrols2 \
                       qtgamepad qtgraphicaleffects qttools
        log_success "Qt 5.15.2 Android installed to $TARGET_QT_DIR/5.15.2/android"
    else
        log_info "Qt 5.15.2 Android is already present at $TARGET_QT_DIR/5.15.2/android"
    fi
    SDK_DIR="${ANDROID_HOME:-$HOME/Android/Sdk}"
    NDK_TARGET_DIR="$SDK_DIR/ndk/android-ndk-r23c"
    if [ ! -d "$NDK_TARGET_DIR" ]; then
        mkdir -p "$SDK_DIR/ndk"
        TMP_NDK_ZIP="/tmp/android-ndk-r23c-linux.zip"
        log_info "Downloading Android NDK r23c (compatible with Qt 5.15)..."
        curl -L -o "$TMP_NDK_ZIP" "https://dl.google.com/android/repository/android-ndk-r23c-linux.zip"
        log_info "Extracting NDK..."
        unzip -q "$TMP_NDK_ZIP" -d "$SDK_DIR/ndk/"
        rm -f "$TMP_NDK_ZIP"
        log_success "NDK r23c installed to $NDK_TARGET_DIR"
    else
        log_info "NDK r23c is already present at $NDK_TARGET_DIR"
    fi
    log_success "All dependencies configured! You can now run ./build_android.sh to build your APK."
    exit 0
fi

# 1. Detect Java JDK
if [ -n "$JAVA_PATH" ]; then
    JAVA_HOME="$JAVA_PATH"
elif [ -z "$JAVA_HOME" ]; then
    for candidate in \
        /usr/lib/jvm/java-11-openjdk \
        /usr/lib/jvm/java-17-openjdk \
        /usr/lib/jvm/java-8-openjdk \
        /opt/android-studio/jbr \
        /usr/lib/jvm/default \
        /usr/lib/jvm/java-1.8.0-openjdk-amd64
    do
        if [ -x "$candidate/bin/javac" ]; then
            JAVA_HOME="$candidate"
            break
        fi
    done
fi

if [ -z "$JAVA_HOME" ] || [ ! -x "$JAVA_HOME/bin/javac" ]; then
    log_error "Could not find a valid Java JDK (JAVA_HOME)."
    log_error "Please install JDK 11 (e.g. sudo pacman -S jdk11-openjdk) or specify with --java <PATH>."
    exit 1
fi
export JAVA_HOME
log_info "Using JAVA_HOME: $JAVA_HOME"

# 2. Detect Android SDK
if [ -n "$SDK_PATH" ]; then
    ANDROID_HOME="$SDK_PATH"
elif [ -z "$ANDROID_HOME" ]; then
    for candidate in \
        "$ANDROID_SDK_ROOT" \
        "$HOME/Android/Sdk" \
        "$HOME/Android/Latest/Sdk" \
        /opt/android-sdk \
        "$HOME/.android-sdk"
    do
        if [ -n "$candidate" ] && [ -d "$candidate/platforms" ]; then
            ANDROID_HOME="$candidate"
            break
        fi
    done
fi

if [ -z "$ANDROID_HOME" ] || [ ! -d "$ANDROID_HOME" ]; then
    log_error "Could not find Android SDK."
    log_error "Please set ANDROID_HOME or provide --sdk <PATH> (e.g. ~/Android/Sdk)."
    exit 1
fi
export ANDROID_HOME
export ANDROID_SDK_ROOT="$ANDROID_HOME"
log_info "Using Android SDK: $ANDROID_HOME"

# 3. Detect Android NDK
if [ -n "$NDK_PATH" ]; then
    ANDROID_NDK_ROOT="$NDK_PATH"
elif [ -z "$ANDROID_NDK_ROOT" ]; then
    # Search for Qt 5-compatible NDK (r21 - r23 preferred)
    for candidate in \
        "$ANDROID_HOME/ndk/android-ndk-r23c" \
        "$ANDROID_HOME/ndk/android-ndk-r23d-canary" \
        "$ANDROID_HOME/ndk/23."* \
        "$ANDROID_HOME/ndk/android-ndk-r22"* \
        "$ANDROID_HOME/ndk/22."* \
        "$ANDROID_HOME/ndk/android-ndk-r21"* \
        "$ANDROID_HOME/ndk/21."* \
        "$HOME/Android/Latest/Sdk/ndk/android-ndk-r23d-canary"
    do
        if [ -d "$candidate/toolchains" ]; then
            ANDROID_NDK_ROOT="$candidate"
            break
        fi
    done

    # If no r21-r23 NDK found, check if any NDK exists, but warn
    if [ -z "$ANDROID_NDK_ROOT" ]; then
        for candidate in "$ANDROID_HOME/ndk/"*; do
            if [ -d "$candidate/toolchains" ]; then
                log_warn "Found NDK at $candidate, but Qt 5.15 officially recommends NDK r21-r23."
                log_warn "If you encounter build errors, run './build_android.sh --setup-deps' to install NDK r23c."
                ANDROID_NDK_ROOT="$candidate"
                break
            fi
        done
    fi
fi

if [ -z "$ANDROID_NDK_ROOT" ] || [ ! -d "$ANDROID_NDK_ROOT" ]; then
    log_error "Could not find Android NDK compatible with Qt 5."
    log_error "Run './build_android.sh --setup-deps' to download NDK r23c automatically,"
    log_error "or pass an existing NDK path with --ndk <PATH>."
    exit 1
fi
export ANDROID_NDK_ROOT
export ANDROID_NDK_HOST="linux-x86_64"
log_info "Using Android NDK: $ANDROID_NDK_ROOT"

# 4. Detect Qt 5 for Android
if [ -n "$QT_PATH" ]; then
    QT_ANDROID="$QT_PATH"
elif [ -z "$QT_ANDROID" ]; then
    for candidate in \
        "$HOME/Qt/5.15.2/android" \
        "$HOME/Qt/5.15.*/android" \
        /opt/Qt5/5.15.2/android \
        /opt/Qt/5.15.2/android \
        /opt/Qt/5.15.*/android \
        "$HOME/.local/Qt/5.15.2/android" \
        "$HOME/Qt/5.15.2/android_arm64_v8a"
    do
        if [ -x "$candidate/bin/qmake" ]; then
            QT_ANDROID="$candidate"
            break
        fi
    done
fi

if [ -z "$QT_ANDROID" ] || [ ! -x "$QT_ANDROID/bin/qmake" ]; then
    log_error "Qt 5 for Android not found!"
    log_error "Run './build_android.sh --setup-deps' to download Qt 5.15.2 Android automatically,"
    log_error "or specify existing Qt 5 Android with --qt <PATH>."
    exit 1
fi
export PATH="$QT_ANDROID/bin:$ANDROID_HOME/platform-tools:$JAVA_HOME/bin:$PATH"
log_info "Using Qt Android: $QT_ANDROID"

# 5. Detect Android Platform
if [ -z "$PLATFORM_API" ]; then
    if [ -d "$ANDROID_HOME/platforms" ]; then
        PLATFORM_API=$(ls -1d "$ANDROID_HOME/platforms/android-"* 2>/dev/null | sort -V | tail -n 1 | xargs -n 1 basename)
    fi
fi
PLATFORM_API="${PLATFORM_API:-android-34}"
log_info "Target Android Platform API: $PLATFORM_API"

# Target ABI triple mapping
case "$TARGET_ARCH" in
    arm64-v8a)
        ARCH_TRIPLE="aarch64-linux-android"
        ;;
    armeabi-v7a)
        ARCH_TRIPLE="arm-linux-androideabi"
        ;;
    x86_64)
        ARCH_TRIPLE="x86_64-linux-android"
        ;;
    x86)
        ARCH_TRIPLE="i686-linux-android"
        ;;
    *)
        ARCH_TRIPLE="$TARGET_ARCH"
        ;;
esac

# 6. Generate dynamic deployment settings JSON
log_info "Configuring android deployment settings for $TARGET_ARCH..."
SETTINGS_FILE="$SCRIPT_DIR/android-vesc_tool-deployment-settings.json"
cat > "$SETTINGS_FILE" <<EOF
{
   "description": "Auto-generated by build_android.sh for androiddeployqt",
   "qt": "$QT_ANDROID",
   "sdk": "$ANDROID_HOME",
   "sdkBuildToolsRevision": "",
   "ndk": "$ANDROID_NDK_ROOT",
   "toolchain-prefix": "llvm",
   "tool-prefix": "llvm",
   "ndk-host": "linux-x86_64",
   "architectures": {"$TARGET_ARCH":"$ARCH_TRIPLE"},
   "android-package-source-directory": "$SCRIPT_DIR/android",
   "qml-root-path": "$SCRIPT_DIR",
   "stdcpp-path": "/sysroot/usr/lib/",
   "qrcFiles": "$SCRIPT_DIR/mobile/qml.qrc,$SCRIPT_DIR/QCodeEditor/resources/qcodeeditor_resources.qrc,$SCRIPT_DIR/qmarkdowntextedit/media.qrc,$SCRIPT_DIR/res.qrc,$SCRIPT_DIR/res_custom_module.qrc,$SCRIPT_DIR/res_lisp.qrc,$SCRIPT_DIR/res_qml.qrc,$SCRIPT_DIR/res/config/res_config.qrc,$SCRIPT_DIR/res_fw_bms.qrc,$SCRIPT_DIR/res_neutral.qrc",
   "application-binary": "vesc_tool"
}
EOF

mkdir -p build/android

if [ "$CLEAN_BUILD" = true ]; then
    log_info "Cleaning previous android builds..."
    rm -rf build/android/*
    if [ -f Makefile ]; then
        make clean 2>/dev/null || true
    fi
fi

# Build function for a specific variant
build_apk() {
    local variant="$1" # "mobile" or "full"
    local config_flag="$2" # e.g. "CONFIG += release_android build_mobile"
    local output_name="vesc_tool_${variant}.apk"

    log_info "=========================================="
    log_info "Building VESC Tool APK: ${BOLD}${variant}${NC} (${TARGET_ARCH})"
    log_info "=========================================="

    log_info "Running qmake..."
    qmake -config release "$config_flag" ANDROID_ABIS="$TARGET_ARCH" -spec android-clang

    log_info "Cleaning previous objects..."
    make clean 2>/dev/null || true

    log_info "Compiling with make (-j$JOBS)..."
    make -j"$JOBS"

    log_info "Installing to build root..."
    rm -rf build/android/build
    make install INSTALL_ROOT=build/android/build

    log_info "Packaging APK with androiddeployqt..."
    androiddeployqt --gradle --no-gdbserver \
                    --output build/android/build \
                    --input "$SETTINGS_FILE" \
                    --android-platform "$PLATFORM_API"

    local FOUND_APK=""
    FOUND_APK=$(find build/android/build/build/outputs/apk -type f -name "*.apk" 2>/dev/null | head -n 1)

    if [ -z "$FOUND_APK" ] || [ ! -f "$FOUND_APK" ]; then
        log_error "Failed to produce APK for $variant!"
        exit 1
    fi

    cp "$FOUND_APK" "build/android/$output_name"
    local APK_SIZE
    APK_SIZE=$(du -h "build/android/$output_name" | cut -f1)
    log_success "Created APK: build/android/$output_name ($APK_SIZE)"

    rm -rf build/android/build
    rm -rf build/android/obj
    rm -f build/android/libvesc_tool*

    if [ "$INSTALL_ADB" = true ]; then
        log_info "Deploying $output_name to connected device..."
        if command -v adb >/dev/null 2>&1; then
            adb install -r "build/android/$output_name"
            log_success "Successfully installed $output_name via ADB!"
        else
            log_warn "adb command not found; skipping device installation."
        fi
    fi
}

if [ "$BUILD_MOBILE" = true ]; then
    build_apk "mobile" "CONFIG += release_android build_mobile"
fi

if [ "$BUILD_FULL" = true ]; then
    build_apk "full" "CONFIG += release_android"
fi

if [ "$CREATE_ZIP" = true ]; then
    cd build/android
    ZIP_FILES=()
    [ -f "vesc_tool_mobile.apk" ] && ZIP_FILES+=("vesc_tool_mobile.apk")
    [ -f "vesc_tool_full.apk" ] && ZIP_FILES+=("vesc_tool_full.apk")
    if [ ${#ZIP_FILES[@]} -gt 0 ]; then
        zip -u vesc_tool_android.zip "${ZIP_FILES[@]}"
        log_success "Created archive: build/android/vesc_tool_android.zip"
    fi
    cd "$SCRIPT_DIR"
fi

echo ""
log_success "Android build completed successfully!"
ls -lh build/android/*.apk 2>/dev/null || true

