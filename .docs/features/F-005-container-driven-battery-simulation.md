# Container-driven battery simulation

ID F-005. Created 2026-11-16. Status implemented; isolated regression checks complete; live multiplayer validation pending.

## Behavior and ownership

The native simulation callback reads batteries directly from `generator:getContainer()` using `PowerBank:calculateBatteryStats`. Battery count, condition-adjusted capacity and weighted stored charge come from actual server inventory items. The simulation integrates energy and writes its resulting common charge fraction to the batteries currently inside that container through `updateBatteries`.

The client inventory-transfer wrapper, ordinary `ISA.TransferAction` handler, `PBSystem:onTransferItem` and `Native.inventoryDelta` are removed. Transfers no longer produce ISA-specific commands. Old clients may still send the command until reloaded, but the server ignores it. Ordinary native inventory networking continues unchanged. No Java change is required.

Per the accepted design, inventory is observed at simulation boundaries. Exact transfer timestamps, intermediate membership and immediate transfer-triggered simulation are outside scope. The existing ten-game-minute/hour callback interval remains. This is a deliberate periodic snapshot model, not a transaction history model.

## Catch-up and compatibility

A persisted `ISA_inventorySampled` flag keeps one container sample across bounded catch-up batches and restart/checkpoint recovery, preventing old item percentages from resetting already integrated charge. Completion writes battery percentages and clears the flag. Loaded banks use current observed capacity for the catch-up interval; unloaded backup-only work retains cached state until a physical bank is available.

Retired `ISA_pendingInventory` deltas are discarded, because current physical inventory supplies the baseline. Existing ISA persistence and command namespaces otherwise remain. The non-native periodic simulation also recounts its loaded containers before integrating energy, so removing the global client wrapper does not strand that fallback.

This implements the inventory command removal proposed in R-001 section 5 using the boundary sampling semantics explicitly accepted by the user. It supersedes the pending transfer-delta design in F-003. It does not claim precise historical membership or measured server performance gains.

## Validation

`py -3.12 -m unittest discover -s tests`: 56 tests passed. The production battery calculation and percentage writer are exercised through the native callback with mixed capacities/charges, stale cached totals and retired deltas, an inserted battery, removal, and an empty bank. Bounded catch-up verifies that the inventory baseline is sampled once and integrated energy is not reset between batches. Existing energy, grid, backup, UI and loot checks also pass.

Live multiplayer validation remains: ordinary looting emits no ISA transfer command after clients reload; installed/removed batteries appear at the next simulation boundary; restart during catch-up preserves progress; empty-bank supply and client percentages behave correctly.

## Sources

- `ApocalipseBR-ISA/42/media/lua/server/ImmersiveSolarArrays/PowerBank/NativeSimulation.lua`: snapshot, simulation, percentage write and completion.
- `PowerBankObject_Server.lua`: `calculateBatteryStats`, `updateBatteries`.
- `PowerBankSystem_Server.lua`: persisted snapshot flag and legacy periodic recount.
- `tests/test_power_budget.py`: physical-container and bounded catch-up regressions.

Related: [F-002](F-002-native-power-bank-update.md), [F-003](F-003-budgeted-energy-and-backup-history.md), [R-001](../reports/R-001-dependency-removal-and-hotspot-refactor.md).
