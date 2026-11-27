#!/usr/bin/env bash
set -euo pipefail

# nix-quick-install-action also enables accept-flake-config, which would let a
# flake's nixConfig change substituters. Replace its file with the defaults the
# NixOS installer writes on Linux, so both platforms evaluate alike.
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/nix"
mkdir -p "$config_dir"
{
  echo 'extra-experimental-features = nix-command flakes'
  echo 'always-allow-substitutes = true'
  echo 'max-jobs = auto'
  echo 'extra-nix-path = nixpkgs=flake:nixpkgs'
  # The installer renames experimental-features so extra-conf adds features
  # instead of dropping nix-command and flakes.
  printf '%s\n' "$EXTRA_CONF" \
    | sed -E 's/^([[:space:]]*)experimental-features([[:space:]]*=)/\1extra-experimental-features\2/'
} > "$config_dir/nix.conf"
