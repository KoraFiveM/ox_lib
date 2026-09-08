#!/usr/bin/env bash
set -euo pipefail

resource_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
lua_bin=${LUA:-lua5.4}

"$resource_dir/test/upstream.sh"
"$lua_bin" "$resource_dir/test/compat.lua" "$resource_dir"
