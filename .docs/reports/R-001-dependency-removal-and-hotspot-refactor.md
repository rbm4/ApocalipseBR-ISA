# R-001: Dependency removal and hotspot refactor

> Decision update, 2026-11-15: the user confirmed no existing-save ISA state needs preservation and selected native loot registrations instead of fixed world placements. [F-001](../features/F-001-native-loot-distributions.md) implements that approach. The owned queue and migration recommendations below are historical alternatives, not current requirements. Other hotspot refactors remain pending.

Date: **2026-11-15**  
Status: **Investigation complete; implementation proposed**  
Scope: the current `ApocalipseBR-ISA/42` fork and local B42 engine/Lua snapshots. No runtime change, migration, dependency removal or benchmark was performed for this report.

## Recommendation

Remove the external TargetSquareOnLoad requirement by implementing a small **ISA-owned deferred-spawn system using the game's native global-object chunk index**. Preserve pending jobs and initial spawn-roll state on existing saves. Do not replace the dependency with per-square Lua scanning, a world-wide tick loop or forced chunk loading.

Refactor the other hotspots in separate, reviewable changes: authoritative battery reconciliation, command validation, generator/toxicity lifecycle handling, fair bank scheduling, then electricity/network coalescing. Lua remains the first implementation layer. A Java change may be justified for per-source toxicity or a missing authoritative inventory hook; neither is needed just to replace the dependency's queue.

The dependency is already selective. Removing it primarily reduces coupling and gives ISA ownership of its persistence/error policy; it is not by itself a major simulation optimization.

## Evidence and current paths

All module paths below are relative to `ApocalipseBR-ISA/42/media/lua/` unless stated otherwise.

| Concern | Source entry point |
|---|---|
| Deferred spawns, initial flag, room spawns | Former `server/ImmersiveSolarArrays/World/RandomWorldSpawns.lua`, `doRolls` (103), `InitSpawns` (151); removed by F-001 |
| Object creation/load | [`World/MapObjects.lua`](../../ApocalipseBR-ISA/42/media/lua/server/ImmersiveSolarArrays/World/MapObjects.lua), `LoadPowerbank`, `OnNewWithSprite` |
| Bank tick/periodic/inventory behavior | [`PowerBankSystem_Server.lua`](../../ApocalipseBR-ISA/42/media/lua/server/ImmersiveSolarArrays/PowerBank/PowerBankSystem_Server.lua), `onTransferItem` (195), `updatePowerbanks` (254), `preventToxicBuildings` (285) |
| Generator and battery operations | [`PowerBankObject_Server.lua`](../../ApocalipseBR-ISA/42/media/lua/server/ImmersiveSolarArrays/PowerBank/PowerBankObject_Server.lua), `getTotalWhenoff`, `updateDrain`, `updateGenerator`, `loadGenerator`, `checkPanels` |
| Broad transfer wrapper | [`client/ImmersiveSolarArrays/Patches.lua`](../../ApocalipseBR-ISA/42/media/lua/client/ImmersiveSolarArrays/Patches.lua), `ISInventoryTransferAction.perform` |
| Ordinary command channel | [`server/ImmersiveSolarArrays/Commands.lua`](../../ApocalipseBR-ISA/42/media/lua/server/ImmersiveSolarArrays/Commands.lua) |
| Global-object command channel | [`PowerBankSystem_Commands.lua`](../../ApocalipseBR-ISA/42/media/lua/server/ImmersiveSolarArrays/PowerBank/PowerBankSystem_Commands.lua) |
| Client permanent loops | [`PowerBankSystem_Client.lua`](../../ApocalipseBR-ISA/42/media/lua/client/ImmersiveSolarArrays/Powerbank/PowerBankSystem_Client.lua), `mutePowerbanks` (309), `preventToxicBuildings` (352) |

Dependency inspected:

`Z:\SteamLibrary\steamapps\workshop\content\108600\2969455858\mods\TargetSquareOnLoad\42.00\media\lua\server\!_TargetSquare_OnLoad.lua`

Engine root `J`:

`Z:\Downloads\ZomboidDecompiler\ZomboidDecompiler\bin\output\source\zombie`

