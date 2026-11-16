# Food catch-up across power-bank outages

Created 2026-11-15. Status source investigation complete, implementation proposed. Target server patch source 42.22.2. The user corrected the reported fridge failure because the placed object was not a fridge. This report concerns historical food simulation.

## Existing processing and ordering

`42.22.2/src/zombie/iso/IsoCell.java` processes server inventory items at approximately five-second real-time intervals. Its `ProcessItems` call precedes `ProcessIsoObject` in the inspected update flow. Therefore a food item can catch up before the loaded power bank receives its first native update. A food integration cannot assume the bank's update callback already prepared its power history.

In the target vanilla `decompiled/zombie/inventory/types/Food.java`, `update()` calls `updateTemperature()` and then, for a server item in a container, `updateAge(false)`. Additional aging calls occur during rotting/replacement processing and queries. A hook belongs at `updateAge(boolean)` before `updateFreezing`, so it covers those callers without another item sweep or an OnTick loop.

Food aging and freezing use separate saved timestamps. Full Food serialization includes age, lastAged, freezingTime, frozen and lastFrozenUpdate. Unloaded food leaves normal processing and later catches up from those values.

## Native rules that the hook must preserve

- Powered freezer contents can freeze when `canBeFrozen` permits it. Native progress advances by 100 percent per four game hours.
- Normal thawing takes 1.5 game hours. A powered fridge doubles that time. Containers hotter than the native ambient baseline accelerate thawing.
- The frozen flag is stateful. Reaching 100 percent sets it true, reaching zero clears it, and intermediate percentages preserve its previous value. A newly freezing item and a thawing item can have equal percentages with different frozen flags.
- `updateAge(boolean)` updates freezing first, then applies aging. Fully frozen state suppresses aging. Refrigeration uses the configured fridge factor and aging uses the configured food-rot speed. Grid-shutoff handling is also present.
- Temperature/heat, eggs, cooking, rotten replacement/removal and client/server item synchronization have their own surrounding behavior. A catch-up callback must return consistent food state without bypassing those surrounding paths accidentally.

Current vanilla catch-up evaluates elapsed time largely using conditions at the update. It does not reconstruct multiple solar outages. Replaying historical intervals needs an explicit policy for freeze/thaw thresholds within intervals, and regression comparisons against native behavior in constant-power cases.

## Missing bank information

`NativeSimulation.advance` currently consumes shared production samples, updates charge with capacity clamps, and saves its final processed hour. It does not emit historical power transitions. `IsoPowerBank.applyPowerState` applies the final present-time activation after a completed batch.

The next bank simulation change must produce persistent supply intervals or transition records. Detect the first zero-energy crossing within each production interval, record subsequent resumption using the current automatic-resume behavior, and distinguish manual shutdown from exhaustion. At a negative constant net rate, exhaustion occurs at interval start plus initial charge divided by the absolute net rate. Zero-production, zero-capacity, backup supply, full storage, configuration edits, manual changes and chunk/restart boundaries need explicit handling.

A shared production history is input to that calculation. It is not itself an appliance power history. Food also needs the supply state immediately before the beginning of its pending interval.

## Proposed server hook contract

1. Java performs a cheap relevance check for a refrigerated world container associated with a power bank. Use the existing indexed powered-object lists during coverage/lifecycle updates to maintain appliance-to-source relationships. Avoid searching squares or all registered banks for every food item.
2. Before food advances, the server ensures the relevant bank's power history covers the requested interval. A pending bounded bank catch-up must not allow vanilla aging to consume that interval with stale supply state. Native reentrancy during generator activation also needs an explicit guard/readiness result.
3. Dispatch one server Lua callback with food state, container identity/type, start/end times, native aging factors and a prepared supply timeline. Cache the prepared timeline for a container's food batch. Multiple contributing banks require combined supply, and vanilla grid/other generator supply must remain accounted for.
4. Lua calculates the result in detached values. Split work at relevant power transitions and freeze/thaw boundaries, preserving the native frozen flag and sandbox multipliers.
5. Java validates and commits a completed result once, including both timestamps. Explicit completion must distinguish handled, deferred, failed and irrelevant cases. `LuaHookManager.TriggerHook` returns whether callbacks were registered, so that boolean cannot serve as a successful simulation result.
6. Irrelevant ordinary food uses vanilla directly. Completed replay must not fall through and age the same interval again. Failure must not partially mutate age or advance a clock. Batches need a bounded operation budget and a documented deferred-food policy.

