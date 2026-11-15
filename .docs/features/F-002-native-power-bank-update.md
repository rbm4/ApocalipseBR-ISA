# Native power-bank update callback

ID F-002. Created 2026-11-15. Status implemented foundation, isolated validation complete, multiplayer validation pending.

## Behavior and ownership

On a dedicated server exposing `IsoPowerBank`, ISA constructs banks as `zombie.apocbr.power.IsoPowerBank`. Construction marks `ApocBRPowerBank=true`. World load, object addition and the sync-repair path resolve ordinary ISA generators through the same conversion helper. Conversion preserves the existing primary battery container, its items and ModData. The server object factory recognizes serialized native generator class ID 22 with base sprite `solarmod_tileset_01_0` and instantiates the subclass before deserialization. The fixed base sprite is part of this reconstruction contract.

Clients receive the native `IsoGenerator` class ID, native save fields and native sync packets. Charge is mapped onto fuel 0..10, which vanilla displays as 0..100 percent. The server subclass bypasses gasoline depletion, engine sound and toxicity writes. Its activation transition updates loaded refrigerator items before changing electricity coverage. It never clears the building-wide toxic flag. Native dirty-electricity refresh remains active.

The server registers `Hook.OnPowerBankUpdate`. ISA subscribes `NativeSimulation.update(generator, nowHours)`. Each loaded native object checks a deadline in Java. The callback advances the individual bank and acknowledges completion through `completeUpdate(processedHour, intervalHours)`. Missing or failed acknowledgement suspends supply, emits one warning until recovery and retries after one game minute. Reentrant update calls are suppressed. Native generator-sync packets cannot assert bank fuel or activation on the server.

Without the server capability, ISA selects its existing simulation path. Single-player continues using that path. Stock clients use the Lua presentation files shipped by this mod.

## Scheduling and persisted state

Native mode omits the old periodic full-bank charge loop and server toxicity OnTick handler. The daily degradation/panel check and existing client sound/UI maintenance still run.

`GlobalModData` key `ApocBRISA_Production` holds ten-game-minute samples `{hour, output}` shared by all banks. Output is the existing per-panel production formula sampled at that boundary, including configured efficiency. Consecutive samples define a piecewise-constant production approximation. It is recorded once per interval regardless of bank count and saved through native GlobalModData persistence.

`ISA_simulationHour` is saved in both the bank global-object fields and physical ModData. A new bank starts at the current game hour. An older record missing this field establishes its baseline on first native update. Historical production predating the recorder cannot be reconstructed.

Unloaded banks consume no per-bank energy callbacks. Loading resumes catch-up using the saved charge/capacity, panel count, cached/current demand and shared production samples. Lookup begins with binary search. Each callback processes at most 128 history segments, clamps storage at each segment and persists its progress. Long catch-up continues on subsequent native updates. Final physical battery percentages, activation and visuals are applied once catch-up reaches current time. `ChargeFreq` selects the normal ten-minute or hourly deadline.

History retention/compaction is pending. Samples currently remain persisted so a long-unloaded bank can consume them. A long catch-up has bounded per-bank batches, but there is no shared server-frame callback budget. Demand and bank configuration are treated as constant during each catch-up request. Precise historical battery-degradation, consumption/configuration changes, aggregate frame budgeting and transactional interaction while catch-up is incomplete need subsequent work.

## Food catch-up boundary

Vanilla 42.22.2 performs food catch-up in `inventory/types/Food.updateAge(boolean)`, beginning with `updateFreezing` and then elapsed-time aging. Generator activation calls `updateFridgeFreezerItems()` before its coverage changes. This foundation preserves that native loaded-food boundary.

Historical off/on interval replay and a scoped food-aging callback remain a separate implementation step. Current production samples and the bank timestamp do not provide a food-facing power-outage timeline. A broad hook invoked for every ordinary food update would add pressure to unrelated food, so its dispatch needs an indexed power-bank relevance check and an explicit handled/result contract. Food catch-up remains vanilla in this phase.

## Sources and validation

Set sandbox `ISA.Debug=true` to enable `[ISA][Debug]` console messages. The default is false. Logs cover system startup/mode, persistent bank registration and coordinates, native object binding, hook subscription, shared production samples, catch-up boundaries/backlog and acknowledged charge/capacity/panel/drain/supply state. Update logs follow simulation deadlines. Existing unconditional object-add chatter and bank creation prints are now gated. English and PTBR sandbox labels are in their JSON translation files.

- `42/media/lua/server/ImmersiveSolarArrays/PowerBank/NativeSimulation.lua` owns the callback and shared production samples.
- `PowerBankSystem_Server.lua` selects the native scheduler and persists `ISA_simulationHour`.
- `PowerBankObject_Server.lua` projects charge into the native generator and reads cached native consumption.
- `shared/ImmersiveSolarArrays/WorldUtilities.lua` and `server/BuildRecipeCode/ISABuildRecipeCode.lua` construct/mark the native bank.
- `tests/test_native_simulation.py` exercises the production Lua module, long catch-up, storage limits, subscription, callback application and retained container identity. The existing loot suite also passes.
- The production Java subclass lifecycle fixture covers deadlines, reentrancy, callback failure/recovery, fuel projection, inbound packet rejection, server-only sprite discrimination and marker restoration.
- Exact target compilation and artifact details are recorded in the linked Java feature guide. No live server/client run or performance measurement has been performed.

Acceptance still needs construction/pickup, save/restart, chunk unload/load, client join, real-generator coexistence, native sync, callback failure, battery transfers and dense-base timing on the actual server/client combination.

See [the Java bridge contract](../../../apocalipsebr-zomboid-patches/42.22.2/docs/features/2026-11-15-power-bank-lua-update.md) and [R-001](../reports/R-001-dependency-removal-and-hotspot-refactor.md).

The subsequent status-range correction, consolidated activation handler and preserved low-skill startup behavior are tracked in [I-002](../issues/I-002-bank-status-and-activation.md).
