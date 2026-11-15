# ApocalipseBR - Immersive Solar Arrays

Author: **Hypothetic**. Project Zomboid **42.13+**. Mod ID: **ApocalipseBR-ISA**.

Development fork initialized from the installed Immersive Solar Arrays B42 `25.0.2` snapshot on 2026-11-15. This import preserves the upstream Lua logic as a baseline for performance and multiplayer refactoring.

## Layout

```text
ApocalipseBR-ISA/
  42/
    mod.info
    poster.png
    media/
      lua/client/ImmersiveSolarArrays/
      lua/server/ImmersiveSolarArrays/
      lua/server/BuildRecipeCode/
      lua/shared/ImmersiveSolarArrays/
      lua/shared/Translate/
      scripts/
      textures/
      sandbox-options.txt
  common/
    media/             # shared models, textures, UI, tile definitions and texture pack
    poster.png
    icon.png
.docs/
  INDEX.md
  issues/
  features/
  reports/
  reference/
AGENT.md
AGENTS.md
workshop/
project.json
package.json
```

The current version folder is `42/` (the original imported folder was `42.1/`). `mod.info` retains `versionMin=42.13`. The old B41 root `media` tree and separate uninstaller were not imported. The empty scaffold sandbox-options file was removed; the complete B42 options are in `42/media`.

Internal `ISA` item/script namespaces, Lua paths, sandbox keys, command modules, global-object system `isa_powerbank`, texture pack name and tile definition ID **575** are preserved. Renaming these would require deliberate migrations and asset/script changes. Enable this fork instead of another ISA fork: they share those identifiers and are not designed to coexist. Existing-save migration has not been validated.

## Build and development

Use the same PZ Studio CLI workflow as the other ApocalipseBR projects. The local import was checked with globally installed `pzstudio` **2.2.0** and Node/npm.

```powershell
npm run build
npm run watch
npm run clean
```

`build` already replaces its own output, so a preceding `clean` is redundant and can fail on a first build. Output is written to the PZ Studio Workshop output directory under the project title. `watch` performs an initial build before watching. Restart the watcher or rebuild after metadata changes. `npm run update` retains PZ Studio's existing library-update command; it is not a Workshop upload command.

PZ Studio generates a root `mod.info` from `project.json`, but its installed generator omits author, modversion, pack and tiledef. The **B42 versioned** `42/mod.info` contains those required fields, as does `common/mod.info`. Maintain relevant identity/dependency fields consistently in those files and `project.json`. This project is tagged B42, is configured as unlisted, and has Workshop item ID `3840506752`. Building does not publish it.

**TargetSquareOnLoad is no longer required.** Panels, batteries, inverters, manuals, failsafes and battery-bank items are registered in native container/vehicle loot tables. Vanilla handles loot rolls; ISA no longer places equipment through coordinate lookups or room-discovery callbacks. Battery-bank rarity and the existing supply multipliers control the registered weights. Optional native annotated-map stashes remain available. See [F-001](.docs/features/F-001-native-loot-distributions.md) for acquisition details and validation.

## Credits and next work

Upstream credits from the imported mod: **RadX5, Poltergeist, ericogamo**. Workshop source: `3670551703`; upstream project URL recorded in that source: `https://github.com/radx5Blue/ImmersiveSolarArrays`. These identify provenance, not a claim that this exact fork matches the current upstream repository. No new license grant is inferred from attribution.

Start at [the documentation index](.docs/INDEX.md) for issues, features and reports. [F-001](.docs/features/F-001-native-loot-distributions.md) records the implemented loot/dependency simplification. [R-001](.docs/reports/R-001-dependency-removal-and-hotspot-refactor.md) retains the broader toxicity, scheduling, inventory authority and Java fallback investigation; its queue/migration recommendation was superseded by the fresh-rollout decision. The [import-era plan](.docs/reference/IMPORT-REFACTOR-PLAN.md) is historical reference. Contributor/agent instructions are in [AGENT.md](AGENT.md), discovered through [AGENTS.md](AGENTS.md).

Initial validation: `npm run build` passed; all 495 imported files other than the intentionally edited `mod.info` matched upstream SHA256 hashes, including all 34 Lua sources. All 496 non-placeholder mod files matched the generated build. JSON parsing and `git diff --check` passed. No in-game or multiplayer validation has been performed.