The callback runs on the owning server thread. No worker receives live Food, container, Lua or world references. A process-wide time change to replay a historical interval would affect unrelated simulation and is outside this design.

## Stock-client synchronization finding

The inspected native `ItemStatsPacket` sends frozen state and heat, among other food fields. Although it declares a `freezingTime` field, the inspected set/write/parse/process paths do not carry food age, partial freezing progress or the saved aging/freezing timestamps.

Consequently, `GameServer.sendItemStats(food)` alone does not establish full replay-state synchronization with stock clients. Full Food serialization carries those values, but any selected native full-item/container synchronization path must be verified for already-present item IDs, object identity, pending transfers and duplicates. A new incompatible packet layout is excluded by the stock-client requirement. Client Lua presentation must not apply the elapsed interval again over a stale internal freezing clock.

Resolve this transport boundary as part of implementing the hook. Do not claim exact server/client historical aging from a successful server calculation alone.

## Validation required for implementation

- Constant powered/unpowered intervals compared against native Food behavior, with multiple fridge-factor and rot-speed settings.
- Fully frozen food that partially thaws, newly freezing food at the same percentage, and intervals crossing zero/100-percent thresholds.
- Exhaustion overnight, resumption after sunrise, manual shutdown, backup supply and overlapping power sources.
- Food processed before a bank's first update, generator-triggered food aging reentrancy, incomplete history batches and callback failures/retries.
- Save/restart, moving food between containers, nested containers, bank removal and actual stock-client food state after synchronization.
- Shared timeline reuse, bounded processing, callback counts, packet bytes and real server timing. No measured performance claim follows from this source investigation.

## Source references

All engine paths are relative to `Z:\git\Github\apocalipsebr-zomboid-patches\42.22.2`.

- `src/zombie/iso/IsoCell.java` around lines 4241-4252, inventory cadence and item/object ordering.
- `decompiled/zombie/inventory/types/Food.java` around lines 367, 718-788, 836-861, 2182-2225, update/age/freezing/frozen-state rules.
- `decompiled/zombie/inventory/types/Food.java` save/load methods, persistent food state.
- `decompiled/zombie/network/packets/ItemStatsPacket.java` set/write/parse/process paths, current wire fields.
- `src/zombie/network/GameServer.java`, `sendItemsInContainer`, existing native container transport to investigate rather than assume as a complete replacement update.
- `src/zombie/apocbr/power/IsoPowerBank.java`, current update acknowledgement and activation ordering.
- Mod `42/media/lua/server/ImmersiveSolarArrays/PowerBank/NativeSimulation.lua`, current bounded charge catch-up.

See [F-002](../features/F-002-native-power-bank-update.md) for the implemented generator foundation. No food-aging hook or historical replay is implemented by this report.

## Subsequent accepted direction

[F-003](../features/F-003-budgeted-energy-and-backup-history.md) implements budgeted bank/backup accounting and a bounded bank-local effective-supply journal. It also records the user's proposed cached power-source association for food: scope hook eligibility to the food's relevant source epochs, share container timeline preparation, and replay outage/restoration and freeze/thaw thresholds rather than solar samples. The association/index, food hook, overlapping-source union and stock-client replay transport remain unimplemented. Cached source lookup alone does not bound per-item replay or justify ignoring power restoration.
