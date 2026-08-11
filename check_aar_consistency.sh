#!/bin/bash
#
# Sanity-checks a built .aar before it is shipped.
#
# Catches the class of defect described in WEBRTC_AAR_ENVIRONMENT_BUG.md: the aar
# built fine, every ninja step succeeded, but classes.jar was missing
# org/webrtc/Environment, so every consumer crashed on the first
# PeerConnectionFactory.builder() call with NoClassDefFoundError. Nothing in the
# WebRTC build catches that — dist_jar just packs whatever its direct deps
# produce, and a class dropped there is only noticed at runtime.
#
# Three checks:
#   1. dangling references — every org/webrtc/* class named in the constant pool
#      of any class in the jar must itself be present in the jar;
#   2. JNI/Java split — every Java_org_webrtc_<Class>_* symbol exported by the
#      native library must have its Java counterpart in the jar. A native half
#      without a Java half is exactly how the Environment bug looked;
#   3. manifest — reports package= / <uses-sdk>, which consumers on AGP 8 have to
#      strip if they reuse the manifest. Informational only, never fails.
#
# Usage: ./check_aar_consistency.sh <aar> [dependency aar or jar]...
#
#   ./check_aar_consistency.sh libwebrtc.aar
#   ./check_aar_consistency.sh mediasoup-client-release.aar libwebrtc.aar
#
# Classes from the dependency archives count as present, so an aar that legitimately
# links against another one (mediasoup-client calls into org.webrtc) is not reported
# as broken. Without them every org/webrtc reference in mediasoup's classes.jar
# would look dangling.
#
# Exit code 0 = clean, 1 = problems found (printed to stderr).

set -u

AAR="${1:-}"
shift || true
DEPS=("$@")

if [[ -z "$AAR" || ! -f "$AAR" ]]
then
 echo "usage: $0 <aar> [dependency aar or jar]..." >&2
 exit 2
fi

for tool in unzip javap nm perl
do
 if ! command -v "$tool" >/dev/null 2>&1
 then
  echo "check_aar_consistency: '$tool' not found in PATH" >&2
  exit 2
 fi
done

AAR="$(cd "$(dirname "$AAR")" && pwd)/$(basename "$AAR")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Checking $(basename "$AAR")"

unzip -o -q "$AAR" -d "$WORK/aar"

if [[ ! -f "$WORK/aar/classes.jar" ]]
then
 echo "FAIL: no classes.jar inside $AAR" >&2
 exit 1
fi

unzip -o -q "$WORK/aar/classes.jar" -d "$WORK/classes"

unzip -Z1 "$WORK/aar/classes.jar" | grep '\.class$' | sed 's/\.class$//' \
 | sort -u > "$WORK/present.txt"

echo "  classes.jar: $(wc -l < "$WORK/present.txt") classes"

# Classes the aar is allowed to reference: its own, plus everything the
# dependency archives ship.
cp "$WORK/present.txt" "$WORK/resolvable.txt"

for dep in ${DEPS+"${DEPS[@]}"}
do
 if [[ ! -f "$dep" ]]
 then
  echo "check_aar_consistency: dependency '$dep' not found" >&2
  exit 2
 fi
 if [[ "$dep" == *.aar ]]
 then
  rm -rf "$WORK/dep"
  unzip -o -q "$dep" -d "$WORK/dep"
  jar="$WORK/dep/classes.jar"
 else
  jar="$dep"
 fi
 unzip -Z1 "$jar" | grep '\.class$' | sed 's/\.class$//' >> "$WORK/resolvable.txt"
 echo "  dependency $(basename "$dep"): $(unzip -Z1 "$jar" | grep -c '\.class$') classes"
done

sort -u -o "$WORK/resolvable.txt" "$WORK/resolvable.txt"

failed=0

