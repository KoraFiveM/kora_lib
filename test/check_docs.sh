#!/usr/bin/env bash
# Builds the GitHub Pages source into a scratch dir and checks every module docs.md
# became a reference page that the API index links to.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
stage="$root/.pages-test"
trap 'rm -rf -- "$stage"' EXIT

bash "$root/docs/build.sh" "$stage" >/dev/null

fail=0
for source_path in "$root"/modules/*/docs.md "$root"/local/*/docs.md; do
    slug="$(basename "$(dirname "$source_path")")"
    if [[ ! -s "$stage/reference/$slug.md" ]]; then
        echo "missing generated reference page: $slug" >&2
        fail=1
    fi
    if ! grep -Fq "/reference/$slug/" "$root/docs/reference.md"; then
        echo "API index (docs/reference.md) does not link $slug" >&2
        fail=1
    fi
done

[[ "$fail" == 0 ]] && echo "docs: all module reference pages generated and indexed"
exit "$fail"
