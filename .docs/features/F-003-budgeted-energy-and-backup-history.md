# Budgeted energy, backup ownership and retained history

ID F-003. Created 2026-11-15. Status implemented; isolated validation and exact-JAR compilation complete; multiplayer and live timing validation pending.

Subsequent behavior update: [F-004](F-004-automatic-backup-control-and-status.md) adds exclusive on/off authority, stop-before-disconnect and runtime presentation. It supersedes the original manual/independently-running backup behavior below; a managed source now stops when its bank is off or the failsafe is missing.

Subsequent correction: [I-004](../issues/I-004-indoor-bank-false-mains-power.md) replaces the old global hydro flag with current B42 grid policy, local mains eligibility and historical shutoff splitting. Indoor placement alone does not exempt a bank from consumption.

Mixed-coverage follow-up: [I-005](../issues/I-005-mixed-grid-generator-load.md) preserves positive native appliance demand even when the bank tile has mains. Native demand already excludes mains-powered appliances; location availability does not cover the entire generator radius.

## Scheduling and synchronization

`NativeSimulation` owns two FIFO queues, with one entry per bank. Native Java callbacks enqueue/defer rather than integrating history inline. OnTick drains due work only; it does not scan the registry, panels, appliances or food. Two of every three service choices prefer ordinary work and one prefers banks more than 24 game hours behind, with work-conserving fallback. FIFO rotation and deduplication prevent a single long history monopolizing service.

Defaults in the module are 32 arithmetic/state-machine steps per job, eight jobs and 256 steps per tick, plus a two-millisecond elapsed-time guard checked between jobs and integration steps. These are initial engineering limits, not measured optimal settings. A native coverage refresh, container finalization, command handler or refrigerator lifecycle call cannot be preempted midway. The time guard is therefore soft, not a promise that the entire tick stays under two milliseconds. Metrics expose jobs, steps, pending entries, failures, final bank broadcasts, queue delay, catch-up latency, frame duration and finalization duration. Sandbox ISA.Debug prints queue work summaries only when jobs run.

`IsoPowerBank.deferUpdate` acknowledges queue ownership while retaining existing supply. Partial batches use `checkpointUpdate`, save bank state without transmission, and requeue fairly. Completion applies physical battery percentages, backup state and bank activation/visuals, broadcasts bank ModData once, and restores the normal game-time deadline. Missing hook acknowledgement and failed scheduled jobs suspend the bank and retry through the existing deadline. Native dirty electricity refresh now occurs inside budgeted preparation.

Activation and panel/backup commands queue one latest pending intent per bank when settlement is needed. The handler runs again after completion, including activation proximity and skill checks. No caller drains historical work inline. Inventory transfer notifications accumulate persisted charge/capacity adjustments and apply them after preceding simulation completes; the bounded aggregate avoids a transfer-event list. Those adjustments use the existing transfer-derived item values and are applied at the completed observation boundary, rather than reconstructing exact transfer timing during backlog.

## Energy and backup state machine

`EnergyModel.step` operates on Lua values without physical source toggles, world scans or item iteration. It splits at production changes, battery empty/full thresholds, backup fuel exhaustion, one running hour of wear, observed backup edits and failsafe hysteresis thresholds. Storage clamps at each boundary. Partial and uninterrupted runs preserve the same state for identical random wear draws and inputs.

Backup fuel consumption uses cached native total consumption times GeneratorFuelConsumption. It is continuous rather than vanilla's whole-clock-hour deduction. Wear rolls once per accumulated running hour using the source item's condition-lowering chance and one/two condition damage. Native loaded-generator backfire/fire/explosion checks, sound, toxicity and activation lifecycle remain native; historical environmental fire/explosion events are not synthesized while unloaded. Historical demand/configuration are held at their last settled values until new observations. This is a defined approximation, not reconstruction of unknown appliance edits.

Failsafe starts at charge <= min(one demand-hour, 25% capacity), and stops at charge >= min(two demand-hours, 75% capacity). The separate thresholds deliberately replace the old single-threshold behavior to avoid rapid oscillation. An empty-capacity bank does not stop an already-needed backup merely because both thresholds are zero. Manual bank shutdown still allows an independently running backup to remain active, matching the prior distinction between the sources.

The server-only `PowerBankBackup` Java bridge gives each linked combustion generator one bank owner. A second bank or an ApocBR permanent managed generator cannot claim it. This restricts the previous ability to associate the same fuel store with several banks: independent bank replays cannot safely spend shared fuel. It does not change normal electricity coverage; other appliances can still receive that generator's native electricity.

Controlled sources skip vanilla's fuel/wear deduction, while retaining its surrounding sound, toxicity, hazard and coverage paths. The engine commits final fuel/condition/activation once through `IsoGenerator.applyISABackupState`, advances the native fuel clock and uses the existing generator packet. No client Java change or packet layout change is required. A loaded owned backup requests the same queue every ten game minutes even when the bank is unloaded; the server global-object table supplies the virtual bank. If both objects are unloaded, no per-bank update runs. No chunks are force-loaded.