Vanilla Lua root `L`:

`Z:\SteamLibrary\steamapps\common\ProjectZomboid\media\lua`

Verified native paths:

- `J/globalObjects/SGlobalObjects.java`: `registerSystem` creates/loads a named system; `initSystems` triggers Lua initialization; `chunkLoaded` checks each registered system; `saveInitialStateForClient` serializes registered object coordinates.
- `J/globalObjects/SGlobalObjectSystem.java`: `chunkLoaded` (95) only invokes Lua if that system has targets in the chunk; `getFileName` uses `gos_<system>.bin`; persistence saves configured keys; `getInitialStateForClient` requires an installed Lua callback.
- `J/globalObjects/GlobalObjectLookup.java`: chunk-scoped object lookup. This snapshot uses **8-square chunks**. Avoid importing B41 `/10` coordinate math; native indexing avoids hardcoding either size.
- `L/server/Map/SGlobalObjectSystem.lua`: generic `OnChunkLoaded` removes records without matching physical objects. A deferred-spawn system **must override it**, since its targets intentionally have no object yet.
- `J/iso/objects/IsoGenerator.java`: `update` (162), `load` (431), `addToWorld` (464), `setActivated` (528), `syncIsoObjectReceive` (612), static `updateSurroundingNow` (689).
- `L/shared/TimedActions/ISTransferAction.lua:95`: shared low-level Lua transfer mutates source/destination containers and has explicit server behavior. This is a candidate interception point, not proof that every server mutation passes through it.

Line numbers are navigation hints for the inspected snapshot. Symbols and current source take precedence after edits. Exact deployed Java versions/patches and event ordering still require runtime verification.

## 1. What the dependency currently supplies

ISA has one direct Lua require of `!_TargetSquare_OnLoad`, in `RandomWorldSpawns.lua`. The dependency is also declared in `project.json`, `ApocalipseBR-ISA/42/mod.info` and `ApocalipseBR-ISA/common/mod.info`.

At `OnSGlobalObjectSystemInit`, ISA:

1. Registers its room-discovery handler if random bank spawns are enabled.
2. Gets the dependency instance and installs the `isaWorldSpawn` callback.
3. Checks `savedData.ISA_RandomWorldSpawns_initialised`.
4. On first initialization, examines active map names and overwrite rules, rolls fixed spawn locations using `solarPanelWorldSpawns`, and queues `{command="isaWorldSpawn", sprite=...}` at selected coordinates.
5. Persists the initialization flag even if no coordinate was selected.

The dependency persists `savedData` at system level and `commands` per global object. For a matching chunk load, it resolves each target square and dispatches its commands. Only an exact `true` return retains a command. ISA returns nothing, making its normal jobs one-shot.

Random room spawns, stash/loot injection, panel connections, charge simulation and bank electricity do not need the dependency's API. They must continue working after removal. Keep room registration independent of whether a fixed-spawn queue is enabled.

Current failure behavior is weak: missing squares without `squareCanBeNil`, absent callbacks, and nil/false results discard jobs. Exceptions are not isolated per target. A replacement should specify success, retry and permanent rejection explicitly.

Additional native detail: returning nil from a system's initial-state callback does **not** prevent `SGlobalObjects.saveInitialStateForClient` from adding `_objects` and their coordinates. Both the dependency and a naive new global-object queue can therefore add join-time serialization for pending targets. Do not call the queue completely network-free without inspecting this path. Measure it; a later storage-only ModData design would need a separately proven efficient chunk trigger.

## 2. Proposed ISA-owned queue

Create `server/ImmersiveSolarArrays/World/DeferredSpawnSystem.lua`, using a unique native system name such as `apocbr_isa_worldspawns`. This is a proposal, not a name already present in the runtime.

Keep the interface narrow: initialize schema, enqueue a fixed spawn, process matching chunk records, and record completion/retry. A general arbitrary-command framework is unnecessary for ISA's single use case. Preserve current spawn functions, map filtering, probability and sprite selection initially.

Suggested persistent state:

| Level | Fields / purpose |
|---|---|
| System | `schemaVersion`, `initialRollComplete`, map/roll policy metadata, legacy-migration status |
| Target/job | Stable job ID, coordinates, sprite, pending/retry/completed status or equivalent ledger, bounded attempts and rejection reason |
| Runtime only | Deduplicated ready queue, cursor, loaded references, timing/diagnostic counters |

Use deterministic job identities derived from a stable location ID plus spawn/schema generation; do not collapse two intentional same-coordinate jobs merely because their positions match. Persist primitive/table data only. Register callbacks and saved-key lists before chunk work can run, and make initialization idempotent. Initialize explicitly in one ordered path rather than relying on incidental Lua filename ordering between several events.

On target chunk load, inspect only that chunk's jobs. Small batches can run immediately; if work is deferred to the simulation work budget, re-resolve the square at execution time because the chunk may unload. Never retain stale square objects as persistent job state. Retry transient absence without spinning; use bounded retry/backoff for errors and visible rejection diagnostics. Catch failures per job and return any pooled native lists even on errors.

Check for an existing matching ISA object/job marker before spawning, then update the job state. Preserve markers across object replacement. This reduces replay duplication, but do **not** promise exactly-once durability: world objects and global-object files are separate save state, and a crash can interrupt either side. Define recovery for mismatched markers/ledger and test it. A permanently completed job should not respawn a panel a player legitimately removed later.

Do not force-load chunks. Verify registration after a target chunk is already loaded: native callbacks fire on chunk loads, not automatically for newly enqueued jobs. Handle currently available targets through a bounded startup reconciliation pass or explicit enqueue-ready path.

### Alternatives

| Approach | Assessment |
|---|---|
| ISA-owned native global-object system | Recommended: preserves native chunk targeting; requires explicit persistence/migration and awareness of initial-state serialization |
| Copy the dependency wholesale into ISA | Removes the Workshop requirement but retains generic/shared namespace and behavior; creates collisions and attribution concerns; not the preferred design |
| ModData queue plus `LoadGridsquare` lookup | Could use O(1) key tests, but still crosses into Lua for every loaded square; weaker than the existing selective architecture |
| Poll all pending coordinates on every tick | Reject: adds the exact kind of global hot loop being removed elsewhere |
| Remove fixed map spawns entirely | A deliberate gameplay change, not equivalent dependency removal |

The dependency README credits Poltergeist and says not to re-upload the mod, while allowing reuse for different tasks with credit. Prefer an ISA-specific implementation against the native API; retain appropriate attribution for any reused material. Do not assume the permission to fork ISA automatically covers repackaging every dependency.

## 3. Existing-save migration is the critical requirement

Old state lives in **`gos_TargetSquareOnLoad.bin`**, not in bank `gos_isa_powerbank.bin` or ordinary bank ModData. If we simply remove the require and rerun map rolls in a fresh queue, the old initialization flag is lost and previously processed locations may spawn again. Simply suppressing rerolls loses still-pending jobs.

Preferred rollout:

1. Introduce the owned queue while the legacy dependency is still available. Initialize migration before any legacy/new ISA spawn can execute, and arrange a single owner for `isaWorldSpawn` during the transition.
2. Enumerate legacy global objects and copy **only `isaWorldSpawn` jobs** into stable owned jobs. Copy the initialized flag even when zero jobs remain; do not infer a fresh world from an empty queue.
3. Retain unrelated commands and all unrelated savedData. The legacy system may serve other mods. Never delete/reset its whole file or hijack its system name.
4. Use repeatable deduplication and a migration ledger. Copy-before-remove is preferable to remove-before-copy, but separate-file saves still create crash windows. Test restart/crash replay and persist checkpoints deliberately.
5. Once the bridge can recover saves that skipped the transition release, remove declarations from all three metadata locations and replace the Lua require. Update README/Workshop requirements too. Removing ISA's requirement does not mean other server mods no longer require the Workshop dependency.

