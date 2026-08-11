#!/bin/bash

export WEBRTC_VERSION_BRANCH_NAME="7339"

export MEDIASOUP_ANDROID_CLIENT_VERSION_NAME="3.5.0"

# NDK 27 (clang 18) and platform 35 are required by mediasoup-client-android
# 3.5.0: it builds with C++20 and AGP 8.7.3, which needs compileSdk 35.
export ANDROID_NDK_VERSION="27.1.12297006"
export CMAKE_VERSION="3.22.1"
export ANDROID_SDK_BUILD_TOOLS_VERSION="35.0.0"
export ANDROID_SDK_PLATFORM_VERSION="android-35"

export SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

SUPPORTED_ARCHS=("x86_64" "armeabi-v7a" "arm64-v8a")

$SCRIPT_DIR/1_install_prebuild_dependencies.sh
source $SCRIPT_DIR/2_inject_prebuild_dependencies.sh
$SCRIPT_DIR/3_get_webrtc_android_sources.sh
$SCRIPT_DIR/4_checkout_webrtc_working_branch.sh
$SCRIPT_DIR/5_apply_patches.sh
$SCRIPT_DIR/6_build_webrtc.sh "${SUPPORTED_ARCHS[@]}"
$SCRIPT_DIR/7_get_actual_android_mediasoup_client_version.sh
$SCRIPT_DIR/8_inject_webrtc_dependencies_to_android_mediasoup_client.sh "${SUPPORTED_ARCHS[@]}"
$SCRIPT_DIR/9_get_android_sdk_dependecies.sh
$SCRIPT_DIR/10_build_android_mediasoup_client.sh
