#!/usr/bin/env bash
set -euo pipefail

case "$RUNNER_OS" in
  Linux|macOS) ;;
  *) echo '::error::setup-nix supports Linux and macOS runners'; exit 1 ;;
esac
case "$CACHE" in
  auto|sticky|hestia|none) ;;
  *) echo '::error::cache must be auto, sticky, hestia or none'; exit 1 ;;
esac
case "$SAVE" in
  true|false) ;;
  *) echo '::error::save must be true or false'; exit 1 ;;
esac
if ! [[ "$GC_THRESHOLD" =~ ^(0|[1-9][0-9]?)$ ]]; then
  echo '::error::sticky-gc-threshold must be an integer from 0 to 99'
  exit 1
fi
while IFS= read -r line; do
  if [[ "$line" =~ ^[[:space:]]*(extra-)?access-tokens[[:space:]]*= ]]; then
    echo '::error::Use github-token instead of putting credentials in extra-conf'
    exit 1
  fi
done <<< "$EXTRA_CONF"
for value in "$STICKY_KEY" "$CACHE_SCOPE" "$INSTALLER_VERSION"; do
  if [[ "$value" == *$'\n'* || "$value" == *$'\r'* ]]; then
    echo '::error::Cache key inputs and installer-version must be single-line values'
    exit 1
  fi
done

sticky_available=false
if [[ "$RUNNER_OS" == Linux && -n "${BLACKSMITH_STICKY_DISK_GRPC_PORT:-}" ]]; then
  sticky_available=true
fi
backend="$CACHE"
if [[ "$backend" == auto ]]; then
  if [[ "$sticky_available" == true ]]; then backend=sticky; else backend=hestia; fi
fi
if [[ "$backend" == sticky && "$sticky_available" != true ]]; then
  echo '::error::sticky requires a Blacksmith Linux runner with sticky disk support'
  exit 1
fi

# Other refs can read the default branch's cache but write only to their own
# scope, which nothing else reads: those writes only consume the quota.
writable=false
if [[ "$SAVE" == true && -n "$DEFAULT_BRANCH" && "$CURRENT_REF" == "refs/heads/$DEFAULT_BRANCH" \
  && "$EVENT_NAME" != pull_request && "$EVENT_NAME" != pull_request_target ]]; then
  writable=true
fi

key=''
if [[ "$backend" == sticky ]]; then
  fingerprint=$(printf '%s\n' "$INSTALLER_VERSION" "$EXTRA_CONF" "$(id -un):$(id -u):$(id -g)" | sha256sum)
  fingerprint=${fingerprint%% *}
  base_key=${STICKY_KEY:-"${REPOSITORY}-nix-${RUNNER_ARCH}-${JOB_ID}-${CACHE_SCOPE}"}
  key="$base_key-nixos-$INSTALLER_VERSION-${fingerprint:0:12}"
fi
{
  printf 'backend=%s\n' "$backend"
  printf 'writable=%s\n' "$writable"
  printf 'sticky-key=%s\n' "$key"
} >> "$GITHUB_OUTPUT"
