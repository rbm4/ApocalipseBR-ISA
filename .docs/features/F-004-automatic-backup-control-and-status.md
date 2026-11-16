# Automatic backup control and runtime status

ID F-004. Created 2026-11-15. Status implemented; isolated validation complete; live multiplayer/UI verification pending.

## Player behavior

A linked native backup is controlled by its bank. Manual start/stop and ordinary generator unplug actions are unavailable while linked. The context menu explains that the player must disconnect the backup association first. Logical disconnection stops the generator before releasing ownership; it remains connected to the ordinary electricity circuit, and normal manual operation becomes available again. Connecting an already running ordinary generator stops it during takeover, after which the bank decides whether automatic activation is needed.

The existing hysteresis is unchanged: automatic start at min(one demand-hour, 25% capacity), automatic stop at min(two demand-hours, 75% capacity). Healthy fuel and condition greater than 20 are required for automatic restart. A managed backup also stops when the bank is switched off, the failsafe is absent, or eligible mains supply is available. Safety shutdown on exhausted fuel or destroyed condition is still permitted by the native guard.

The backup supplies appliances so panel production can replenish storage. It does not add gasoline-derived charge to the batteries. Consequently the status distinguishes running with solar charging from running while waiting for sunlight.

## Server ownership and disconnect

`IsoGenerator` holds a private runtime owner copied from its saved ModData on load or from a validated server claim. Ordinary incoming ModData does not assign this field. Native save writes that authoritative owner back into the existing ModData payload. The generic marker remains a client presentation/persistence projection, not permission to change activation. There are no new packet fields or object IDs and no client Java requirement.

`setActivated` rejects manual changes on controlled sources, with a scoped internal application flag for the bank's final state commit. Emergency off at zero fuel/condition remains legal. `setConnected(false)` rejects ordinary unplugging until the bank association is disconnected. Incoming native generator-state packets are consumed but cannot assert owned source state; the server sends its authoritative state back. Normal generators keep their original behavior.

`PowerBankBackup.release` stops the source while ownership protection is still active, then clears the private owner and public projection and resets the native consumption clock. Bank disconnect first applies any already-accounted partial fuel/condition without refunding it. A stale bank association cannot release another bank's owned source. An unloaded source cannot be physically changed immediately: its retained ownership causes the first loaded native update to detect the missing association, stop it and release control. No chunks are forced into memory to accomplish this.

Native timed-action validation/completion also reject manual activation and unplug on marked sources. This avoids presenting an action as available while the Java server guard rejects it. The old ISA manual-generator activation command is disabled in native mode. Legacy and global-object backup commands share the same settlement, integral-coordinate, proximity, source association and configured range checks. Queued operations re-run those checks after catch-up. Timed connection and single-player presentation paths use the same command service.

## Runtime presentation

The server publishes `ISA_backupStatus` with completed bank state: operating reason, failsafe presence, fuel percent, condition, actual start/stop charge percentages, managed status and observation time. It also updates the linked source's cached on/off state even when the source itself is unloaded. Publication uses the existing final/coalesced bank update, with no new periodic registry scan or per-frame synchronization.

Both Summary and Details use the shared `BackupStatus` presenter. States include automatic operation with solar charging, automatic operation awaiting sunlight, standby, bank off, missing failsafe, exhausted fuel, insufficient condition, mains supply and pending server state. Details displays thresholds, fuel/condition and the manual-control restriction. Source-square inspection is not needed to render these values. Update queues a fresh server observation through the existing budgeted path.

Control is also evaluated at the completed observation boundary, so a newly installed failsafe or refuel can take effect without waiting another simulation interval. Zero-duration supply changes are coalesced in the journal. This is still bank-local history; the deferred food integration remains described in F-003/R-002.

New UI labels use `IGUI_ISABackup_*` keys in the existing EN and PTBR `IG_UI.json` files. Touched Lua/JSON files are UTF-8 without BOM. Internal protocol/debug strings remain untranslated.

The backup operation label and automatic-control badge are green when a backup is connected; the disconnected summary label is neutral gray. Details uses the same connection color for its operation heading/state while keeping numeric information unchanged. Percentage templates escape literal percent signs as `%%`; the native formatter regression and rendering-color checks are recorded in [I-001](../issues/I-001-b42222-translation-lookups.md).

The Solar Fail Safe construction recipe also uses `Tooltip_ISA_SolarFailsafe` in EN/PTBR `Tooltip.json`, explicitly requiring placement on the same tile as the bank's connected backup generator. This uses the native CraftRecipe `ToolTip` field, matching the existing power-bank construction tooltip.

## Validation

Production Lua tests cover locked versus normal timed actions, wrapped native context-menu options, wrong-target/proximity rejection, stop-before-release, cached runtime rendering without a loaded backup square, state/threshold projection, source disable conditions and the stale global hydro flag regression. The complete Lua suite passed 49 tests at verification time, including concurrent grid-policy regressions. All mod Lua syntax and packaged copies are checked separately.

The expanded Java fixture compiles production ownership/guard/commit methods and the actual native incoming state handler with doubles. It verifies rejected manual toggles and unplug, four-field packet consumption without state assertion, unchanged internal automatic control, marker-clear resistance and manual operation after release. Exact-JAR BuildOnly compiled 375 Java files into 1,068 classes, retained at `42.22.2/artifacts/build_20261115_230710` in the patch repository. These are isolated checks, not live RakNet, rendering or server timing results.

Deploy the matching server Java patch and Lua mod together. Live acceptance: automatic low/high threshold crossings, no sunlight, manual start/stop rejection, disconnect while running, normal start after disconnect, refuel/repair, source/bank unload separately, restart, source removal and two-bank stale associations. Verify both English and Portuguese window layout at the actual UI scale.

See [F-003](F-003-budgeted-energy-and-backup-history.md) and [the Java contract](../../../apocalipsebr-zomboid-patches/42.22.2/docs/features/2026-11-15-power-bank-lua-update.md).
