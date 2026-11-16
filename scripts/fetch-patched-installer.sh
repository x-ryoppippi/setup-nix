#!/usr/bin/env bash
set -euo pipefail

# Temporary: NixOS/nix-installer has no way to skip the Time Machine exclusions
# (https://github.com/NixOS/nix-installer/issues/264), which cost about 22s per
# macOS job. Drop this script once a release ships the option (PR #265).
url=https://github.com/ryoppippi/nix-installer/releases/download/fork-v2.35.4-no-tm.1/nix-installer-aarch64-darwin
sha256=1950b62ef3d851a25f68bc1ee0da41354f51cdaad34bc2f680e4508cc6631b00

dir="$RUNNER_TEMP/nix-installer-patched"
mkdir -p "$dir"
curl --fail --silent --show-error --location --retry 3 --output "$dir/nix-installer-aarch64-darwin" "$url"
echo "$sha256  $dir/nix-installer-aarch64-darwin" | shasum -a 256 --check --status
echo "path=$dir" >> "$GITHUB_OUTPUT"
