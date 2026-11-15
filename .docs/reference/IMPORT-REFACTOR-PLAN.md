# Refactor requirements

> Historical import-era plan, retained for provenance. Paths referring to `42.1/` describe the original import; the current fork uses `42/`. Current dependency-removal and hotspot recommendations are in [R-001](../reports/R-001-dependency-removal-and-hotspot-refactor.md), indexed in [INDEX.md](../INDEX.md).

## Baseline

Imported on 2026-11-15 from:

`Z:\SteamLibrary\steamapps\workshop\content\108600\3670551703\mods\immersive solar`

Copy `42.1/` and `common/` into the scaffold mod directory. The B42 Lua source files, translations, scripts and supporting assets are preserved. Only mod identity metadata is changed within the imported version tree. Do not start by rewriting the ISA runtime or renaming persistent identifiers. Establish a working multiplayer baseline first.

The first implementation phase should remain in Lua where the existing APIs provide adequate authority and lifecycle hooks. Java changes belong in the separate versioned Java-patches project if investigation establishes a missing engine capability; no patch is implemented or required by this import.

## Electricity and toxicity

The local Java source does not support the assumption that all electricity must come from a physical generator: vanilla grid power exists. For localized post-shutoff supply, however, ISA currently uses a real `IsoGenerator` and the native generator-position electricity indexes. `IsoGridSquare.haveElectricity()` checks its chunk's generator power coverage; `setHaveElectricity(boolean)` is deprecated and only updates light switches in the inspected source. It is not a usable replacement power-provider API.

Relevant local engine root:

`Z:\Downloads\ZomboidDecompiler\ZomboidDecompiler\bin\output\source\zombie`

- `iso/objects/IsoGenerator.java:162`: ordinary update handles sound/fuel/condition; hourly advancement marks an indoor building toxic when active.
- `iso/objects/IsoGenerator.java:528`: activation changes mark the building toxic and refresh electricity.
- `iso/objects/IsoGenerator.java:689`: `updateSurroundingNow` is static and traverses the global generator list.
- `iso/IsoGridSquare.java:9983`: generator coverage query and deprecated square setter.

There is no dedicated per-generator non-toxic setting in these inspected paths. ISA clears the **building-wide** flag and removes its bank generator from ordinary engine processing. Its server tick loop visits every bank; the client also runs toxicity and sound loops.

First investigate whether Lua can reliably remove bank generators from ordinary processing at creation/load/sync boundaries and handle activation transitions with targeted callbacks. Inspect all re-registration paths, including incoming generator synchronization, chunk load, restart and client lifecycle. A simple slower timer still permits toxicity windows; blindly clearing the building still hides an ordinary combustion generator in that building. Both outcomes are unacceptable.

If Lua cannot prevent those engine writes, the narrow Java fallback is to identify a non-combustion power source and exclude that source from generator toxicity writes, preserving the normal building hazard calculation for real generators. Also review sound, fuel/condition, sync and load behavior. Merely changing one call to `setToxic(false)` would preserve the mixed-building bug. Exact patches must be designed against the deployed game version, not assumed from this decompilation.

## Scheduling: process energy per bank

Use a server work queue with a bounded bank count/time budget per tick, round-robin fairness, and elapsed-game-time integration. Separate persisted bank records from the loaded/active bank set. Avoid world-wide loaded-object searches on each tick; maintain loaded state through proven lifecycle hooks. Handle removal while queued and catch-up without unbounded work after restart/time acceleration.

Per-panel jobs are not an automatic optimization: routine output already uses `npanels`, and each bank owns storage, demand and generator state. If P panels feed B banks, scheduling every panel changes an approximately B-sized energy job into P jobs, adds scheduling overhead, and risks repeatedly clamping the same bank. Compute shared weather/daylight input once per simulation slice and aggregate panel contribution per bank. Use panel jobs only for bounded link/outdoor validation or future panel-specific shading/damage, with contributions accumulated before bank integration.

Throttle expensive appliance/electricity recalculation separately from cheap charge integration. Coalesce repeated `setSurroundingElectricity`, avoid static global-generator refresh per bank, and transmit state when it changes. Handle exact empty/full transitions, backup switching, cached unloaded consumption, day rollover, and production/demand units correctly. If slices cross weather changes, use a documented integration policy rather than assuming present weather describes the whole elapsed interval.

