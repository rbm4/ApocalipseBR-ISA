# Documentation index

Project: **ApocalipseBR - Immersive Solar Arrays**. Maintainer: **Hypothetic**.

Updated: **2026-11-16**. Working conventions: [AGENT.md](../AGENT.md).

## Reports

| ID | Document | Status | Date |
|---|---|---|---|
| R-001 | [Dependency removal and performance refactor](reports/R-001-dependency-removal-and-hotspot-refactor.md) | Loot decision implemented by F-001; remaining hotspots proposed | 2026-11-15 |
| R-002 | [Food catch-up across power-bank outages](reports/R-002-food-power-history-catch-up.md) | Source investigation complete; hook/replay proposed | 2026-11-15 |
| R-003 | [Catch-up budgets, backup transitions and food cost](reports/R-003-catch-up-budgets-and-food-cost.md) | Pre-change audit; energy proposals implemented by F-003; food replay deferred | 2026-11-15 |

## Issues

| ID | Document | Status | Date |
|---|---|---|---|
| I-001 | [Build 42.22.2 translation lookups](issues/I-001-b42222-translation-lookups.md) | Implemented; native percentage formatter regression checked; in-game validation pending | 2026-11-15 |
| I-002 | [Bank status proximity and activation diagnostics](issues/I-002-bank-status-and-activation.md) | Correction implemented; isolated validation complete; live retest pending | 2026-11-15 |
| I-003 | [Details device-list refresh](issues/I-003-device-list-refresh.md) | Correction implemented; isolated checks complete; multiplayer retest pending | 2026-11-15 |
| I-004 | [Indoor bank falsely assumes mains power](issues/I-004-indoor-bank-false-mains-power.md) | Corrected; regression checks complete; live retest pending | 2026-11-15 |
| I-005 | [Mixed mains and generator-dependent appliance load](issues/I-005-mixed-grid-generator-load.md) | Correction implemented; live cause traced; regression checks complete; live retest pending | 2026-11-15 |

See [issue record conventions](issues/README.md). R-001 contains additional findings to extract when taking them into implementation.

## Features

| ID | Document | Status | Date |
|---|---|---|---|
| F-001 | [Native loot distributions](features/F-001-native-loot-distributions.md) | Implemented; Lua integration/build checked; in-game validation pending | 2026-11-15 |
| F-002 | [Native power-bank update callback](features/F-002-native-power-bank-update.md) | Implemented foundation; isolated checks complete; multiplayer and food-history integration pending | 2026-11-15 |
| F-003 | [Budgeted energy, backup ownership and retained history](features/F-003-budgeted-energy-and-backup-history.md) | Implemented; isolated checks complete; multiplayer/timing validation pending | 2026-11-15 |
| F-004 | [Automatic backup control and runtime status](features/F-004-automatic-backup-control-and-status.md) | Implemented; isolated checks complete; multiplayer/UI validation pending | 2026-11-15 |
| F-005 | [Container-driven battery simulation](features/F-005-container-driven-battery-simulation.md) | Implemented; 56 regression checks pass; live multiplayer validation pending | 2026-11-16 |

See [feature record conventions](features/README.md). F-001 supersedes R-001's deferred-spawn queue/migration proposal. F-005 implements inventory command removal with periodic container sampling; other remaining hotspot proposals are tracked in R-001.

## Reference

| Document | Purpose |
|---|---|
| [Import-era refactor plan](reference/IMPORT-REFACTOR-PLAN.md) | Historical provenance and initial analysis; superseded by R-001 for current planning |

Use `I-NNN-...`, `F-NNN-...` and `R-NNN-...` filenames for issues, features and reports. Update this index with each new document or status change. Link implementation evidence and validation results when work is completed.
