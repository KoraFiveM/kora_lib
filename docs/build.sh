#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
stage_dir="${1:-$repo_root/.pages-source}"
stage_dir="$(realpath -m -- "$stage_dir")"

case "$stage_dir" in
    "$repo_root"/.pages-*) ;;
    *)
        echo "Refusing to replace unsafe staging directory: $stage_dir" >&2
        exit 1
        ;;
esac

rm -rf -- "$stage_dir"
mkdir -p "$stage_dir/reference" "$stage_dir/migration"

cp -R "$script_dir/." "$stage_dir/"
rm -f "$stage_dir/build.sh"

copy_reference() {
    local source_path="$1"
    local slug="$2"
    local page_title

    if ! grep -Fq "/reference/$slug/" "$script_dir/_data/navigation.yml"; then
        echo "Reference page '$slug' is missing from docs/_data/navigation.yml" >&2
        exit 1
    fi

    if [[ -e "$stage_dir/reference/$slug.md" ]]; then
        echo "Duplicate reference page slug: $slug" >&2
        exit 1
    fi

    page_title="$(awk '/^# / { sub(/^# /, ""); print; exit }' "$source_path")"
    if [[ -z "$page_title" ]]; then
        echo "Reference page '$source_path' needs a level-one heading" >&2
        exit 1
    fi
    page_title="${page_title//\"/\\\"}"

    {
        printf '%s\n' '---' "title: \"$page_title\"" "permalink: /reference/$slug/" '---'
        sed 's#\](../theme/docs\.md)#]({{ site.baseurl }}/reference/theme/)#g' "$source_path"
    } > "$stage_dir/reference/$slug.md"
}

for source_path in "$repo_root"/modules/*/docs.md; do
    module_name="$(basename "$(dirname "$source_path")")"
    copy_reference "$source_path" "$module_name"
done

for source_path in "$repo_root"/local/*/docs.md; do
    module_name="$(basename "$(dirname "$source_path")")"
    copy_reference "$source_path" "$module_name"
done

mv "$stage_dir/ox_lib-parity.md" "$stage_dir/migration/ox-lib.md"
mv "$stage_dir/ox_lib-contract-3.39.0.md" "$stage_dir/migration/ox-lib-contract.md"

echo "Prepared GitHub Pages source in $stage_dir"