## What the inventory command intends to do

`client/ImmersiveSolarArrays/Patches.lua` wraps `ISInventoryTransferAction.perform` and sends ordinary `ISA/TransferAction`. It sends item data and source/destination coordinates, even for unrelated inventory operations. `server/ImmersiveSolarArrays/Commands.lua` resolves potential bank parents and calls `PowerBankSystem_Server:onTransferItem`.

For an ISA battery, `onTransferItem` derives effective capacity from the item's configured capacity and condition, derives charge from its remaining-use fraction, then increments/decrements the bank's cached battery count, charge and capacity. It updates generator state, overlays and bank ModData. Thus the command keeps cached bank accounting aligned with battery insertion/removal; it does not implement the actual authoritative inventory move.

Removing the command without replacement would leave cached bank accounting stale. Replace it with server-side reconciliation after a committed relevant container change, using authoritative server inventory state. Prefer a proven server transfer/container hook; a dirty-bank queue plus bounded recount is another option if all relevant mutations can mark a bank dirty. Include scripted/admin moves and restart/load reconciliation, not just normal player timed actions. Inspect Java transfer completion before choosing the interception point. Client `OnContainerUpdate` alone is not proof of a committed server transfer.

Local vanilla `ISInventoryTransferAction:transferItem` delegates the move to `ISTransferAction:transferItem`. A client `perform` wrapper is not a comprehensive server transaction hook. Item serialization also produces a network copy rather than authoritative inventory identity; ItemContainer payloads are unsupported by the table serializer and can produce client errors. Eliminate the extra broad client command flow after authoritative replacement is working.

## Commands, network and persistence

- Inventory ownership, distance, skills/permissions, input types and finite numbers must be checked on the server. Bound list sizes and rate-limit expensive repair/sync/update commands. Make duplicate requests safe.
- Consolidate intentional ordinary `ISA` and global-object `isa_powerbank` routing. Some timed-action client command names have no matching ordinary handler; B42 server `complete` also mutates state. Verify actual execution and avoid double mutation.
- Keep stable persistence fields for the first refactor. Introduce a schema version and explicit migration if the data model changes.
- Replace unconditional whole-bank ModData sync, which includes panel lists, with change detection/appropriately scoped messages. Preserve initial join and chunk-load state recovery.
- Fix stale panel-link cleanup, avoid quadratic daily membership work, and gate broad object-add debug logging.
- Keep TargetSquareOnLoad for deferred fixed-coordinate spawns initially; it is already chunk-indexed and does not solve simulation work.

## Java workers and unloaded world

Do not force-load the world just to update charge. Integrate persisted bank state without a square; reconcile the physical generator when its chunk becomes available. Consumption in unloaded areas needs an explicit cached/offline policy.

Do not access live squares, generators, inventories, Kahlua state or Lua callbacks from an arbitrary async worker. If Java computation is useful later, pass immutable snapshots to workers and apply bounded results on the authoritative game thread with identity/version checks. A server main-thread budgeted queue is the initial design; a worker only helps a measured pure-computation bottleneck. IO or off-thread work does not make unsafe world mutation safe.

## Validation before deployment

1. Load this import alone with its dependency on the target B42 server/client. Validate recipes, models, textures, translations, bank construction, linking, charge and backup power.
2. Validate battery insertion/removal including batch transfers, failures, duplicate requests, multiple clients, scripts/admin actions, save/restart and chunk unload/reload.
3. Test an indoor bank alone and sharing a building with a real active generator. Solar must not poison occupants; solar must not erase the real generator's hazard. Include client resync and power/charge transitions.
4. Verify fair energy integration and backup behavior under throttled round-robin scheduling, fast-forward/time changes, full/empty storage, many off/unloaded banks and large panel counts.
5. Compare tick p95/p99/max, handler counts/time, native electricity refreshes, packet bytes/rate, logs, GC and client frame time at realistic bank counts. Include ordinary looting far from banks.

Build/file-integrity checks establish packaging only. They do not establish multiplayer compatibility, live performance, safe existing-save migration or completed refactoring.
