#!/usr/bin/env bash
set -euo pipefail

resource_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
expected=$(<"$resource_dir/test/upstream.sha256")

actual=$(
    cd "$resource_dir"
    find init.lua imports modules locales -type f -print0 \
        | sort -z \
        | xargs -0 sha256sum \
        | sha256sum \
        | cut -d ' ' -f 1
)

if [[ "$actual" != "$expected" ]]; then
    echo "Vendored ox_lib 3.39.0 files differ from b8f5a043." >&2
    echo "Expected: $expected" >&2
    echo "Actual:   $actual" >&2
    exit 1
fi

count=$(find "$resource_dir/init.lua" "$resource_dir/imports" "$resource_dir/modules" "$resource_dir/locales" -type f | wc -l)

if [[ "$count" -ne 106 ]]; then
    echo "Expected 106 pinned upstream files, found $count." >&2
    exit 1
fi

manifest="$resource_dir/fxmanifest.lua"
for entry in \
    "use_experimental_fxv2_oal 'yes'" \
    "version '3.39.0'" \
    "'qblib'" \
    "'init.lua'" \
    "'imports/**/client.lua'" \
    "'imports/**/shared.lua'" \
    "'locales/*.json'" \
    "'modules/**/init.lua'" \
    "'resource/progressProps/client.lua'" \
    "'resource/locale/client.lua'" \
    "'resource/locale/server.lua'"
do
    if ! grep -Fq "$entry" "$manifest"; then
        echo "fxmanifest.lua does not expose required entry $entry." >&2
        exit 1
    fi
done

actual_exports=$(mktemp)
trap 'rm -f "$actual_exports"' EXIT
grep -RhoE 'function lib\.[A-Za-z_]+' "$resource_dir/resource" --include='*.lua' \
    | sed 's/function lib\.//' \
    | sort -u > "$actual_exports"

if ! diff -u "$resource_dir/test/exports.txt" "$actual_exports"; then
    echo "The public ox_lib export inventory changed." >&2
    exit 1
fi

echo "ok - 106 upstream files and 50 resource exports match ox_lib 3.39.0 (b8f5a043)"
