#!/bin/bash

#"git apply some.patch" causes errors when reapplying a patch.
# It may be fixed by:
# "git apply abc.patch || git apply abc.patch -R --check && echo already applied"
# But this behavior allows you to see real errors during the first patch.

echo "Apply webrtc h264 codec support patch"
cd $SCRIPT_DIR/webrtc_android/src/third_party/ffmpeg
git apply $SCRIPT_DIR/webrtc_h264_codec_support.patch


# Who use "use_custom_libcxx=false" argument build for android
# got "undefined symbol: _Unwind_Backtrace" mistake should do like this:
# https://bugs.chromium.org/p/webrtc/issues/detail?id=13535
echo "Apply use custom libcxx argument support patch"
cd $SCRIPT_DIR/webrtc_android/src/buildtools
git apply $SCRIPT_DIR/use_custom_libcxx_argument_buildtools_support.patch

cd $SCRIPT_DIR/webrtc_android/src/build
git apply $SCRIPT_DIR/use_custom_libcxx_argument_build_support.patch


#webrtc_voice_engine.cc create a default AudioDeviceModule if no supplied.
#    adm_ = CreateAudioDeviceModule(
#       env_, webrtc::AudioDeviceModule::kPlatformDefaultAudio)
# That goes to AudioDeviceModuleImpl::Create, which has no Android backend
# (CreatePlatformSpecificObjects only covers Windows/Linux/iOS/Mac) and so
# returns null on Android. The patch routes it to the Android ADM instead.
echo "Apply support default audio device module patch"
cd $SCRIPT_DIR/webrtc_android/src
git apply $SCRIPT_DIR/support_default_audio_device_module_for_webrtc_voice_engine.patch


# build_aar.py refuses to package the AAR when a linked third_party library has
# no license mapping:
#   Exception: Missing licenses for third_party targets: ffmpeg, openh264
# Upstream omits them because the default build disables H264, so they are never
# linked. We enable them, so their licenses must ship in the AAR.
echo "Apply aar licenses for h264 patch"
cd $SCRIPT_DIR/webrtc_android/src
git apply $SCRIPT_DIR/aar_licenses_for_h264.patch


# dist_jar("libwebrtc") in sdk/android/BUILD.gn sets direct_deps_only = true, so
# only the classes of the targets listed in its deps land in classes.jar.
# M140 added api/org/webrtc/Environment.java in its own environment_java target
# and hung it off peerconnection_java, i.e. one level too deep. The result is an
# aar whose PeerConnectionFactory is compiled against org.webrtc.Environment
# while the class itself is missing, so every app dies at startup with
#   java.lang.NoClassDefFoundError: Failed resolution of: Lorg/webrtc/Environment;
#   at org.webrtc.PeerConnectionFactory$Builder.<init>
# The patch also drops package= and <uses-sdk> from the aar manifest, which AGP 8
# rejects.
echo "Apply aar java classes and manifest patch"
cd $SCRIPT_DIR/webrtc_android/src
git apply $SCRIPT_DIR/aar_java_classes_and_manifest.patch
