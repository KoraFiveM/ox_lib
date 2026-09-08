# ox_lib compatibility resource

This resource preserves the FiveM-facing ox_lib 3.39.0 import and API surface
while qblib owns the shared UI implementation. Existing resources can keep:

```lua
shared_script '@ox_lib/init.lua'
```

and continue to use the global `lib` and `cache` APIs or `exports.ox_lib`.

The consumer-local loader, lazy imports, data structures, callbacks, points,
zones, streaming helpers and other non-UI modules are pinned verbatim to
Overextended commit `b8f5a04351b1d427e0e112150d36094e9889ec7b` under the
LGPL-3.0-or-later license. The resource-owned UI exports are a thin bridge to
qblib, avoiding a second NUI page and duplicate focus state.

The pinned player locale and notification preferences remain owned here.
Locale dictionaries reload in each consumer exactly as they do upstream, and
the decoded ox browser labels are bootstrapped into qblib and updated on every
`lib.setLocale` call.

qblib deliberately translates presentation onto its own design system. Any
presentation-only differences are documented by qblib rather than described
as byte-for-byte upstream UI parity; the manifest/import surface, public
exports, return values, ownership, and non-UI modules are the compatibility
contract of this resource.

Start `qblib` before this resource. Any resource importing `@ox_lib/init.lua`
must start after `ox_lib`, matching the original ox_lib load-order contract.
