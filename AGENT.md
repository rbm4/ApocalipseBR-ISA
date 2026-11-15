# Project working guide

## Context and layout

This is **ApocalipseBR - Immersive Solar Arrays**, author **Hypothetic**, mod ID `ApocalipseBR-ISA`, forked from the B42 ISA 25.0.2 snapshot. The current game content lives in `ApocalipseBR-ISA/42/` and `ApocalipseBR-ISA/common/`. Do not restore the earlier import folder name `42.1` or the old B41 tree. Check the current files rather than relying on historical reports.

- `42/media/lua/server/ImmersiveSolarArrays/`: authoritative bank simulation, commands, world spawns, loot.
- `42/media/lua/server/BuildRecipeCode/`: construction callbacks.
- `42/media/lua/shared/ImmersiveSolarArrays/`: utilities, bank formulas, timed actions and shared patches.
- `42/media/lua/client/ImmersiveSolarArrays/`: presentation, context menus, client global objects and client patches.
- `42/media/scripts/`: items, recipes, models and `entities/` definitions.
- `42/media/lua/shared/Translate/`: translations; preserve current language/file conventions.
- `common/media/`: shared models, textures, UI, texture pack and tile definitions.
- `project.json`, `package.json`, `workshop/`: PZ Studio metadata and build entry points.
- `.docs/INDEX.md`: documentation entry point and work status.

Preserve other work already present in the checkout. The internal `ISA` namespaces, require paths, sandbox options, `isa_powerbank` persistence name, command module names, sprite IDs, `solarmod_tileset` pack and tile definition ID 575 are compatibility contracts. Change them only with an explicit migration design. Other ISA forks share them and should not be enabled alongside this fork.

## Implementation principles

Read the relevant Lua paths and verify engine assumptions against local source before changing behavior. Use the Project Zomboid B42 modding skill when available. Primary engine source root:

`Z:\Downloads\ZomboidDecompiler\ZomboidDecompiler\bin\output\source\zombie`

Vanilla Lua root:

`Z:\SteamLibrary\steamapps\common\ProjectZomboid\media\lua`

These are local snapshots; confirm compatibility with the deployed build. Prefer Lua changes using proven native APIs and lifecycle hooks. Java patches are a fallback for capabilities Lua cannot reliably provide, and belong in the separate `Z:\git\Github\apocalipsebr-zomboid-patches` project under its own instructions and applicable skill.

Use server-authoritative state and validation. Never trust client-supplied inventory item copies, capacity/charge deltas, permissions or coordinates as proof that an action occurred. Bound command lists and expensive work; make repeated requests safe. Keep ordinary `ISA` commands distinct from global-object `isa_powerbank` routing until deliberately consolidated.

Avoid permanent full-world/full-registry tick scans. Use maintained indexes, loaded/active sets, dirty work queues and bounded fair processing where justified. Preserve elapsed-game-time energy accounting and storage transitions. Routine panel output is already aggregated per bank; do not introduce per-panel energy jobs without a demonstrated need.

Do not force-load chunks just to integrate virtual energy. Do not mutate live world objects, inventories, Lua state or callbacks from worker threads. Any future async computation must use immutable inputs and validated results applied on the game thread.

Never fix solar toxicity by indiscriminately clearing a building's hazard: real combustion generators must remain dangerous. Prove the creation/load/activation/sync paths before removing current workarounds. The user confirmed this fork was not active in the existing save: legacy ISA spawn migration is outside this rollout. Acquisition uses native loot registrations; do not restore the coordinate queue or room-discovery spawning. See F-001 in the documentation index.

## Documentation convention

All maintained issues, features, analyses and reports belong under **`.docs/`**. Start with [the index](.docs/INDEX.md).

- `.docs/issues/I-NNN-short-name.md`: a concrete defect or investigation with reproduction/evidence, impact, current status, proposed correction and validation.
- `.docs/features/F-NNN-short-name.md`: intended behavior, scope, architecture/data flow, persistence/network compatibility and acceptance criteria.
- `.docs/reports/R-NNN-short-name.md`: dated investigation with source evidence, verified findings, proposals, uncertainties and recommendations.
- `.docs/reference/`: provenance and historical context; clearly mark superseded material.

Choose the next unused number in its category. Add or update the matching row in `.docs/INDEX.md` whenever creating a document or changing its status. Link related records instead of duplicating their full contents. Use repo-relative Markdown links and precise file/symbol references; distinguish implementation status from proposed designs. A report is not evidence that its recommendations have been implemented or benchmarked. Update documents with material behavior changes; do not create empty records for hypothetical work.

Keep README a concise project/build entry point with a link to the index. Keep instructions in this file and the root `AGENTS.md` as a discovery pointer. Documentation is outside the packaged mod directories.

## Build and validation

Use the existing commands: `npm run build`, `npm run watch`, `npm run clean`. PZ Studio build replaces its own output; inspect its resolved target before a build that removes an existing directory. Building does not publish. Preserve the current Workshop ID/visibility and user metadata.

Keep relevant identity/dependency fields aligned in `project.json`, `42/mod.info` and `common/mod.info`. The installed PZ Studio generator omits some mod.info fields; inspect versioned output, not just its generated root metadata.

For documentation-only changes, check links, current paths and `git diff --check`; no runtime build is required. For runtime changes, use proportionate checks and exercise affected server/client flows. Verify bank construction, inventory changes, chunk unload/reload, restart, multiplayer synchronization, real-generator coexistence and time transitions as applicable. Measure timing/traffic for performance claims; static operation counts are not benchmarks. Report what was actually checked and what remains unverified.
