#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
RUNTIME="$ROOT/vendor/youtube-runtime"
ARCHIVE="$RUNTIME/Python-3.14-iOS-support.b11.tar.gz"
FRAMEWORK="$RUNTIME/Python.xcframework"
URL="https://github.com/beeware/Python-Apple-support/releases/download/3.14-b11/Python-3.14-iOS-support.b11.tar.gz"
SHA256="b591f3301bd22a4f423c49c746cac9e55558b909fd14d6eb8327ccc62234ab7b"

mkdir -p "$RUNTIME"
if [ ! -f "$FRAMEWORK/Info.plist" ]; then
    curl --fail --location --retry 3 "$URL" --output "$ARCHIVE"
    printf '%s  %s\n' "$SHA256" "$ARCHIVE" | shasum --check --status || {
        printf '%s\n' "Python support archive checksum mismatch" >&2
        exit 1
    }
    tar -xzf "$ARCHIVE" -C "$RUNTIME" Python.xcframework
fi

# Workaround for beeware/Python-Apple-support 3.14-b11 bug: install_stdlib in
# build/utils.sh builds a path from the unquoted $ARCHS list, producing a
# nonexistent "lib-arm64 x86_64" directory on multi-arch (generic/CI) builds.
# Copy each architecture's lib-<arch> folder instead.
UTILS="$FRAMEWORK/build/utils.sh"
if [ -f "$UTILS" ] && grep -qF 'lib-$ARCHS/' "$UTILS"; then
    awk 'index($0, "lib-$ARCHS/") {
            line = $0
            sub(/lib-\$ARCHS\//, "lib-$LIB_ARCH/", line)
            print "        for LIB_ARCH in $ARCHS; do"
            print line
            print "        done"
            next
        }
        { print }
    ' "$UTILS" > "$UTILS.tmp"
    mv "$UTILS.tmp" "$UTILS"
fi

rm -rf "$RUNTIME/app"
mkdir -p "$RUNTIME/app"
WHEELS="$RUNTIME/wheels"
rm -rf "$WHEELS"
mkdir -p "$WHEELS"
python3 -m pip download --index-url https://pypi.org/simple --disable-pip-version-check --only-binary=:all: \
    --python-version 3.14 --implementation cp --abi none --platform any --dest "$WHEELS" \
    'yt-dlp==2026.8.19' \
    'yt-dlp-ejs==0.8.0' \
    'yt-dlp-apple-webkit-jsi==0.1.1' \
    'certifi==2026.7.22'

cd "$ROOT"
shasum -a 256 --check scripts/youtube-runtime-wheels.sha256

rm -rf "$RUNTIME/app"
mkdir -p "$RUNTIME/app"
for wheel in "$WHEELS"/*.whl; do
    unzip -oq "$wheel" -d "$RUNTIME/app"
done
mkdir -p "$RUNTIME/app/vipod_youtube"
cp "$ROOT/vipod/Features/YouTube/Infrastructure/vipod_youtube.py" "$RUNTIME/app/vipod_youtube/__init__.py"
printf '%s\n' "Runtime prepared at $RUNTIME"