# 1. Dangling references.
#
# javap -verbose prints one "= Class #N // some/Class/Name" line per Class entry
# in the constant pool. Array types show up as "[Lorg/webrtc/Foo;" and inner
# classes as "org/webrtc/Foo$Bar"; the sed below strips the array wrapper so both
# forms compare against the plain names taken from the jar listing.
#
# Constant pool Class entries only, deliberately: a type that appears solely
# inside a method descriptor has no Class entry and is not checked here. That
# is not a real gap for this artifact — a class reachable through the public API
# is always instantiated, cast, or caught somewhere, which forces a Class entry.
find "$WORK/classes" -name '*.class' -print0 \
 | xargs -0 javap -p -verbose 2>/dev/null \
 | grep -oE '= Class +#[0-9]+ +// +\[*L?[A-Za-z0-9_/$]+;?' \
 | sed -E 's/.*\/\/ +//; s/^\[+L?//; s/;$//' \
 | sort -u | grep '^org/webrtc' > "$WORK/refs.txt"

missing="$(comm -23 "$WORK/refs.txt" "$WORK/resolvable.txt")"

if [[ -n "$missing" ]]
then
 echo "FAIL: classes.jar references org/webrtc classes it does not contain:" >&2
 echo "$missing" | sed 's/^/  /' >&2
 failed=1
else
 echo "  ok: no dangling org/webrtc references ($(wc -l < "$WORK/refs.txt") referenced)"
fi

# 2. Native JNI symbols without a Java counterpart.
#
# A JNI symbol is Java_<mangled class>_<mangled method>, and the separator is the
# same '_' that appears inside names, so the symbol cannot be split back into
# class and method reliably. Going the other way is exact: mangle every class
# present in the jar (org/webrtc/Foo_Bar$Baz -> org_webrtc_Foo_1Bar_00024Baz) and
# require each Java_org_webrtc_* symbol to start with one of those prefixes.
sed -e 's/_/_1/g' -e 's/\$/_00024/g' -e 's;/;_;g' "$WORK/resolvable.txt" \
 | sed -e 's/^/Java_/' -e 's/$/_/' | sort -u > "$WORK/mangled.txt"

for so in "$WORK"/aar/jni/*/*.so
do
 [[ -f "$so" ]] || continue
 abi="$(basename "$(dirname "$so")")"

 nm -D --defined-only "$so" 2>/dev/null \
  | grep -oE '\bJava_org_webrtc_[A-Za-z0-9_]+' | sort -u > "$WORK/jni_syms.txt"

 # A symbol resolves if it starts with any mangled class prefix; which prefix
 # does not matter, only that one exists.
 unresolved="$(awk 'NR==FNR { prefix[$0]; next }
                    { for (p in prefix) if (index($0, p) == 1) next
                      print "  " $0 }' \
                 "$WORK/mangled.txt" "$WORK/jni_syms.txt")"

 if [[ -n "$unresolved" ]]
 then
  echo "FAIL: $abi exports JNI symbols whose Java class is absent from classes.jar:" >&2
  echo "$unresolved" >&2
  failed=1
 else
  echo "  ok: $abi JNI symbols all have Java classes ($(wc -l < "$WORK/jni_syms.txt") symbols)"
 fi
done

# 3. package= / <uses-sdk> in the manifest — reported, never fatal.
#
# Consumers who unpack an aar and reuse its manifest as a source manifest hit
# AGP 8's rejection of package=, which is why libwebrtc's manifest is stripped
# of both. But AGP writes package= and <uses-sdk> into every aar it produces
# itself — mediasoup-client-release.aar included — so failing on this would fail
# every normal Android library. Hence a note, not an error.
#
# Comments are stripped first: the libwebrtc manifest explains in a comment why
# those two were removed, and a naive grep matches its own explanation.
if [[ ! -f "$WORK/aar/AndroidManifest.xml" ]]
then
 echo "FAIL: no AndroidManifest.xml inside $(basename "$AAR")" >&2
 failed=1
else
 perl -0777 -pe 's/<!--.*?-->//gs' "$WORK/aar/AndroidManifest.xml" > "$WORK/manifest.xml"

 if grep -qE '(<manifest[^>]*[[:space:]]package=)|(<uses-sdk)' "$WORK/manifest.xml"
 then
  echo "  note: AndroidManifest.xml declares package= / <uses-sdk>;"
  echo "        consumers reusing it as a source manifest must strip them for AGP 8"
 else
  echo "  ok: AndroidManifest.xml has no package= / <uses-sdk>"
 fi
fi

if [[ $failed -ne 0 ]]
then
 echo "check_aar_consistency: FAILED" >&2
 exit 1
fi

echo "check_aar_consistency: OK"
