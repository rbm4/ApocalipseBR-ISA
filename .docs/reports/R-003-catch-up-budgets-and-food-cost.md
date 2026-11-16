# Catch-up budgets, backup transitions and food replay cost

Created 2026-11-15. Status source audit and synthetic operation-count check complete; proposed changes are not implemented.

Subsequent implementation on 2026-11-15: [F-003](../features/F-003-budgeted-energy-and-backup-history.md) implements the four energy priorities and is authoritative for current behavior. This report preserves the pre-change audit; food replay remains proposed and live timing validation remains pending.

## Current guarantees and gaps

`NativeSimulation.advance` binary-searches the shared production history and visits at most 128 segments per invocation. For S samples and K pending segments, lookup is O(log S), a batch is O(log S + min(K,128)), and completing catch-up still visits O(K) segments. The number of samples alone does not penalize a current bank with a linear scan.

There is no shared server-frame allowance. Every due loaded `IsoPowerBank.update` can dispatch its Lua callback in the same frame. `completeUpdate` sets its next deadline from the processed historical hour; sufficiently backlogged banks can therefore remain due on consecutive native updates. A per-bank batch bound does not bound aggregate server work or guarantee completion latency. The native dirty-electricity refresh before dispatch and finalization are outside the 128-segment bound.

The recorder appends a sample every ten game minutes even when output is unchanged. At that cadence, 100,000 samples span approximately 694 game days. History has no retention/compaction policy, so total memory and GlobalModData persistence work grow. It is shared history, not a separate climate log per bank.

An isolated Lua 5.1 probe invoked the production `NativeSimulation.update` with 100,000 regularly spaced samples and mocked world objects. Completion required 782 callbacks, called `saveData(true)` 782 times, and ran physical battery finalization and backup handling once each at completion. The real save method transmits ModData. These are operation counts, not packet counts/bytes, live-server timings or a Kahlua benchmark.

Other work remains outside the segment count: `updateDrain` can use `solarscan` depending on sandbox DrainCalc, final `updateBatteries` iterates container items, activation invokes native refrigerator processing and coverage rebuilding, and backup generator `update()` can perform its own native catch-up. Thus 128 does not bound the entire callback's cost independently of world contents.

## Backup and failure-protection correctness

`NativeSimulation.update` determines drain once before advancing. `PowerBank.shouldDrain` uses cached `conGenerator.ison` to suppress battery drain. After all history is processed, `updateConGenerator` resolves a loaded backup square, calls its native update and applies existing failsafe controls, guarded to run at most once per game hour. An unloaded backup cannot be resolved by this method.

The existing functions remain connected, but that does not constitute historical failover simulation. Fuel exhaustion, restart thresholds, manual changes and effective supply-source transitions are not replayed during historical segments. Applying one cached backup state across a long interval can give incorrect battery accounting. Food replay cannot safely infer an accurate historical supply timeline from it.

## Recommended order

1. Add an aggregate fair scheduler for due loaded banks with a total work quota and measured elapsed-time guard, preserving resumable progress. A time guard can stop between bounded operations; it cannot preempt an already-running native world scan. Reserve normal-update service so long catch-up cannot starve current banks. Do not drain the queue synchronously in UI or inventory handlers; dependent actions need explicit pending behavior.
2. Separate simulation checkpoints from client presentation. Persist safe progress without broadcasting every intermediate batch; coalesce final/meaningful state updates. Bound finalization, coverage refresh and backup work as well as arithmetic. Measure queue age, aggregate segments, callback/finalization duration and network volume under dense-base load.
3. Represent battery, backup and manual/failsafe control as one chronological state machine. Split at production boundaries, storage thresholds and modeled source transitions. Model backup consumption only if sufficient historical load/fuel inputs are available; otherwise record the approximation explicitly. Do not call live native generator update once per historical segment or replay physical activation for every old transition. Commit the present physical state once.
4. Establish bounded history storage and a documented old-history policy. Identical adjacent production intervals can be merged exactly. More aggressive summaries/checkpoints require proof or explicit approximation: total net energy alone cannot preserve battery clipping, exhaustion times or failover hysteresis. An indefinitely unloaded bank needs preserved usable history, an exact sufficient summary, or an accepted loss of historical accuracy.
5. Keep vanilla food behavior until that supply model and scheduler are measured and stable. Add historical food integration only if its gameplay benefit justifies the additional persistence, processing and stock-client synchronization work described in R-002.

## Food cost and a reasonable scope

Loaded bank activation already calls native `updateFridgeFreezerItems` before changing coverage. That helper visits loaded squares in generator range and foods in fridge/freezer containers. There is no custom food hook, and no new global food sweep is necessary to preserve this existing behavior. Frequent physical activation toggles could themselves make this native path expensive.

A future narrow hook should use native food processing, an indexed container-to-power-source association and a cached effective supply timeline shared by the container. It must not search every bank or solar sample per item, force-load food, or physically replay old generator transitions. Effective supply is the union of relevant grid/generator/bank sources, not each bank's activation in isolation.

Sharing timeline preparation removes repeated bank simulation, but does not eliminate per-food work. F foods traversing T supply transitions can still require O(F*T) work; freeze/thaw thresholds and different starting food states prevent assuming one result fits every item. A transition history can itself be arbitrarily long. Strict latency bounds therefore require resumable per-food replay plus a global budget, and a defined policy for food access/transfers while pending. A fast Java relevance check should avoid dispatching Lua for unrelated food.

Recommendation: prioritize reliable bank/failover accounting and predictable scheduling. Preserve vanilla loaded-food lifecycle behavior now; defer exact long-unloaded food history. If later implemented, make historical replay a separately measured feature with a defined accuracy horizon or explicit deferred-work policy. Async workers do not solve unbounded total work and must never receive live Lua/world/item objects.

## Evidence

- Mod `42/media/lua/server/ImmersiveSolarArrays/PowerBank/NativeSimulation.lua`: history recording, binary search, batch cap, finalization and transmitting save.
- Mod `PowerBankObject_Server.lua`: `shouldDrain`, `updateDrain`, `updateBatteries`, `getConGenerator`, `updateConGenerator` and `saveData`.
- Patch `42.22.2/src/zombie/apocbr/power/IsoPowerBank.java`: native deadlines, acknowledgement and activation lifecycle.
- Patch `42.22.2/src/zombie/iso/objects/IsoGenerator.java`: native `updateFridgeFreezerItems` range/container traversal.

See [F-002](../features/F-002-native-power-bank-update.md) and [R-002](R-002-food-power-history-catch-up.md). No runtime code was changed for this audit.
