#!/bin/bash
# Build Clicker plugin for Linux/macOS
# Usage: build_unix.sh [plugin_name]
# Example: ./build_unix.sh example_plugin

set -e

PLUGIN_NAME="${1:-example_plugin}"
PLATFORM="$(uname -s)"

echo "Building $PLUGIN_NAME for $PLATFORM..."

mkdir -p "../linux" "../darwin"

if [ "$PLATFORM" = "Linux" ]; then
    gcc -shared -fPIC -O2 -Wall main.c -I. -o "../linux/$PLUGIN_NAME.so"
    echo "SUCCESS: ../linux/$PLUGIN_NAME.so"
elif [ "$PLATFORM" = "Darwin" ]; then
    clang -shared -fPIC -O2 -Wall main.c -I. -o "../darwin/$PLUGIN_NAME.dylib"
    echo "SUCCESS: ../darwin/$PLUGIN_NAME.dylib"
else
    echo "ERROR: Unsupported platform: $PLATFORM"
    exit 1
fi
