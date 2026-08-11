#!/bin/bash

function get_target_cpu() {
 local arch_type="$1"
 if [[ $arch_type == "x86" ]]
 then
  target_cpu="x86"
 elif [[ $arch_type == "x86_64" ]]
 then
  target_cpu="x64"
 elif [[ $arch_type == "armeabi-v7a" ]]
 then
  target_cpu="arm"
 elif [[ $arch_type == "arm64-v8a" ]]
 then
  target_cpu="arm64"
 fi
 echo "$target_cpu"
}

# When building webrtc 6099 with is_debug=true, there was an error when turning off the camera:
# "mediasoup-android-client-builder/webrtc_android/src/pc/rtp_sender.cc", 799, "(signaling_thread_)->IsCurrent()" was observed.
# Printing out the thread name, it matched signaling_thread_, error is in the RTC_DCHECK_RUN_ON check itself.
# See related issue: https://groups.google.com/g/discuss-webrtc/c/pm56BSiAa-E
# android_static_analysis="off" disables the Errorprone Java compiler.
# Without it the build fails with:
#   ninja: error: '../../third_party/android_build_tools/nullaway/cipd/nullaway.jar',
#   needed by 'obj/rtc_base/base_java__errorprone.stamp', missing
# build/config/android/internal_rules.gni references that jar whenever errorprone
# is enabled, but webrtc's DEPS does not fetch the nullaway CIPD package, so it is
# never present. Errorprone only static-analyses Java sources and is not needed to
# produce the library.
#
# use_rtti=true is needed by mediasoup-client-android: libmediasoupclient
# instantiates webrtc::VideoDecoderFactoryTemplate<...>, which references
# "typeinfo for webrtc::VideoDecoderFactory". WebRTC defaults to -fno-rtti, so
# that typeinfo is never emitted and the .so fails to link.
#
# libyuv_use_sme=false drops third_party/libyuv/source/*_sme.cc. That SME code
# references __arm_tpidr2_save, which exists in the NDK's
# libclang_rt.builtins-aarch64.a but NOT in the -android variant that gets
# linked for Android targets. Upstream knows this is fragile: see the TODO on
# bug 359006069 above the libyuv_use_sme declaration in libyuv.gni.
COMMON_ARGS='ffmpeg_branding="Chrome" rtc_use_h264=true is_clang=true is_component_build=false is_debug=false rtc_build_examples=false rtc_build_tools=false rtc_enable_protobuf=false rtc_include_tests=false use_custom_libcxx=false target_os="android" android_static_analysis="off" use_rtti=true libyuv_use_sme=false'

ARCH_TYPES=("$@")

cd $SCRIPT_DIR/webrtc_android/src

./build/install-build-deps.sh --android
source build/android/envsetup.sh


for arch_type in "${ARCH_TYPES[@]}"
do
 target_cpu="$(get_target_cpu $arch_type)"
 echo "Gn gen for $target_cpu"
 gn gen out/$arch_type --args="$COMMON_ARGS target_cpu=\"$target_cpu\""
done

for arch_type in "${ARCH_TYPES[@]}"
do
 target_cpu="$(get_target_cpu $arch_type)"
 echo "Build $target_cpu"
 ninja -C ./out/$arch_type/
done

echo "Build aar"
./tools_webrtc/android/build_aar.py --arch ${ARCH_TYPES[@]} --extra-gn-args "$COMMON_ARGS"


mkdir -p ../build_output
cd ../build_output
rm -rf *

cp -v ../src/libwebrtc.aar ./libwebrtc.aar

# build_aar.py writes LICENSE.md next to the .aar, not inside it. Since this
# build enables H264, the aar links ffmpeg (LGPL 2.1) and openh264, so ship the
# generated license text alongside the artifact.
cp -v ../src/LICENSE.md ./LICENSE.md

for arch_type in "${ARCH_TYPES[@]}"
do
 mkdir $arch_type
 cp -v ../src/out/$arch_type/obj/libwebrtc.a ./$arch_type/libwebrtc.a
done

# The aar can be built successfully and still be unusable: classes.jar is
# whatever dist_jar("libwebrtc") happened to pack, and a Java class silently
# dropped there only shows up as a NoClassDefFoundError on the user's device.
# That is exactly what happened with org.webrtc.Environment in M140.
echo "Check aar consistency"
$SCRIPT_DIR/check_aar_consistency.sh ./libwebrtc.aar || exit 1
