#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_NAME="ai_tracker"
OUTPUT_DIR="${SCRIPT_DIR}/../android/jniLibs"

NDK_PATH="${ANDROID_NDK_HOME:-$HOME/Android/Sdk/ndk/26.1.10909125}"
TOOLCHAIN="${NDK_PATH}/build/cmake/android.toolchain.cmake"

if [ ! -f "$TOOLCHAIN" ]; then
    echo "Error: Android NDK toolchain not found at $TOOLCHAIN"
    echo "Set ANDROID_NDK_HOME environment variable"
    exit 1
fi

build_for_abi() {
    local ABI=$1
    local API_LEVEL=$2

    echo "Building for ${ABI}..."
    local BUILD_DIR="${SCRIPT_DIR}/build_android_${ABI}"
    mkdir -p "${BUILD_DIR}"
    cd "${BUILD_DIR}"

    cmake \
        -DCMAKE_TOOLCHAIN_FILE="${TOOLCHAIN}" \
        -DANDROID_ABI="${ABI}" \
        -DANDROID_PLATFORM=android-${API_LEVEL} \
        -DCMAKE_BUILD_TYPE=Release \
        "${SCRIPT_DIR}"

    cmake --build . --config Release

    local LIB_DIR="${OUTPUT_DIR}/${ABI}"
    mkdir -p "${LIB_DIR}"
    cp "lib${PLUGIN_NAME}.so" "${LIB_DIR}/"

    echo "Built ${ABI}: ${LIB_DIR}/lib${PLUGIN_NAME}.so"
}

build_for_abi arm64-v8a 21
build_for_abi armeabi-v7a 21
build_for_abi x86_64 21

echo "Android build complete!"
