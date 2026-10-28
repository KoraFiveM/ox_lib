# ox_lib compatibility resource

This resource preserves the FiveM-facing ox_lib 3.39.0 import and API surface
while kora_lib owns the shared UI implementation. Existing resources can keep:

```lua
shared_script '@ox_lib/init.lua'
```

and continue to use the global `lib` and `cache` APIs or `exports.ox_lib`.

The consumer-local loader, lazy imports, data structures, callbacks, points,
zones, streaming helpers and other non-UI modules are pinned verbatim to
Overextended commit `b8f5a04351b1d427e0e112150d36094e9889ec7b` under the
LGPL-3.0-or-later license. The resource-owned UI exports are a thin bridge to
kora_lib, avoiding a second NUI page and duplicate focus state.

The pinned player locale and notification preferences remain owned here.
Locale dictionaries reload in each consumer exactly as they do upstream, and
the decoded ox browser labels are bootstrapped into kora_lib and updated on every
`lib.setLocale` call.

Client state-bag write requests validate their bag, target ID, key, and
replication mode before reaching hook dispatch or FiveM state natives. Invalid
requests return `false`; they do not throw or mutate state.

kora_lib deliberately translates presentation onto its own design system. Any
presentation-only differences are documented by kora_lib rather than described
as byte-for-byte upstream UI parity; the manifest/import surface, public
exports, return values, ownership, and non-UI modules are the compatibility
contract of this resource.

## Install only for a legacy manifest import

This wrapper is optional. Do not add it to a default configuration: start it
only when an installed legacy resource imports `@ox_lib/init.lua`. Start
`kora_lib` before this resource, and start an importing resource after `ox_lib`:

```cfg
ensure kora_lib
ensure ox_lib # only for @ox_lib/... imports
```

## Verify the wrapper

From this resource directory, run `bash test/run.sh`. It verifies the public
compatibility surface without starting `ox_lib` or adding it to a server
configuration.