For a direct upgrade from an old save without the dependency, implement and test a **legacy reader/compatibility path**. Native `SGlobalObjects.registerSystem("TargetSquareOnLoad")` loads its file, but also registers the system globally: it is not a read-only reader. Without callbacks, later chunk processing or initial-client-state generation can throw. Save-key configuration also matters because the engine resaves all registered systems. Do not casually register it as a temporary reader and leave it half initialized.

Choose one explicit supported policy before implementation: a fully compatible bridge, a bounded offline migration tool, or requiring the transition release for existing saves. Native exposure and deployed-save behavior need verification before claiming the first option works. Fresh saves need no legacy import. Do not combine “new queue absent” and “no old save exists” into one inferred state.

## 4. Toxicity and generator lifecycle

Confirmed: ordinary `IsoGenerator.update` sets building toxicity on hourly advancement; `setActivated` sets it when the activation state changes. `addToWorld` adds generators to normal engine processing. Loading restores state and marks surrounding electricity dirty. The inspected sync receiver directly updates activation/electricity/sound; it does **not** itself call `setToxic` in that method. Audit these distinct paths rather than describing them as identical.

ISA currently compensates by removing bank generators from ordinary processing, muting clients, and clearing the entire building's toxicity in permanent server/client bank loops and several bank operations. That can conceal an ordinary combustion generator's hazard in the same building. Reducing polling frequency would retain that correctness problem and introduce a possible toxicity window.

Lua-first investigation: maintain loaded/active bank state, remove bank engine processing at proven creation/load lifecycle boundaries, and centralize ISA activation/refresh handling. `OnElectricityChanged` is broad and does not identify a particular generator, so replacing one global scan with another event-wide registry scan is not automatically an improvement. Verify same-tick activation ordering, client sound paths, real-generator coexistence, and re-registration after streaming/restart.

Also remove activation toggling as a hidden demand query: `getTotalWhenoff` temporarily switches a generator on/off, which invokes electricity refresh, sound, toxicity writes and events. Demand estimation must not silently change world state.

If Lua cannot guarantee correct behavior, a narrow Java capability distinguishing non-combustion generators is justified. Guard toxicity contributions at their source and preserve/recompute real-generator building hazards. Do not merely replace solar writes with `setToxic(false)`. Review flag persistence/identity, networking, load and sound behavior against the versioned patch project. Solar still needs native power coverage; the deprecated square electricity setter is not a replacement provider API.

Acceptance: solar alone never poisons occupants; adding solar never suppresses a real generator's hazard; no full-bank per-tick safety/sound sweep remains; charge/activation/load/sync transitions remain correct.

## 5. Inventory accounting and command authority

The existing transfer command does not move the item. It adjusts cached bank battery count, capacity and charge from client-supplied serialized item properties, then refreshes generator/sprite/ModData. Its broad `perform` wrapper adds traffic to unrelated transfers. ItemContainer fields are unsupported by the inspected table serializer and can cause client errors; InventoryItems are serialized copies rather than authoritative identity.

Investigate a server-only wrapper around the shared `ISTransferAction.transferItem` path, comparing actual relevant source/destination membership before/after and marking only affected banks dirty after a committed mutation. Preserve original return behavior and distinguish early no-op returns. This path is **not yet established as comprehensive**: network packets, scripted/admin changes and direct container calls may bypass it. No suitable universal committed-container Lua event was verified in this investigation.

A Lua fallback is a bounded periodic recount of loaded bank containers plus dirty reconciliation for known changes. This eliminates the broad client command even if a complete mutation event is unavailable, at the cost of a documented maximum detection delay. Validate that delay for removed batteries and zero-capacity shutdown. Java post-commit notification is a fallback if stronger guarantees cannot be achieved in Lua.

Reconciliation must preserve energy: settle the bank to the transaction time where possible, use authoritative battery condition/charge, and reconcile before overwriting item charge fractions. Uniformly setting every battery to cached bank charge before accounting for a new battery can destroy or create energy. Batching and concurrent moves need stable ordering. Recounts should be idempotent; duplicate notifications must not increment counts twice.

Validate both command channels independently: argument types, finite/clamped values, real objects and item ownership, range, skill/permission, bounded lists and server cooldowns. Repair/debug commands need appropriate restrictions. Align ordinary `ISA` handlers with global-object handlers and B42 server-side timed-action completion; avoid adding a second mutation when completion already did the work.

