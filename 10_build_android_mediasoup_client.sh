#!/bin/bash

cd mediasoup-client-android	
rm -rf ./gradle/caches

bash ./gradlew clean

# assembleRelease, not assemble: the debug variant cannot link against our
# libwebrtc.a. We build WebRTC with is_debug=false, so DCHECK is off and
# third_party/jni_zero/java_refs.h defines JavaRef(JNIEnv*, jobject) inline.
# A debug build of the JNI layer has DCHECK on, where that constructor is only
# declared and expected out-of-line, so linking fails with:
#   undefined symbol: jni_zero::JavaRef<_jobject*>::JavaRef(_JNIEnv*, _jobject*)
bash ./gradlew assembleRelease

cd $SCRIPT_DIR
rm -rfv ./output
cp -rv ./mediasoup-client-android/mediasoup-client/build/outputs/aar ./output
cp -v ./mediasoup-client-android/mediasoup-client/deps/webrtc/lib/libwebrtc.aar ./output/

# Same check as in step 6, now on what actually ships. mediasoup-client's own
# classes.jar references org.webrtc, so libwebrtc.aar is passed as its classpath.
echo "Check output aar consistency"
./check_aar_consistency.sh ./output/libwebrtc.aar || exit 1
./check_aar_consistency.sh ./output/mediasoup-client-release.aar ./output/libwebrtc.aar || exit 1

printf "\n\n\n\n"
echo "                           *                           "
echo "                          ***                          "
echo "                          ***                          "
echo "                          ***                          "
echo "                          ***                          "
echo "             *            ***            *             "
echo "             **           ***           **             "
echo "             ***          ***          ***             "
echo "              ***         ***         ***              "
echo "               ****       ***       ****               "
echo "                ****      ***      ****                "
echo "                  ****    ***    ****                  "
echo "                   *****  ***  *****                   "
echo "                     *************                     "
echo "                      ***********                      "
echo "                        *******                        "
echo "                          ***                          "
echo "                           *                           "
echo "the final build output is here ---> $SCRIPT_DIR/output"
