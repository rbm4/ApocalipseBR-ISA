# Details device-list refresh

ID I-003. Created 2026-11-15. Status correction implemented; isolated checks complete; multiplayer retest pending.

## Evidence and impact

The user reported newly powered appliances missing after pressing Update in the bank Details view. The previous `ISAWindowDetails:updateDevices` sent `activatePowerbank` with the client's cached on/off state. It did not explicitly rebuild the local native generator's powered-device list. Refreshing display data therefore also reused an unrelated state-changing command.

## Correction

`ISAStatusWindowDetailsView.lua` now calls the native `setSurroundingElectricity()` on explicit refresh and when opening the Details tab, rereads bank data and invalidates the presentation cache. Update sends a separate global-object `refreshPowerbank` request.

`PowerBankSystem_Commands.lua` validates integral coordinates and player proximity, throttles refresh to once per second per bank, recalculates server coverage and drain, requests a native simulation update when available, and synchronizes bank data. It does not request activation or repeat a skill roll. No periodic world scan was added. Existing native coverage rebuilding remains synchronous and uses the generator's normal range.

This fixes the missing explicit refresh path; it does not establish that client generator muting was the root cause. Native lighting processing also services dirty generators independently.

## Validation

`py -m unittest discover -s tests -v`: 21 tests passed. New production-Lua tests exercise Update routing, local refresh on tab opening, preservation of activation state, server drain recalculation, repeated-request throttling, proximity and invalid coordinates.

PZ Studio packaging passed and packaged changed Lua files matched source. Live multiplayer verification remains required: add/remove or switch appliances while a charged bank is running, press Update, and confirm both the displayed devices and server drain change without switching the bank off.

See [I-002](I-002-bank-status-and-activation.md) for activation and [F-002](../features/F-002-native-power-bank-update.md) for native simulation.
