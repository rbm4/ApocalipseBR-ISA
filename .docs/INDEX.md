# Documentation index

Project: **ApocalipseBR - Immersive Solar Arrays**. Maintainer: **Hypothetic**.

Updated: **2026-11-15**. Working conventions: [AGENT.md](../AGENT.md).

## Reports

| ID | Document | Status | Date |
|---|---|---|---|
| R-001 | [Dependency removal and performance refactor](reports/R-001-dependency-removal-and-hotspot-refactor.md) | Loot decision implemented by F-001; remaining hotspots proposed | 2026-11-15 |

## Issues

| ID | Document | Status | Date |
|---|---|---|---|
| I-001 | [Build 42.22.2 translation lookups](issues/I-001-b42222-translation-lookups.md) | Implemented, static validation complete, in-game validation pending | 2026-11-15 |
| I-002 | [Bank status proximity and activation diagnostics](issues/I-002-bank-status-and-activation.md) | Correction implemented; isolated validation complete; live retest pending | 2026-11-15 |

See [issue record conventions](issues/README.md). R-001 contains additional findings to extract when taking them into implementation.

## Features

| ID | Document | Status | Date |
|---|---|---|---|
| F-001 | [Native loot distributions](features/F-001-native-loot-distributions.md) | Implemented; Lua integration/build checked; in-game validation pending | 2026-11-15 |
| F-002 | [Native power-bank update callback](features/F-002-native-power-bank-update.md) | Implemented foundation; isolated checks complete; multiplayer and food-history integration pending | 2026-11-15 |

See [feature record conventions](features/README.md). F-001 supersedes R-001's deferred-spawn queue/migration proposal. The other hotspot refactors remain pending.

## Reference

| Document | Purpose |
|---|---|
| [Import-era refactor plan](reference/IMPORT-REFACTOR-PLAN.md) | Historical provenance and initial analysis; superseded by R-001 for current planning |

Use `I-NNN-...`, `F-NNN-...` and `R-NNN-...` filenames for issues, features and reports. Update this index with each new document or status change. Link implementation evidence and validation results when work is completed.
