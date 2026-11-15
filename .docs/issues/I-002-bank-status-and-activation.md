# Bank status proximity and activation diagnostics

ID I-002. Created 2026-11-15. Status status/routing correction implemented, isolated checks passed, live retest pending.

## Report and evidence

The user reported the bank status message `O Banco de Baterias está muito longe` beside a bank and no apparent activation after selecting `Ligar`.

The server log `C:\Users\ricar\Zomboid\Logs\2026-11-15_20-04_DebugLog-server.txt` records bank `11951,7713,0` with native subclass binding, subsequent battery insertion reaching charge/capacity 1000, and panel connections reaching eight. Periodic acknowledgements continue with `supply=false`. This confirms registration and simulation, but the old logs do not establish whether an activation action completed or failed its start roll.

`ISAStatusWindowDetailsView.render` used `getValidBackupArea(player Electrical level)` as its viewing-distance threshold. Electrical level zero gives distance zero, preventing ordinary adjacent inspection. It also combined this with a square visibility check under the same distance message.

The activation timed action included an original skill-based start roll. Electrical levels 0, 1 and 2 succeed with probabilities 1/6, 1/4 and 1/2, respectively. Level 3+ starts are guaranteed by this roll. The user explicitly chose to retain this behavior. Failure previously had no dedicated debug message. This is a possible explanation for an unsuccessful start, rather than a confirmed diagnosis of the specific attempt.

The timed action's client `complete` branch sent ordinary `ISA/activatePowerbank`, whereas the implemented handler was on the `isa_powerbank` global-object channel. Native B42 normally invokes `complete` on the server, so the mismatched client branch alone does not prove failure of normal actions.

## Correction

- `WorldUtil.isWithinPowerBankRange` defines same-level proximity within three tiles of the bank center. The status details gate uses this independently of backup-generator Electrical rules.
- `PBSystem.setBankEnabled` handles timed-action and global-object activation requests through the same server implementation. It checks player proximity and physical bank availability, settles native catch-up before a switch, preserves the start probabilities and synchronizes the resulting state. A long catch-up defers the switch until its accounting reaches current time.
- The timed action's client completion branch uses the global-object command route.
- Sandbox `ISA.Debug` logs queue/path failure, action start/cancellation, server completion/bank lookup, requested skill/charge, catch-up deferral, failed start roll and resulting native activation. Logs can distinguish a missed action from the preserved low-skill failure.
- Repeating an already enabled state does not reroll startup and inadvertently switch off the bank.

This correction is Lua-only. The existing Java power-bank contract continues to apply.

## Validation

`tests/test_power_bank_activation.py` exercises production Lua for skill-independent proximity, distant/different-floor rejection, native catch-up settlement/defer, authoritative on/off application, original low-skill failure and client command routing. Run `py -m unittest discover -s tests -v` from the project root. PZ Studio packaging and source whitespace checks are also required.

Verification on 2026-11-15 passed all 19 Lua tests, including execution of the actual details renderer at Electrical level zero and beyond the interaction range. `npm run build` and `git diff --check` passed. Packaged activation, status-view and server-handler sources match the working tree. Live behavior after loading this correction remains pending.

Live acceptance requires updated server and client Lua. At level 3+, queue `Ligar` beside a charged bank and confirm `Activation action completed on server`, `Activation applied ... activated=true`, and subsequent supply. At lower levels, a failed attempt should log `reason=electrical-skill-start-roll`. Open status beside the bank at level zero, then walk beyond three tiles to verify both display states. Existing logs predate these diagnostics, so the specific original activation failure remains unverified.

See [F-002](../features/F-002-native-power-bank-update.md).
