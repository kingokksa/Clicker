#!/bin/bash
# Build AI Tracker plugin for Linux (GCC/Clang)
# Requires: libx11-dev, libxext-dev, libxfixes-dev, libxi-dev
# ONNX Runtime is loaded dynamically at runtime

set -e

PLUGIN_NAME="ai_tracker"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/../linux"

echo "Building ${PLUGIN_NAME} (Linux) ..."

# Check for required tools
if ! command -v g++ &> /dev/null && ! command -v clang++ &> /dev/null; then
    echo "ERROR: No C++ compiler found. Install g++ or clang++."
    exit 1
fi

# Use g++ if available, otherwise clang++
if command -v g++ &> /dev/null; then
    CXX="g++"
else
    CXX="clang++"
fi

echo "Using compiler: $CXX"

# Create output directory
mkdir -p "${OUTPUT_DIR}"

# Copy SDK header if not present
SDK_HEADER="${SCRIPT_DIR}/clicker_plugin.h"
ROOT_SDK_HEADER="${SCRIPT_DIR}/../../../sdk/clicker_plugin.h"
if [ ! -f "${SDK_HEADER}" ] && [ -f "${ROOT_SDK_HEADER}" ]; then
    cp "${ROOT_SDK_HEADER}" "${SDK_HEADER}"
fi

# Compile as shared library (.so)
# -fPIC: Position Independent Code required for shared libraries
# -std=c++17: C++17 standard (compatible with Flutter Linux runner)
# -O2: Optimization level 2
# -Wall: Enable warnings
${CXX} -shared -fPIC \
    -O2 -Wall -Wextra \
    -std=c++17 \
    -D PLUGIN_EXPORTS \
    main.cpp \
    -o "${OUTPUT_DIR}/lib${PLUGIN_NAME}.so" \
    -ldl

if [ $? -ne 0 ]; then
    echo "ERROR: Build failed."
    exit 1
fi

# Clean up object files if any
rm -f *.o 2>/dev/null || true

echo ""
echo "SUCCESS: ${OUTPUT_DIR}/lib${PLUGIN_NAME}.so"
echo ""
echo "NOTE: To enable AI detection:"
echo "      1. Place libonnxruntime.so in the same directory or system library path"
echo "      2. Place a YOLO .onnx model file in the models/ subdirectory"
echo ""
echo "Install dependencies on Ubuntu/Debian:"
echo "  sudo apt install libx11-dev libxext-dev libxfixes-dev libxi-dev"