Acceptance: no ISA transfer packet for unrelated looting; no client-supplied charge deltas trusted; correct accounting for successful/failed/batch/concurrent transfers, scripted changes, restart and load.

## 6. Fair simulation, electricity and synchronization

Use a bounded round-robin **bank** scheduler, not one energy job per panel. Production already uses stored panel count; per-panel scheduling generally expands B bank jobs into P panel jobs. Use panel jobs for incremental membership/outdoor validation or future panel-specific behavior, aggregating results before bank integration.

Keep separate cheap energy integration, dirty inventory reconciliation, expensive demand/electricity refresh, visual updates and network flush. Maintain persisted records independently of loaded/active references. Track elapsed **game hours** per bank and integrate `(production - demand) × elapsedHours`; retain current units, capacity clamps and a documented weather-history/catch-up policy. Bound catch-up work and queue latency; time-budget checks between banks cannot preempt a single expensive native call.

Avoid double-counting the next interval: current `updatePowerbanks` applies `dCharge` and `updateGenerator(dCharge)` then considers `self.charge + dCharge` again. Define activation from settled energy and explicit transition policy rather than accidentally projecting charge twice.

Coalesce repeated `setSurroundingElectricity` calls and avoid static `updateSurroundingNow` per bank. That static method walks the global generator list and refreshes dirty entries; it does not recalculate every entry. Deduplicate dirty refreshes without breaking appliance changes and freezer timers. The optional custom Lua demand scan walks a large radius/height volume and clamps Z to old 0..8 assumptions; retain native demand mode initially and investigate pure demand calculation separately.

Suppress unchanged ModData/generator transmissions. Charge-only changes should not resend complete panel-coordinate lists unnecessarily. Preserve join/load recovery, semantic full/empty transitions and backup switching. Daily battery degradation/panel validation must also be incremental or budgeted; coordinate sets can remove repeated quadratic membership searches. Gate object-add debug prints and retain existing two-second debug-area caching.

No forced loading is needed for stored charge arithmetic. Unloaded demand is a policy choice using cached or virtual state, not a reason to stream the world. Async workers are appropriate only for measured pure computation over immutable snapshots; apply results on the game thread with identity/version checks. Lua/world objects must not be accessed unsafely off-thread.

## 7. Implementation sequence and validation

| Stage | Deliverable | Evidence required |
|---|---|---|
| 1 | Runtime baseline and aggregate instrumentation | Current server/client build, bank/transfer behavior, tick and packet baseline |
| 2 | Owned spawn queue and migration bridge | Fresh/legacy saves, pending/empty legacy queues, unrelated jobs, retry/restart/replay and already-loaded targets |
| 3 | Authoritative inventory reconciliation and command controls | Failed/batch/concurrent/direct mutations, energy conservation, no unrelated-transfer ISA traffic |
| 4 | Generator lifecycle/toxicity fix | Mixed real/solar buildings, client sound, activation, resync, stream/restart; Java only if Lua capability gap is demonstrated |
| 5 | Budgeted bank simulation and demand refresh | Fairness, game-time changes, low/full storage, backup transitions, loaded/unloaded consistency |
| 6 | Network/panel/daily-work optimization | Reduced bytes/refreshes and bounded daily/load spikes without stale state |

Dependency removal and the simulation refactor can be delivered independently. Do not hold migration correctness hostage to a simultaneous energy-model rewrite.

Test zero banks, realistic totals, dense overlapping bases, dispersed/unloaded/off banks, many ordinary generators, and ordinary looting far from ISA objects. Measure callback counts/time, full-tick p95/p99/max, queue age/backlog, native refresh count, command/ModData bytes, log volume, GC and client frame time. Aggregate diagnostics rather than logging each tick.

Open decisions: supported legacy-upgrade policy; tolerable inventory reconciliation delay; offline-demand/weather integration; exact Lua lifecycle-hook coverage; need for narrow toxicity or inventory Java capabilities. Source inspection establishes feasible designs and risks, not safe player limits or measured performance gains.
