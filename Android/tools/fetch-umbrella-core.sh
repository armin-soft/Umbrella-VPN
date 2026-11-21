#!/usr/bin/env bash
# Download and verify the upstream Android engine used by Windows 1.0.0.
# Requires gh authentication and sha256sum. The resulting AAR is a build input,
# not a release artifact; preserve upstream attribution in application notices.
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
gh release download v5.9.11 --repo hiddify/hiddify-core \
  --pattern hiddify-lib-android.tar.gz --dir "$tmp"
echo "853e897ee2dcbde30801314eb30346e0a4fc61c38f6b4fc4ee901a18fabec3a9  $tmp/hiddify-lib-android.tar.gz" | sha256sum --check
# Read only the verified, expected archive member. Do not extract arbitrary paths.
mkdir -p android/app/libs
tar -xOzf "$tmp/hiddify-lib-android.tar.gz" ./hiddify-core.aar > "$tmp/umbrella-core.aar"
test -s "$tmp/umbrella-core.aar"
mv "$tmp/umbrella-core.aar" android/app/libs/umbrella-core.aar
