# Build 42.22.2 translation lookups

Status is implemented with static validation complete. In-game validation is pending.

Updated on 2026-11-15.

## Defect and evidence

With PTBR selected, ISA items and construction entries can display English names. The installed client's `console.txt` identifies version 42.22.2. Inspection of its `projectzomboid.jar` confirms the following contracts in `zombie.core.Translator` and `zombie.scripting.ui.XuiSkin$EntityUiStyle`.

- `getItemNameFromFullType` uses the full item type directly in `ItemName.json`, for example `ISA.SolarPanel`.
- `getRecipeName` uses the exact case-sensitive recipe name in `Recipes.json`.
- `getMoveableDisplayName` normalizes the tile's group/custom name for `Moveables.json`. The existing six PTBR keys match the mod's tile definitions.
- Entity UI styles pass `DisplayName` through `Translator.getText`. Literal English display names therefore need category-prefixed translation keys.
- General UI, context-menu, tooltip, sandbox and stash lookups retain their category prefixes.

## Correction

- Corrected PTBR item keys and added coverage for all 12 declared items.
- Corrected `UnWireCarBattery` casing and added the five current entity recipe names.
- Replaced five entity display literals with `IGUI_ISA_Entity_*` keys in [entity definitions](../../ApocalipseBR-ISA/42/media/scripts/entities/).
- Added 42 missing summary labels, corrected escaped newlines and completed English-valued PTBR entries in the affected catalogs.
- Changed 15 summary label calls to pass arguments directly to `getText`, using `%1` and `%2` placeholders and `%%` for literal percentages.
- Added the missing `Tooltip_PowerBank` entry. New entity, summary and tooltip labels also have EN fallback entries.

Catalogs are under [Translate](../../ApocalipseBR-ISA/42/media/lua/shared/Translate/). The formatted calls are in [ISAStatusWindowsSummaryView.lua](../../ApocalipseBR-ISA/42/media/lua/client/ImmersiveSolarArrays/UI/ISAStatusWindowsSummaryView.lua).

## Validation

Parsed all ten JSON files with duplicate-key detection and checked string values, category prefixes, exact item/recipe/entity references, ISA Lua/stash references, sandbox labels/tooltips/enum options and EN/PTBR placeholder parity. Verified touched mod files as UTF-8 without BOM and checked the Git diff for whitespace errors.

The remaining runtime check is to reload the mod in a PTBR 42.22.2 client and inspect inventory names, construction entries, picked-up moveables, summary values including percentages and time estimates, sandbox options, context menus and stash annotations. Other hardcoded Lua text is outside this catalog-contract correction.
