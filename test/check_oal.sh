#!/usr/bin/env bash
# Conservative source guard for the current OAL allowlist. This intentionally
# catches the common unsafe pattern; it complements, rather than replaces,
# in-game testing of native signatures.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
for resource in kora_utils kora_hud kora_loading; do
    manifest="$root/$resource/fxmanifest.lua"
    rg -q "use_experimental_fxv2_oal 'yes'" "$manifest"
done

# Passing GetEntityCoords directly into a native relies on legacy vector
# unpacking and is forbidden in an OAL-enabled resource.
if rg -n -U '[A-Z][A-Za-z0-9_]*\([^\n]*GetEntityCoords\([^\n]*\)' \
    "$root/kora_utils" "$root/kora_hud" "$root/kora_loading" --glob '*.lua'; then
    echo 'unsafe direct GetEntityCoords native argument in OAL allowlist' >&2
    exit 1
fi

echo 'OAL static audit passed'
