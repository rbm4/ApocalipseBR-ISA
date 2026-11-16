# Mains at the bank does not cover every appliance in its radius

ID I-005. Created 2026-11-15. Status correction implemented; isolated regressions complete; live retest pending.

## Verified live evidence

The user reported that the indoor bank still did not discharge after I-004. The subsequent `C:/Users/ricar/Zomboid/server-console.txt` contains the new diagnostics, confirming the correction was loaded. At bank 11942,7715,0 it reports:

- Hour 322.545: charge 915.017 Ah.
- Hour 323.046: charge 986.753 Ah.
- Both have `on=true grid=true gridEligible=true drain=230.560 backupOn=false simOn=true simDrain=230.560`, and backup fuel remains 9.762 L.

Charge increased approximately 143 Ah/h despite recognized generator demand. The native scheduler is running and it is not a backup fuel expenditure.

The active server is `servertest`; its saved sandbox configuration has ElecShutModifier=14 and TimeSinceApo=1. Hour 323 is about day 13.46, before the native day-14 cutoff at hour 336. Thus grid=true is consistent with native policy in this capture. I-004's stale-grid/no-power-location protections were useful, but its location-only exemption was incomplete for this setup. Do not change the user's cutoff configuration to conceal the accounting defect.

## Root cause

`IsoGenerator.setSurroundingElectricity()` only adds an appliance when `!ItemContainer.isObjectPowered(obj, false)`. The false argument excludes generator power when checking mains. Its consumption list therefore already represents appliances that need generator supply, potentially outside or in NoPower rooms while the bank itself is indoors on mains.

The energy model nevertheless set all battery demand to zero when the bank tile had mains. Backup control made the same mistake by stopping/prohibiting automatic backup operation. Client drain presentation and final supply/status accounting repeated that assumption. A bank-local mains flag cannot erase a positive residual appliance load.

## Correction

Shared `GridPower.coversLoad` distinguishes mains availability from coverage of the measured load. Battery arithmetic, endpoint/failsafe control, backup status, supply journaling and client/legacy drain presentation use this distinction.

For the native demand calculator, no remaining appliance load means at most the native 0.02 L/h idle floor, converted by ISA's unchanged 800 factor to 16 Ah/h. With mains available only this floor can be exempted. Above it, the entire existing calculated demand is retained. No generator idle cost is removed after mains shutoff. This preserves the existing ISA native consumption formula and avoids inventing an appliance load where only native idling remains.

The optional custom SolarScan now excludes mains-powered objects with the same native `ItemContainer.isObjectPowered(object,false)` predicate before applying its own consumption formula. It has no native idle floor, so only zero residual demand is fully covered. This adds no world scan; it filters the objects inside that existing optional scan.

No source ownership, activation hysteresis, save discriminator or packet layout changes are introduced. Existing cached demand is already in the correct native units and does not need migration. Debug settlement lines now distinguish `grid` from `gridCoversLoad`. Positive residual load should show gridCoversLoad=false even if grid=true.

## Validation and acceptance

`py -m unittest discover -s tests -q`: 55 tests passed. New regressions cover a genuinely live grid with an indoor bank and 230.560 Ah/h residual demand, failsafe activation under that condition, native/custom idle-floor rules, matching client drain behavior, and an actual custom-scan execution with one mains-powered and one generator-dependent fridge. At 145 Ah/h solar input and 230.560 Ah/h demand, one game hour reduces charge by 85.560 Ah.

Packaging and full Lua syntax checks passed. This correction needs only updated server/client mod Lua, using the existing Java foundation. Live acceptance: verify grid=true/gridCoversLoad=false at positive appliance demand, falling charge with backup off, and backup fuel expenditure once failsafe activates. Native synchronous coverage/food refresh costs remain outside a hard time guarantee; this correction does not add history replay work or claim new performance measurements.

See [I-004](I-004-indoor-bank-false-mains-power.md) and [F-003](../features/F-003-budgeted-energy-and-backup-history.md). Engine evidence: patch repository `42.22.2/src/zombie/iso/objects/IsoGenerator.java`, `setSurroundingElectricity`, and `42.22.2/decompiled/zombie/inventory/ItemContainer.java`, `isObjectPowered`.
