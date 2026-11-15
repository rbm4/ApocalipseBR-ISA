# F-001: Native loot distributions

Date: **2026-11-15**  
Status: **Implemented; Lua integration/build validation complete, in-game validation pending**

## Decision and behavior

The user confirmed this fork has not been active in the existing save. Preserve no legacy deferred-spawn state. Replace fixed-coordinate panels/crates and room-discovery bank/crate spawning with ordinary native loot registrations. This supersedes the queue and migration proposal in [R-001](../reports/R-001-dependency-removal-and-hotspot-refactor.md).

Vanilla rolls equipment as items in existing containers and electrician vehicles. No ordinary generator placements or loot entries are replaced. Players obtain an `ISA.PowerBank` item and place it through the existing generator/bank lifecycle, or construct a bank through the existing recipe. The ISA model, scripts, identity and `isa_powerbank` simulation are retained.

| Equipment | Registered loot sources |
|---|---|
| Battery bank | `CrateGenerator` junk pool, generator rooms, electronics/tool crates, garage tools, appliance stores, electrician vehicles |
| Solar panel | Military electronics, electronics/tool/mechanics/farming crates, stores, garages, workshops, electrician vehicles |
| Deep-cycle / super battery | Electronics, mechanics, tools, military/storage and electrician vehicles |
| Inverter | Electronics/mechanics/tool stores, crates, garages, electrician vehicles |
| Manual | Bookshops, libraries, magazines, household shelves and electrician vehicles |
| Failsafe | Electronics/military junk pools and electrician vehicles |

Weights are relative native loot weights, not guaranteed percentages. Actual acquisition depends on vanilla rolls, loot rarity, item capacity checks and container availability. Panel/crate locations no longer depend on supported map names. Existing explored containers are not retroactively filled by this mod; newly rolled loot and native loot respawn use the registered tables.

Optional annotated-map stashes still use the native stash system and ISA supply/container tables. This is separate from the removed fixed spawn lookup. Their existing `StashMode` option remains unchanged.

## Implementation and lifecycle

[`Items/Distributions.lua`](../../ApocalipseBR-ISA/42/media/lua/server/ImmersiveSolarArrays/Items/Distributions.lua) now declares item/weight/target registrations. On `OnPostDistributionMerge`, after the engine constructs `SuburbsDistributions`, it appends the entries once and records their weight positions/base values. Missing optional targets emit one startup diagnostic each rather than aborting registration. It explicitly requires the vehicle distributions.

Sandbox settings are applied at `OnLoadedMapZones`, since the inspected engine loads SandboxOptions after distribution merge and initially parses loot before this later event. The handler applies final server multipliers and reparses once, coalescing the existing native annotated-map reparse flag. It does not add per-tick, per-square, room-discovery or per-loot-roll callbacks. It does not repeatedly multiply already scaled values.

The old `fulltype`/`fullType` mismatch prevented most supply entries from being correctly paired with weights. Declarative registrations fix that error, avoid eagerly indexing optional tables and remove the old recursive room-table modification code, including misspelled `proclist` paths. Container/stash definitions required by native ISA objects remain.

[`World/MapObjects.lua`](../../ApocalipseBR-ISA/42/media/lua/server/ImmersiveSolarArrays/World/MapObjects.lua) retains sprite-specific handling for placed/map-authored ISA objects. Bank conversion now reuses its existing load/initialization path, without requiring the removed random-spawn module.

Removed `RandomWorldSpawns.lua`, `RandomWorldSpawns_Locations.lua`, their room/init hooks and the external API require. Removed TargetSquareOnLoad requirements from `project.json`, `42/mod.info` and `common/mod.info`. No dependency code was vendored, no replacement queue was introduced and no legacy save is read or migrated. Other server mods may independently require that dependency.

## Sandbox and translations

- Removed the obsolete `ISA.solarPanelWorldSpawns` option and its EN/PTBR-facing legacy labels where present.
- `ISA.BatteryBankSpawn` now controls native **bank loot** weights: None = 0, Very rare = 0.3, Rare = 1 (default), Uncommon = 3 times the base weights. It does not replace vanilla generators or disable bank crafting.
- Existing `LRMSolarPanels`, `LRMBatteries` and `LRMMisc` scale their registered items, including relevant native solar stash contents; zero disables those weighted entries. DIY/wired batteries in specialized native battery pools retain their existing weights.
- Added EN `Sandbox.json` fallback keys for the revised labels/tooltips. Updated the existing PTBR `Sandbox.json` and matching legacy PTBR sandbox text entries. Other labels and current translation work were preserved.

## Validation

`tests/test_loot_distributions.py` executes the actual installed vanilla room, procedural, clutter and vehicle distribution tables plus this module under **Lua 5.1 through Lupa**. Five tests pass: valid Lua syntax, registration without duplicate entries or removed native generators, final sandbox values including zero/reapply behavior, vehicle/stash support and missing optional targets, and startup-only callback/reparse behavior. All configured targets exist in the tested install.

Run locally with `py -m unittest discover -s tests -v` (requires `lupa` and the configured local game path). JSON/UTF-8-no-BOM checks, metadata/reference checks and the PZ Studio build were also performed.

Remaining in-game checks: fresh container/vehicle loot rolls without TargetSquareOnLoad, bank-item placement/pickup/reload, optional annotated-map stash contents, sandbox rarity behavior on a dedicated server, and first multiplayer join. The harness does not run Java loot probability/capacity logic or prove gameplay rarity balance. No measured TPS/FPS improvement is claimed.

Toxicity, inventory authority, round-robin simulation and packet suppression are separate pending changes described by R-001.
