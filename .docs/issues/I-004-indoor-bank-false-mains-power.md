# Indoor bank incorrectly bypasses consumption as mains-powered

ID I-004. Created 2026-11-15. Status correction implemented; isolated regression checks and packaging complete; live retest pending.

## Evidence and expected behavior

The user moved the bank indoors, rebuilt its panel/backup setup and enabled it. Reported solar output was approximately 145 Ah/h against 280 Ah/h of appliance consumption, but the bank did not discharge while appliances remained powered.

`C:/Users/ricar/Zomboid/server-console.txt` shows the new bank at 11942,7715,0 enabled at hour 319.093. Between hours 319.299 and 320.970, charge rose from 462.391 to 706.371 Ah, while backup fuel remained 9.762 L. The approximately 146 Ah/h increase is consistent with solar-only charging and a suppressed load. These logs did not include the grid decision, so they do not individually prove the runtime global flag or local eligibility value.

Without actual mains or a running backup, 145 Ah/h production minus 280 Ah/h consumption must produce -135 Ah/h while the bank is supplying the load.

## Root cause verified in source

The original native integration recorded `getWorld():isHydroPowerOn()` into shared history and treated an indoor bank as eligible for mains. The legacy server and client display used the same global flag. That overlooks two B42 rules:

- In 42.22.2 `IsoWorld.isHydroPowerOn` returns a stored field, initialized at world startup. Native current grid availability uses `SandboxOptions.doesPowerGridExist`, which compares current world age (including TimeSinceApo) with ElecShutModifier.
- `IsoGridSquare.hasGridPower()` also rejects `isNoPower()` locations. Native exclusions include user-defined rooms, derelict rooms and NoPower/NoPowerOrWater zones. Being indoors alone does not establish mains eligibility.

Either false assumption can suppress all battery demand and automatic backup operation. Generator-supplied square electricity must not be used to detect mains, because the bank would then exempt its own load.

## Correction and persistence

Shared `GridPower.lua` reads the native current sandbox grid policy and square mains eligibility. Client and legacy loaded-bank drain checks use `square:hasGridPower()` while retaining the bank's indoor restriction. They never use generator coverage as mains evidence.

The native recorder now samples the current sandbox policy. A cached `gridEligible` property retains local eligibility for virtual processing; loaded jobs establish/update it from the actual square, and ordinary bank saves preserve it. Supply journaling and backup status use the same corrected inputs.

Catch-up constrains even previously recorded hydro=true samples by the native shutoff hour, including the TimeSinceApo offset. It splits a compacted production interval at that boundary, so an old sample cannot extend mains electricity after shutoff. Existing samples are not scanned or rewritten. Local eligibility changes use the same last-observed configuration policy as other virtual inputs; already-simulated charge is not retroactively corrected.

Sandbox-debug settlement logs now include actual/current mains, local eligibility, bank on state, cached simulation on state/demand, displayed demand and backup on state. These distinguish real backup support from an exempted or stale load on the live retest.

## Validation

`py -m unittest discover -s tests -q`: 48 tests passed, including five new regressions: the reported 145/280 energy balance despite a stale global flag, shutoff inside one compacted legacy sample, local NoPower exclusion, TimeSinceApo offset, and client drain agreement without generator feedback. Full Lua syntax and packaged-source checks passed; PZ Studio build completed. Other ongoing managed-backup/UI work in the checkout was preserved.

No Java source or packet format changes are required for this correction. Reload the updated Lua/content mod on server and client, with the existing matching Java foundation. Live acceptance: with mains absent and backup off, verify grid=false, on=true, simDrain matching the appliance load and charge falling by net consumption; then verify a genuinely running backup suppresses battery drain while consuming fuel. No claim of live confirmation follows from the isolated tests.

See [F-003](../features/F-003-budgeted-energy-and-backup-history.md). Engine evidence is under the patch repository's `42.22.2`: `src/zombie/iso/IsoWorld.java`, `src/zombie/iso/IsoGridSquare.java`, `decompiled/zombie/SandboxOptions.java` and `decompiled/zombie/GameTime.java`.