Ownership persists in source ModData; simulation fuel, wear remainder, applied/observed source values and pending external observations persist in bank global-object fields and physical ModData. First observation is not credited before its timestamp. Refuel, repair, manual activation, demand-rate and failsafe observations are applied at observation boundaries. Up to 64 pending observations are retained; overflow coalesces to the latest observation and marks an explicit observation gap. Changing consumption alone does not reset spent fuel. A removed/mismatched owner releases the source back to native accounting. The bridge enables only after ISA registers its callbacks; without ISA it does not suppress native accounting.

## Bounded production and supply histories

`ProductionHistory` retains at most 4,096 production change records and merges adjacent identical output/grid states exactly. At one changed record per ten minutes this is roughly 28 game days; compaction can extend coverage. Sparse numeric indices are persisted with explicit first/last bounds and binary search. Normal append evicts one oldest entry. Migration of an existing oversized table exposes only the retained tail immediately and deletes old entries in batches of 128 per tick, rather than traversing/copying 100,000 entries during one callback. Initial legacy memory is released incrementally; native save/GC costs still require live measurement.

If a bank checkpoint predates retained history, the model sets charge to zero at the oldest retained boundary, records `ISA_historyLostUntil`, and integrates retained production from there. No historical backup supply is credited across that unknown period; its retained fuel becomes available at the present boundary. This avoids inventing production or supply but can penalize a very long-unloaded bank. There is no claim of exact simulation outside retained history. Existing saves without an energy configuration establish their cached inputs when first serviced.

Each bank also retains at most 256 effective supply transitions in `ISA_supply`, independent of production sample count. Current effective grid availability, bank supply and owned-backup supply contribute to this journal. Ten-minute grid sampling is approximate. Other overlapping native generators are not yet included in this bank-local journal; it is not by itself an authoritative appliance supply timeline.

## Food bookkeeping direction, not implementation

The intended next integration follows the user's cached-source approach: maintain a versioned container-to-power-source association as coverage changes, and dispatch a food hook only for food whose pending aging interval intersects bank-powered refrigeration. Foods transferred out of such a container must retain a source-epoch boundary until that interval is settled; merely checking their current container would lose relevant history. Movement, pickup/removal, source replacement, overlapping generators and grid changes invalidate/rebuild the association through lifecycle events, not global food scans.

Food consumes effective supply transitions, not solar production records. Prepare/cache a container timeline once and reuse it for its food batch. A transition to no supply begins thawing; zero freezing progress changes frozen state; subsequent age thresholds determine freshness/rot. Power restoration also matters because it can interrupt thawing and resume freezing. Preserve each item's own timestamps, freezing percentage and frozen-state hysteresis; one cached bank identity cannot replace those.

Use the normal native food processing entry, a cheap Java relevance check and one shared work budget. Do not physically replay old generator activations or invoke native refrigerator sweeps per historical transition. Per-item transition work remains resumable and bounded even with cached source lookup. A missing/evicted supply interval, observation gap, item transfer while pending and stock-client synchronization require explicit policies before implementation. No food hook or historical food replay is introduced here. See [R-002](../reports/R-002-food-power-history-catch-up.md).

## Validation and rollout

The Lua suite passed 36 tests exercising aggregate quotas/fairness, one final broadcast, time guarding, a 100,000-record migration, capacity clipping, exhaustion timing, failsafe resumption/hysteresis, observation handling without fuel refunds, pending inventory, queued commands, virtual bank/loaded backup service, failure cleanup and existing activation/loot behavior. All 35 Lua files passed Lua 5.1 syntax checks and PZ Studio packaging passed. Java fixtures compile production ownership/deferred lifecycle code and the production backup-state commit method with doubles. Exact 42.22.2 JAR compilation passes: 375 Java files, 1,068 classes retained in `42.22.2/artifacts/build_20261115_214211` of the patch repository. These do not replace streaming/RakNet/real-time tests.

Deploy the matching server Java patch and packaged mod together. Clients need the updated Lua/content mod only. Live acceptance must cover bank-only/backup-only/both/neither loaded, restart during partial replay, refuel/repair/disconnect and removal, second-owner rejection, ordinary-generator coexistence, hourly combustion hazards, dense appliance/battery populations and actual scheduler/packet timing. A native finalization overrun is observable but not preemptible by this queue.

See [F-002](F-002-native-power-bank-update.md), [R-003](../reports/R-003-catch-up-budgets-and-food-cost.md), and [the Java contract](../../../apocalipsebr-zomboid-patches/42.22.2/docs/features/2026-11-15-power-bank-lua-update.md).

## Inventory update (2026-11-16)

[F-005](F-005-container-driven-battery-simulation.md) replaces transfer-command inventory deltas with direct server-container sampling in the simulation callback. Its boundary sampling semantics supersede the inventory-delta behavior described above.
