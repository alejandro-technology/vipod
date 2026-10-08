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
