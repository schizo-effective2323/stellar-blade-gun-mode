# NikkeGunMode - research notes

Goal: enter the NIKKE DLC missions' "Gun Mode" (the TPS cover-shooter mode) during normal gameplay.

## Status (2026-11-14)
- Ctrl+G puts Eve in NIKKE Gun Mode in the open world (IsTPSMode=true, TPSModeType=2) and turns it off again - confirmed in game.
- Open: she aims (Ctrl) but never fires. She can't move (by design - cover shooter tied to mission cover spots).
- v0.4 test: confirmed Eve keeps Bullet_Normal equipped in Gun Mode (GetCurrentBulletItemAlias) - the bullet switch did not run because hooks on her ServerRequest_* calls never fire in single player (no GUID).
- v0.4b test: SBNetworkPlayerState.ActorNetGuid = 0 in single player; ClientBroadcast_ActorSetBulletItem doesn't fire either (bullet changed in the wheel to Bullet_Missile, no hook call). No reflected way to read Eve's GUID.
- v0.4c: finds the GUID by calling ServerRequest_ChangeBulletItem(g, "Bullet_Nikke") for g = 1, 2, 3... (batches of 1500 per tick, up to 300000) until GetCurrentBulletItemAlias reads Bullet_Nikke.
- v0.4c test: search found Eve's GUID = 1501 in 0.3 s (her bullet read Bullet_Nikke right after the request), but 0.5 s later it read Bullet_Missile again - the game reverts it (likely the ammo-slot manager: Bullet_Nikke isn't in BulletItemSlotArray). Calls made from Lua DO trigger UE4SS hooks on ServerRequest_*; the game's own calls don't.
- v0.4d: while Gun Mode is on, re-sets Bullet_Nikke every 100 ms and logs the reverts (test whether she fires while it's set).
- v0.4d test: the game reverts the bullet every ~0.15 s (73 reverts in 14 s); still no fire. Bullet route abandoned (FORCE_BULLET=false).
- v0.5: data fix instead. CharacterStanceTable: stance P_Eve_GunNikke (100114) = active while effect P_Eve_GunNikke is on and aim (SkillCommandState_TPSMode) is held; its CommandArray holds P_Eve_GunNikke_ShootSlug1_1/_2. SkillCommandTable: those two are SkillCommandAction_RangedFireItem with BulletItemAlias Bullet_Nikke (fire only while that bullet is equipped). The burst shot ShootSlug2 uses RangedFireSkill (no bullet). zNikkeGunMode_P (built by runner_jobs/ngm_build_cmdpak.py from build/SkillCommandTable.ngm.patch) switches ShootSlug1_1/_2 to RangedFireSkill. Side effect to check: ammo may no longer count down (in the missions too).
- v0.5 test: still no fire with zNikkeGunMode_P installed (game restarted). v0.5b logs Eve's state changes while Gun Mode is on (IsRunningSkill, IsActiveTPSAimOffset, bTPSZoomIn, TPS type, bullet) to see whether aiming/firing registers at all.
- v0.5b test (11-15): Ctrl+G -> crouch; holding Ctrl -> laser sight (stance P_Eve_GunNikke's AimEffect), left-click -> nothing, no sound. Logged state never changes while aiming/clicking: IsRunningSkill=false, IsActiveTPSAimOffset=true, bTPSZoomIn=false. RMB+LMB also nothing. So the stance comes up but no fire command ever runs.
- Ghidra pass 3 (ghidra/ghidra_nikke_decomp3.txt) - the rest of what the stage entry 0x141c2ede0 switches on:
  - FUN_14232c1b0(1): forces r.ForceAspectRatio (letterbox) - cosmetic.
  - FUN_1422a5280(x, 0): decrements a counter at +0x388 of an object and toggles two UI objects (vtable +0x320/+0x328) - HUD swap.
  - FUN_141adc360() = a 0x610-byte native game-state singleton: stage sets +0x43 = 1 and +0x4c = 3.
  - DAT_147032aa8 = 1: global switch read by FUN_1424a0ff0 to pick handler [1] instead of [0] from a 2-entry list (probably the input/command handler).
  - FUN_141a8cab0(actor, bullet) = native bullet setter (actor +0x28bc); local path FUN_141a8cb20 when a setting byte (+0x5b0) is set, network path FUN_141b01650 otherwise. Also called by FUN_141ec0490 / FUN_141c316d0 (probably stage exit / slot refresh -> the reverts we saw).
  - None of these are reachable from Lua (no reflected function); a native (C++) UE4SS piece could set them.
- v0.6: native part. `native/ngm_native.cpp` -> NikkeGunMode.dll (VS2019 on the PC, `runner_jobs/ngm_build_native.py`), loaded by the Lua mod with package.loadlib like StellarCoop.dll (exports in lua_CFunction shape, no Lua linked; result code = number of args returned). ngm_on does the stage-entry switches: singleton +0x43=1/+0x4c=3, DAT_147032aa8=1, EVE's bullet -> Bullet_Nikke via FUN_141a8cab0 (EVE found as the stage entry finds her). ngm_off restores. Pinned to Steam build 26123051 (PE stamp 0x6ad8eff1 / size 0x15fa3000, StellarCoop's pin; StellarCoop's log confirms the installed game is that build, and its docs use the same addresses as the shared Ghidra project). Log: Mods\NikkeGunMode\NikkeGunMode_native.log.
- Background (stellar-blade-coop native docs, lion/shock.h): firing comes from the gun stance's CommandArray - SkillCommandTable rows of type RangedFireItem with a BulletItemAlias; the ammo wheel list is BulletItemSlotArray in SB's const store. The coop native part keeps the local player's GUID at client +0x58. Data fallback if the GUID search fails: give the NIKKE stance fire commands for the shipped bullets.

## Layout
| Path | What |
|---|---|
| `ue4ss/` | the UE4SS Lua mod (goes to `ue4ss\Mods\NikkeGunMode`) |
| `build/` | data-pak scripts: `NGM_2_build.bat` patches the rows below into Survival Protocol's `RoguelikeMode_P` (base `OutfitWork\sp_data1113a\stage`), backs up the original (`NGM_restore_sp_pak.bat` restores it). `*.ngm.patch` = exact find/replace edits for `RoguelikeBuild\apply_patch.ps1`. `1f_extract_nikke.bat` / `NGM_1_extract.bat` export tables. |
| `ghidra/` | headless Ghidra scripts + their output (strings with xrefs, decompiled gun-mode functions) |
| `native/` | NikkeGunMode.dll source + build script (game-memory switches Lua can't reach) |
| `runner_jobs/` | jobs for the OutfitWork runner: Ghidra headless runs, table export, the zNikkeGunMode_P build |

## How it works
- SBCheatManager commands (SBApplyEffectMe etc.) do NOTHING in the release build - tested.
- Working route = Survival Protocol's: `SBBlueprintLibrary.CreateSBZoneEvent(type, row)`
  - type 2 -> EventActorEffectTable row -> puts one EffectTable effect on Eve
  - type 13 -> EventItemActionTable row -> gives an item (TargetFilter `Xion_10_LevelTargetFilter_013`)
- Rows added:
  - `NGM_AE_GunOn` P_Eve_GunNikke / `NGM_AE_GunOff` P_Eve_GunNikke_Dispel
  - `NGM_AE_Pos2` P_Eve_GunNikke_Position2 / `NGM_AE_PosOff` P_Eve_GunNikke_Position_Dispel
  - `NGM_AE_MaxHP` / `HP` / `Beta` (+ `_Off` dispels): Nikke HP and burst gauge to 100
  - `NGM_AE_Ammo` P_Eve_GunNikke_BurstSkillReloadCompleted (ItemRefill Bullet_Nikke 60, no conditions)
  - `NGM_ItemA_Ammo`: Acquire Bullet_Nikke x60
- Keys: Ctrl+G toggle, Ctrl+Shift+G status (F6/F8 clash with the outfit mod).
- Bullet switch (v0.4): `SBNetworkPlayerController:ServerRequest_ChangeBulletItem(actorGUID, "Bullet_Nikke")`; Eve's GUID is learned by hooking her own `ServerRequest_*` calls (jump etc.). `SBCharacter:GetCurrentBulletItemAlias` reads it back.

## Ghidra findings (addresses in the shared SB project; it predates the Oct 30 game patch)
- `0x141c2ede0` = NIKKE stage entry: reads game config `NikkeStage_ChangeBullet` (= Bullet_Nikke) and switches the player's equipped bullet to it, then sets several stage flags (not identified yet).
- `0x141a8c2b0` = TPS mode switch; uses config `TPS_Shot_CommandKey` for the shot command.
- `0x141c37890` / `0x141c33510` = NIKKE player-side logic: apply `P_Eve_GunNikke_AimEffect`, handle UI events TPSNikke_Reload / ClipInfinity / HideOff / CoverPosition / TargetCover.
- `0x141a6c240` references "P_Eve_GunNikke".
- Config keys of interest: TPS_Nikke_* (HUD offsets), NikkeStage_HealItemAlias, Positioning_Nikke_GridCount.

## Running things on the PC
- OutfitWork runner (`OutfitWork\runner.bat`): write a quoted .py path into `OutfitWork\job.txt`; it runs with Blender's Python (subprocess works).
- Ghidra headless: `C:\Tools\ghidra`, project `Modding Tools\ghidra_sb` (owner mothersphere - `GHIDRA_HEADLESS_JAVA_OPTIONS=-Duser.name=mothersphere`, `-readOnly`), JAVA_HOME = `Modding Tools\jdk25\jdk-25.0.4.1+1`. One run ~10-25 min.

## Game data facts
- P_Eve_GunNikke = EffectAction_TPSNikke (enum 35), param "Eve_NikkeGun" -> ESBTPSModeType_Nikke (2).
- NikkeStageTable start (all 5 stages): items Bullet_Nikke x60 + Potion_Nikke x1; effects ReloadStartDelay, P_Eve_GunNikke, Position2, LV_SummonDrone_Dispel, PeacefulMode_Infinite, MaxHP100, HP100, MaxBetaGauge100, BetaGauge0, stage-start screen effect, a BurstSkill2Sequence; skills GunNikke_BurstSkill1..3.
- Shooting is not in the stage skill list (only bursts). Shoot skill: P_Eve_GunNikke_ShootSlug1_1 (cooldown 0.11 s). In the missions holding aim both aims and fires.
- Cover positions Left/Center/Right are mission-placed (EVEPosition); Position effects send UI event TPSNikke_CoverPosition.
- Survival Protocol's pak also replaces EventActorEffectTable/EffectTable/etc. - a standalone release needs a merged pak.
- retoc can't convert Survival Protocol's container to legacy (container version differs from global).

## Native crashes (v0.6, v0.7) — 2026-11-15
- Both versions made the game window vanish instantly: no UE crash reporter, and no crash folder in AppData\Local\SB\Saved\Crashes.
- The v0.7 step log stops at `step: on: singleton FUN_141adc360`. So the very first call into game code (a trivial 97-byte getter) killed the process, and the SEH guard never got control.
- The shipping exe is wrapped by a protector. Its sections are .debug$P, .link, .sbss, .edata (0xe3d1338 bytes, RWX), .xtls and .code, and the bytes on disk at the Ghidra addresses are not function starts (ngm_exe_check.py, NikkeGunBuild\exe_check.txt). The Ghidra project matches the decrypted in-memory image.
- Conclusion: calling game functions from our DLL triggers the protector's silent kill.
- v0.8 makes no calls at all. It only reads and writes data in .sbss: the singleton pointer DAT_147032598, then +0x43 and +0x4c, and the switch DAT_147032aa8.

## v0.8 native result + v0.7 Lua fire (2026-11-15)
- v0.8 ran without crashing. The log confirms the switches went in (singleton +43 0→1, +4c 0→3, DAT_147032aa8 0→1), but firing was unchanged. So the NIKKE stage-entry switches don't control firing.
- UE4SS_ObjectDump shows `SBNetworkPlayerController:ServerRequest_UseSkill(inCasterUID u32, inCommand u8, inSkillId u32, inCommandNodeName FName, inTargetActorIdList TArray<u32>, InTargetLocation FVector, inInputWorldDirection FVector)`. There's also `ServerRequest_ActorStancePressCommandKey(guid, stanceAlias, bool)`.
- ESBSkillCommandState: SkillCommandState_TPSMode = 43, SkillCommandState_TPSFire = 44.
- P_Eve_GunNikke_ShootSlug1_1 is SkillCommandTable ID 1007601 and SkillTable ID 1007601 (ShootSlug2_1 = SkillTable 1007602).
- Lua v0.7: Ctrl+LMB in Gun Mode sends UseSkill(1501, 44, 1007601, "P_Eve_GunNikke_ShootSlug1_1", {}, GetTPSLookAtWorldLocation, direction). Each shot logs the stance plus IsRunningSkill 150 ms later.
- v0.7 result: no shot, and the game lagged. The UE4SS keybind repeats while held, which sent 72 requests in about 5 s.
- While aiming, the stance read **P_Eve_GunNikke**, so the NIKKE stance is active and the fire command has somewhere to go.
- The aim point was (0,0,0) because GetTPSLookAtWorldLocation takes a bool (inReCheckHitLocation).
- IsRunningSkill never became true.
- v0.7b: shots are rate-limited to 4/s, the aim call is fixed with (true), and enable() checks the GUID (bullet read-back) and runs the search if it isn't Eve.
- v0.7b result: the aim point is now real (e.g. 50136,6451,-19997) and GUID 1501 is confirmed, but there's still no shot. The frame dips came from the GUID search starting the bullet keeper (124 swaps in 30 s).
- **Key data finding:** SkillCommandTable P_Eve_GunNikke_ShootSlug1_1 has DualSenseCheckType True plus a DualSenseTriggerEffectState_WeaponFired condition, so it is the DualSense-only fire command. **ShootSlug1_2** (ID 1007602, DualSenseCheckType False) is the keyboard/mouse one; both run skill P_Eve_GunNikke_ShootSlug1_1 (1007601).
  - Both have CheckActiveNoneEffectAliasArray: P_Eve_GunNikke_BulletZero and P_Eve_GunNikke_ShootSlug2, plus InputType HoldKeep.
  - The stance P_Eve_GunNikke also needs P_Eve_GunNikke_BulletZero and P_Eve_GunNikke_Block to be absent.
- v0.7c: the command node is ShootSlug1_2, the keeper only runs with FORCE_BULLET, and the GUID defaults to 1501.
- v0.7c result: no shot. The user reports stutter while just aiming, with no clicks. Cause: the v0.5b diag loop ran every 150 ms and called getPC() → FindFirstOf (walks GUObjectArray). v0.7d turns diag off by default and caches the controller.
- The next Ghidra pass (NikkeNative.java / ngm_ghidra_native.py) looks for the ASCII UFunction names ServerRequest_UseSkill and ServerRequest_ActorStancePressCommandKey. It then finds the {name, exec} native-table pairs pointing at them and decompiles exec → _Implementation → callees (depth 3), to see what rejects a fire request from Lua.

## UseSkill native path (Ghidra pass, 2026-11-15)
- The ASCII "ServerRequest_UseSkill" string has two pointer pairs:
  - 0x145e91be8 → 0x142764e10 (no function defined)
  - 0x145e9c860 → FUN_142760050
- FUN_142760050 is the exec thunk. It unpacks the params, calls `controller->vtable[+0x1580]` (_Validate; on false it sets the "ServerRequest_UseSkill_Validate" error), then `vtable[+0x1588]` (_Implementation).
- ServerRequest_ActorStancePressCommandKey: exec FUN_14275e740 → vtable +0x14d0 (_Validate) / +0x14d8 (_Implementation).
- Native v0.8b adds ngm_vtable. It reads the controller address that Lua writes to NikkeGunMode_addr.txt (Ctrl+Shift+G) and logs those vtable slots as Ghidra addresses, using data reads only. Those addresses get decompiled next.
- Runtime vtable (Ctrl+Shift+G, 11-15 07:18), SBPlayerController:
  - UseSkill: _Validate +0x1580 = 0x1423be0f0, _Implementation +0x1588 = 0x1423be1d0
  - StancePress: _Implementation +0x14d8 = 0x1423bf3a0
- The Ghidra project folds those entry points into neighbouring functions (FUN_1423be0e0 / FUN_1423be160 / FUN_1423bf350). Those neighbours are the client-side message senders: they run only if FUN_143f69360 (net mode) == 3, stamp +0x850, build a packet and hand it to FUN_141af3c70 (the message queue).
- ngm_ghidra_native3 removes the mis-bounded function and creates one exactly at each vtable address.
- The stutter is confirmed fixed by v0.7d.
- Pass 3 result: the runtime +0x1588 slot (0x1423be1d0) decompiles to an empty 6-byte function, and +0x14d8 (0x1423bf3a0) is "bad instruction data". The +0x1580 slot (0x1423be0f0) is a client-only sender: it runs only if net mode == 3, so it does nothing in single player.
  - Either the controller's vtable layout doesn't match the exec thunk's offsets (the object is a subclass?), or the protector keeps those stubs encrypted or relocated in the dumped image.
  - Static analysis of this path has stalled. Status: firing is still unsolved.

## Real NIKKE stage check (2026-11-15 09:04)
- In a real drone stage, with every NikkeGunMode file installed (including the zNikkeGunMode_P SkillCommandTable pak), firing works normally: Ctrl = aim, LMB = fire, Shift+A/D = swap cover. So our files don't break firing; our Gun Mode is missing some piece of state.
- Lua v0.7f: Ctrl+Shift+G also writes NikkeGunMode_snap_<time>_<n>.txt. It dumps every simple property (walking ForEachProperty up the class chain) of the pawn, controller, player state, game state and game mode, so a real stage can be diffed against our mode.
- Drone stages can be replayed after their quest (one per drone location), so the real stage can be used for comparisons any time.
- **Snapshot diff (stage ×2 vs ours, while aiming):** the stance is P_Eve_GunNikke and bTPSMode/bIsActiveTPSAimOffset match. The meaningful differences:
  - `SBCharacter.CurrentBulletItemAlias`: stage "Bullet_Nikke", ours "Bullet_Normal"
  - `SBCharacter.CustomLookAtActive`: stage true, ours false
  - The real stage is a separate map, /Game/DLC_2/Art/BG/WorldMap_NK_MiniGame/NK_MiniGame_02_P.
- v0.8 Lua: while Gun Mode is on, CurrentBulletItemAlias = Bullet_Nikke and CustomLookAtActive = true are held by plain property writes every 50 ms (rewritten only when changed; no RPC, so no equip spam). Both are restored on exit.
- Ctrl+R hot reload crashed the game once (in a stage, v0.7f). Cause unknown — possibly the DLL handle when the Lua state is torn down. Restart the game instead for now.
- v0.8 result: the property write holds the bullet (1 rewrite in 20 s, never reverted again), with no stutter. She still doesn't fire and IsRunningSkill stays false, so the bullet was needed but isn't the whole story.
- NikkeStageTable PlayerStartEffects that we never applied: P_Eve_GunNikke_ReloadStartDelay, LV_SummonDrone_Dispel, PeacefulMode_Infinite, P_Eve_GunNikke_BetaGauge0, Nikke_StageStart_ScreenEffect_Show, BurstSkill2SequenceB.
  - The fire commands require **P_Eve_GunNikke_BulletZero to be absent**. The stage's opening reload (ReloadStartDelay) is the likely thing that clears it.
  - The normal drone owns TPS aim/fire, and the stage dismisses it.
- v0.8b adds EventActorEffectTable rows (in the SP pak; IDs 900012–900015):
  - NGM_AE_Reload → P_Eve_GunNikke_ReloadStartDelay
  - NGM_AE_NoDrone → LV_SummonDrone_Dispel
  - NGM_AE_DroneLock → P_EVE_DoNotSummonDrone
  - NGM_AE_DroneFree → P_EVE_DoNotSummonDrone_Dispel
  - Lua fires the first three on enter and DroneFree on exit.
- v0.8b result: still no fire. Worse, the drone vanished and **didn't come back after exit**, so the normal ranged weapon was gone too (DoNotSummonDrone_Dispel alone doesn't re-summon it).
- v0.8c: the drone rows are removed from ON. Exit (and a one-time repair 8 s after each load) fires NGM_AE_DroneFree plus the game's own rows Xion_11_E_ActorEff_001 (P_EVE_DoNotSummonDrone_Dispel) and CGH_data_E_ActorEff_003 (P_Eve_Sword_SummonDrone). The opening reload row stays.
- The drone is back after v0.8c's repair (user confirmed).
- **Full snapshot diff (object refs included):** in the stage, `SBCharacter.CurrentCameraVolume` = NK_MiniGame_City_LD … NKGame_City_CameraVolume_Center (an SBCameraVolume), `TPSSwitchableTimeFromCameraVolume` = 7.4, and `TouchTriggerMap` has 2 entries. Ours: no camera volume, 0.0, and 0 entries.
  - SBCameraVolume has `EnableTPSFlag` (bool, offset 0x400), `EffectAlias` (an effect applied in the volume), `BlockSkillInVolume`, `TPS_SwitchableTime` and the LookAt* settings (which match CustomLookAtActive = true in the stage).
  - Leading hypothesis: the stage's camera volume is what lets NIKKE fire through.
- v0.8d: the snapshot also dumps the current camera volume's properties and the TouchTriggerMap contents.

## Breakthrough lead: start the shot skill through an effect (2026-11-15 14:05)
- The stage's camera volume (NKGame_City_CameraVolume_Center) is camera-only: EnableTPSFlag true, EffectAlias None, nothing blocked. So that wasn't it.
- **StellarCoop's cut/chainspin.lua** starts a skill without any input by applying an EffectTable effect whose **Action1 = EffectAction_UseSkill (69)** and ActionValue1 = the SkillTable name (0.1 s, LifeType IndependentTime, TargetFilter Self).
  - It applies the effect with `pc:ServerRequest_Cheat(EVE_GUID, 0, 'SBApplyEffectMe', tostring(effectID))`. That's the controller's cheat *request* (FSBCheat::Simulate → effect call 0x141ad1af0), not the dead SBCheatManager console command.
- Survival Protocol ships its own EffectTable (sp_data1113a stage; 439 MB as JSON, ID max 9900203).
- v0.9:
  - EffectTable row **NGM_Fire (ID 9900301)** = clone of M_Scarlet_CounterLinkStart (a clean UseSkill effect) with ActionValue1 = P_Eve_GunNikke_ShootSlug1_1.
  - EventActorEffectTable row NGM_AE_Fire (900016) → NGM_Fire.
  - Built by runner_jobs/ngm_build_sp_pak2.py (the full SP pak build in Python, including the EffectTable patch).
  - Lua: Ctrl+LMB = zone route (CreateSBZoneEvent 2, NGM_AE_Fire); Ctrl+Shift+LMB = cheat route (ServerRequest_Cheat SBApplyEffectMe 9900301).
- v0.9 result: both routes were sent without error (zone ×3, cheat ×17), but there was no shot and IsRunningSkill stayed false. SkillTable P_Eve_GunNikke_ShootSlug1_1 has no gating fields: SkillType RangeAttack, ConsumeItemCountType Default (it probably consumes the bullet item).
- v0.9b, to isolate the cause:
  1. On enable: `ServerRequest_ItemBucketItemAdd(1, guid, "Bullet_Nikke", 60, 0, true, false, false, {})` (StellarCoop shop.lua's call).
  2. Control effect NGM_Test (9900302) = UseSkill P_Eve_Sword_Normal_Potion_1, on test key Ctrl+Shift+H via the cheat route.
  3. Ctrl+Shift+J = cheat SBApplyEffectMe 10082 (P_Eve_GunNikke), which shows whether the cheat route applies effects at all.
- v0.9b result:
  - The cheat route applies nothing on a normal save: SBApplyEffectMe 10082 didn't start Gun Mode. StellarCoop presumably has its native/session state enabling it.
  - Ctrl+Shift+H (cheat route potion): nothing. Ctrl+Shift+J also opens the game's mission menu.
  - Ammo was sent via ItemBucketItemAdd; the zone NGM_Fire still produces no shot.
- v0.9c: EAE row NGM_AE_Test (900017) → NGM_Test, and Ctrl+Shift+H now fires that zone row. This tests whether a zone-applied UseSkill effect can start any of EVE's skills. The J key is removed.
- **v0.9c result: the control works.** The zone row NGM_AE_Test → NGM_Test (Action1 UseSkill P_Eve_Sword_Normal_Potion_1) made EVE drink a potion. So zone-applied UseSkill effects do start EVE's skills, and NGM_Fire should be reaching her. The NIKKE shot skill itself is what refuses.
- v0.9d: test key Ctrl+Shift+N fires NGM_AE_Fire anywhere (in or out of Gun Mode). Ctrl+Shift+H (the potion) also works anywhere. Two questions: does Gun Mode block all skills, and can the shot skill play outside Gun Mode?
- **Hotkey rule:** use only the keys NikkeGunMode owns in the user's hotkey map: Ctrl+G (toggle) and Ctrl+Shift+G (status/test), plus Ctrl+LMB fire while in Gun Mode. Test keys that clashed: Ctrl+Shift+J (mission menu), Ctrl+Shift+N (CNS menu). v0.9e removed every extra bind (H, N, Ctrl+Shift+LMB); Ctrl+Shift+G now runs the shot test (NGM_AE_Fire anywhere).
- **v0.9e result:** Ctrl+Shift+G (NGM_Fire) outside Gun Mode "cancels out of everything"; inside Gun Mode nothing visible. IsRunningSkill is false at +150 ms either way.
- **SkillActiveStepTable** (steps.txt): the NIKKE shot is only about 0.07 s long, so a +150 ms IsRunningSkill check would miss it even when it runs.
  - Cast1 is 0.01 s, with StartSelfEffect P_Eve_GunNikke_SkillUseCheck.
  - Hit1 is 0.01 s, Type **SkillActiveStepType_Item**, Show CH_P_EVE_01/Skill/P_Eve_GunNikke_ShootSlug1, projectile P_Eve_GunNikke_ShootSlug1_Projectile1.
  - Finish1 is 0.05 s.
  - Hit1 is an item step and probably consumes a Bullet_Nikke round, so ammo is the prime suspect. The potion, by comparison, is 1.8 s with a visible Show.
- **HUD bug:** after today's tests the user reports all HUD elements missing in game.
  - The native log shows DAT_147032aa8 reading 192 (0xC0) / 64 (0x40) before our write, so it's a **bit field, not a flag**. Writing 1 clobbers it.
  - The singleton +0x43/+0x4c (stage mode) likely drives the HUD swap as well.
  - v0.9f turns the native switches off (CFG.NATIVE_SWITCHES = false); they never helped firing.
- The HUD is back after a restart with v0.9f (native switches off), confirming they caused it.
- Ammo isn't the blocker: the bag shows "<> x60" under Ammo (Bullet_Nikke has no localized name outside the DLC).
- New theory: the shot skill's fire step Hit1 is Type **Item** and spends the bullet chosen by the fire command (RangedFireItem's BulletItemAlias). When the NGM_Fire effect starts the skill directly, no command supplies a bullet, so the step fires nothing.
  - ngm_build_cmdpak2.py adds SkillActiveStepTable to zNikkeGunMode_P with Hit1's Type switched to Cast1's plain type, so it simply fires P_Eve_GunNikke_ShootSlug1_Projectile1. Side effect: real stages wouldn't spend NIKKE ammo.

## FIRST SHOTS (2026-11-15 15:07)
- With zNikkeGunMode_P's SkillActiveStepTable edit (ShootSlug1_1_Hit1: Item → None), Ctrl+LMB in Gun Mode plays the NIKKE **fire sound and muzzle flash on every click**. The shot skill runs. No projectile is visible yet.
  - Likely cause: the skill's TargetDetectionType is TargetFilter with no target or aim location, because the effect start gives none. The command path normally supplies the TPS aim.
- UE4SS hot reload moved from Ctrl+R to **Ctrl+F11** (UE4SS-settings.ini HotReloadKey = F11). Ctrl+R is the game's ammo switch, which caused accidental reloads and likely crashes.
- v0.9g: FIRE_INTERVAL 0.11 (the skill's CoolTime), giving full auto while LMB is held.
- Ctrl+F11 triggered a video-capture shortcut (an overlay or recorder) and the reload crashed the game. UE4SS hot reload is now **Ctrl+Numpad 0** (HotReloadKey = NUM_ZERO), chosen by the user.
- v0.9h: NikkeGunMode.dll is no longer loaded (gated on CFG.NATIVE_SWITCHES = false). The 15:08 crash came right after "All mods re-installed", and the DLL is our likeliest contribution to hot-reload crashes.
- v0.9h result: holding LMB doesn't give full auto; the log shows the requests repeating (5 in 1.2 s) but not every one plays. Enemies don't react, so no damage.
- Lock-on from Lua is impossible: `ServerRequest_ActorLockOnTarget(actor, target)` and `SetAimLockOnTarget` take GUIDs, and characters expose no GUID property (StellarCoop gets GUIDs natively).
- steps_scan: EVE's Sword Aura / Tachy aura steps use TargetDetectionType TargetFilter with **UsableNonTargetProjectileTargetType = NonTarget**, so they fire a projectile with no target. The NIKKE shot has MainTarget there.
  - cmdpak2 v2 also sets ShootSlug1_1_Hit1's UsableNonTargetProjectileTargetType to NonTarget.
  - ESkillProjectileTargetType: MainTarget / NonTarget / OnePerTarget. ESkillTargetDetectionType: TargetFilter / AimLockOnTarget / AimLockOnBounds (only P_Eve_Gun_ShootMissile1_1_Hit1 uses AimLockOnBounds).

## PROJECTILES (2026-11-15 17:07)
- With Hit1 set to NonTarget, **real projectiles fire** and hit the ground (screen recording). They land up and to the left of the reticle: they follow EVE's facing, not the camera aim.
- v0.10:
  - FACE_AIM: before each shot, EVE's yaw is set toward GetTPSLookAtWorldLocation(true) via K2_SetActorRotation.
  - FULL_AUTO: the first Ctrl+LMB starts a loop that fires every 0.11 s while PlayerController:IsInputKeyDown(LeftMouseButton) and (Left|Right)Control are both down. This replaces Windows key repeat, which has a ~0.5 s delay and stutters.
- v0.10 result: **full auto works.** Shots still don't follow the reticle, even with the yaw turn.
- v0.10b logs, for the first 5 shots, the wanted yaw, the actor yaw before and after K2_SetActorRotation, the control yaw and the mesh yaw, plus the actor yaw again 60 ms later. This shows whether the TPS/cover stance overrides EVE's rotation.
- v0.10b log: K2_SetActorRotation works (actor/mesh yaw -118 → -132), but **60 ms later the actor is back at -118 = the control yaw**. In NIKKE mode the camera is fixed and the reticle moves across the screen, so the control yaw never changes and every shot flies the same way.
- v0.10c: aim hold. Each shot stores aimYaw (toward GetTPSLookAtWorldLocation) for 0.25 s, and a post-hook on CH_P_EVE_01_Blueprint_C:ReceiveTick (the same hook UPS uses) re-applies that yaw every tick while it's active, so the projectile spawns with EVE facing the aim point.
- v0.10c result: no real change. **The projectile always flies the same world direction (user: "north"), whichever way Gun Mode faces EVE.** So the effect-started shot has no direction and uses a zero rotation (world +X); EVE's facing is irrelevant.
- v0.11 theory: ServerRequest_UseSkill (tried in v0.7) may have been starting the shot all along, but Hit1 was the Item step and fired nothing without the command's bullet. With Hit1 now plain, UseSkill(1501, 44, 1007601, "P_Eve_GunNikke_ShootSlug1_2", {}, aimLoc, aimDir) should fire **toward the aim point**.
  - Default route is now "useskill"; Ctrl+Shift+G switches between useskill and the effect route.
- v0.11 result: the UseSkill route doesn't fire (the request really is rejected), and the per-tick yaw hold made EVE's animations jerky. Back on the effect route it still fires north.
- v0.11b: route "effect" by default, FACE_AIM off.
- cmdpak2 v3: Hit1 gets EVE's drone-missile targeting (P_Eve_Gun_ShootMissile1_1_Hit1, the only AimLockOnBounds step): TargetDetectionType AimLockOnBounds, AimLockOnTargetMaxCount 1, AimLockOnTargetOverlapCount 8. The hope is that enemies inside the aim reticle become targets, so the MainTarget projectile flies to them. With no target it still fires NonTarget (north).
- cmdpak2 v3 result: AimLockOnBounds did nothing (no lock-on without the command), and shots still go north with no enemy reaction.
- **ProjectileTable P_Eve_GunNikke_ShootSlug1_Projectile1:**
  - Movement: Velocity at 20000.
  - Start: StartTarget MainActor at socket **SC_GunShoot** with bStartTargetTransformRotation true, but **StartTargetRelativeAxisType = World**.
  - Destination: DestTarget **StartToDestDirection**, distance 50000, DestTargetRelativeAxisType RootAxis.
  - Other: TargetFilterAlias P_Eve_GunNikke_ShootAmmo1_Projectile_Target, LifeTime 0.5.
  - ESBProjectileTarget: MainActor, OtherActor, SetLocation, StartToDestDirection, SkillTargetLocation, InputTransform.
  - MovementTargetRelativeAxisType: World, ParentAxis, RootAxis, InputDirection.
- cmdpak2 v4 adds ProjectileTable to zNikkeGunMode_P with StartTargetRelativeAxisType → ParentAxis, so the bullet follows the muzzle socket, which points at the reticle in aim pose. SP doesn't ship ProjectileTable.
- cmdpak2 v4 result: still north. The start axis isn't what sets the flight direction.
- cmdpak2 v5: the projectile's DestTargetRelativeAxisType also changes RootAxis → ParentAxis, so StartToDestDirection is measured on the muzzle socket.
- cmdpak2 v5 result: still north. Neither projectile axis (start or destination ParentAxis) changes the direction, so the direction vector itself is zero for an effect-started skill.
- v0.12 theory: the skill's input direction is EVE's movement input (zero in Gun Mode).
  - Projectile DestTargetRelativeAxisType → InputDirection.
  - Lua INPUT_AIM: `p:AddMovementInput(horizontal dir to aim, 1.0, true)` right before each NGM_Fire.
- v0.12 result: still north. Movement input isn't the source either.
- Projectile comparison: EVE's drone bullets (P_Eve_Gun_ShootSlug1_Projectile1, ShootScatterSlug1) use the **same** StartToDestDirection + RootAxis setup. Their direction comes from the fire command's aim point/direction, which an effect-started skill never gets. That's also why the shot works in the real NIKKE stage: there the click goes through the fire command, which carries the aim.
- cmdpak2 v6: Dest = MainActor, socket SC_GunShoot, ParentAxis, DestTargetRelativeLocation X 50000 (a point far along the muzzle socket's own X). Start axis back to World. FVector zero components are stored as "+0".
- cmdpak2 v6 result: **the shot direction finally responds.** Bullets follow the gun but cluster up and to the right of the reticle, because the SC_GunShoot socket's X isn't the barrel axis.
  - One crash: an access violation (reading 0x70) inside UE4SS Lua frames, 2 s after Gun Mode ON. The mod isn't identified; it didn't recur in the next test.
  - The empty DestTargetRelativeLocation is a StructPropertyData (StructType Vector) with Value []. The fix inserts a VectorPropertyData inside it.
- v7 + Lua v0.13: Dest = MainActor at its root (Base transform, RootAxis), relative X 50000, so the point is straight ahead of EVE's body. FACE_AIM is back on: while firing (and 0.25 s after), the tick hook turns EVE's yaw to the aim point. Pitch follows the gun height for now.
- **Bullets damage enemies** (user, 18:34). Correction to v6's result: the shots are always too far right *whichever way EVE faces*, so the socket method tracks the gun with a constant offset. Measured from the video, the tracer is about 90° right of the reticle direction.
- cmdpak2 v8: back to the muzzle socket (Socket SC_GunShoot, ParentAxis) with DestTargetRelativeLocation (0, -50000, 0), i.e. the socket's −Y, 90° left of +X. If it lands ~180° off, flip to +Y. Lua v0.13b: FACE_AIM off.
- cmdpak2 v8 result: socket −Y lands too far **left** (+X was too far right). v9 uses 45° between them: relative (35355, −35355, 0).
- Observed in the v6 video: EVE is **immortal in gun stance**, likely because of the NIKKE stage rules (MaxHP100/HP100 and the stage's damage model). There's also a graphic glitch near the gun when she's attacked, probably the NIKKE hit/guard FX. Bullets register hits near their path (projectile hit radius / target filter). All to be dealt with after aim is fixed.
- v9 (45°) result: "much better", lands a little **high and left**. v10: 35° left of socket +X, slight downward tilt → relative (40958, −28679, −4000).
- Crash at 19:14 after ~320 shots during the v9 test. UE4SS.log ends normally with no Lua error, so it was a native crash. Earlier crashes in this testing were also silent. Watch whether long full-auto bursts reproduce it (possible projectile/FX buildup).
- v10 (35°, Z −4000) result: lands high and **right**. Horizontal sits between 35° and 45°. v11: 40°, Z −10000 → (38302, −32139, −10000). If height doesn't change with Z, the socket's Z isn't vertical.
- v11 (40°, Z −10000) result: low and **left**, but close. So socket Z *is* vertical. v12 splits both ranges: 37.5°, Z −7000 → (39668, −30438, −7000).
- v12 (37.5°, Z −7000) result: left-right good, "just a little bit high". v13: Z −8500.
- During the v12 test (~19:48) EVE stood up out of the gun stance by herself, with no Gun Mode OFF in the log until 19:49:17. The video shows a sword swing (blade trail) just before. Likely cause: a plain LMB (without Ctrl) or another melee input runs a sword attack, and that drops the NIKKE stance while our mod still thinks it's on. Possible fix: re-assert the stance (GunOn row) when Ctrl is held and the stance has dropped, or block melee while in Gun Mode.
- Correction (user, 19:51): the stance drop isn't a stray click. It happens when she connects with an enemy and enters combat. The game auto-draws her sword on combat entry, and that cancels the NIKKE stance. Fix idea: watch for the stance leaving P_Eve_GunNikke while Gun Mode is on and re-apply GunOn, or suppress the combat-entry sword draw.
- v13 (Z −8500) result: "a hair too low". v14: Z −8000 (final bracket between −7000 high and −8500 low).

## Aim done (2026-11-16 01:42)
- v14 (37.5°, Z −8000) result: **"fairly centered"**. Final shot destination: SC_GunShoot socket, ParentAxis, relative (39668, −30438, −8000).
- Next issues (user + video 01:39):
  - The first shot of every burst strays low-left. Likely cause: the bullet takes its direction from the muzzle socket, and on the first shot the gun hasn't risen into the shoot pose yet. Lua v0.14 waits FIRST_SHOT_DELAY (0.12 s) before the first shot; later shots are already in pose.
  - The reticle doesn't reach the far left/right of the screen (it does reach the top). Probably the NIKKE minigame's reticle/aim-offset yaw limit, which assumes a fixed cover camera. Not yet located (TPS aim-offset limits, camera volume LookAt settings, or a HUD clamp).
  - Still open: EVE immortal in the stance, the glitch near the gun when hit, the stance dropping on the auto sword draw at combat entry, and one silent crash after a long burst.

## Feature requests (user, 2026-11-16 01:51)
- **Gun ammo as a real ammo type.** The game already has the item Bullet_Nikke (we currently grant 60 on each Gun Mode entry). Wanted:
  - It drops as an enemy reward like other ammo.
  - It's sold at camp shops, and it's included in the ammo box that contains all ammo types.
  - It is **not** selectable in the ammo wheel, because Gun Mode has its own trigger.
  - Data work involved: ItemTable name/description/icon, enemy drop/reward tables, shop tables, and the ammo-box contents.
- **Ammo counter HUD:** a splash display at the top left showing the remaining gun ammo, in the ammo wheel's font, with its own new ammo icon and a backdrop that matches the wheel's style. Needs a UMG widget (likely a clone of an ammo-wheel slot) shown while in Gun Mode / on ammo change.
- **No zoom on entry.** Ctrl+G zooms the camera in on EVE before the stance starts. The user wants her whole body on screen while firing, so the NIKKE TPS camera's distance/FOV must be kept (or set) wide.
- **New triggers:**
  - Keyboard: plain **G** (to verify against the game's own key bindings first).
  - Controller: **hold R1 + press L2**. Vanilla R1 = burst skills (R1 + face buttons) and L2 = shooting mode, so L2 must not also open the drone mode while R1 is held.

## v0.15–v0.16 (2026-11-16 02:00–02:20)
- **v0.15 stance guard.** Every 0.25 s while Gun Mode is on, check GetCurrentStanceName (must contain "GunNikke"), IsTPSMode and TPSModeType==2. If any has dropped (the combat-entry sword draw), re-fire NGM_AE_GunOn + NGM_AE_Pos2, at most once per second. Each re-apply is logged ("stance guard #n: stance=…") so we can see what the sword draw switches to.
- **Zoom on entry: user correction (02:04).** The zoom isn't the NIKKE camera. Holding Ctrl (the game's TPSMode action, i.e. drone aim) before G starts the drone camera transition. A single key fixes it.
- **Key check.** The game's DefaultInput.ini (pakchunk0 .pak, extracted by ngm_input_ini.py) binds keyboard G only to UI_RightThumbstick (menus). TPSMode = LeftControl / Gamepad_LeftTrigger; TPSFire = LMB / Gamepad_RightTrigger. Gamepad R1 = BurstSkillPreCommand / BurstSkillView / WallRun / PhotomodeTwoKey2. L2 = TPSMode (+ some context keys).
- **v0.16 keys:**
  - Plain **G** toggles (Ctrl+G also works, to exit mid-aim). There's a 0.4 s debounce, and nothing happens while the mouse cursor is shown or the game is paused (G is a UI key there).
  - Controller: **hold R1 + press L2** toggles. In Gun Mode, **L2 + R2** fires full auto. Both are polled every 50 ms via IsInputKeyDown.
  - Ctrl+Shift+G (the fire-route test key) is removed.
- New tables exported to json (ngm_extract_tables3.py) for the ammo work: KeyMappingTable, KeyMappingRolloverTable, ItemTable, ShopItemTable, ShopTable, RewardGroupTable, ItemSpawnTable, DropRateAdjustTable, UIKeyImageAssetTable. The full asset path list is NikkeGunBuild\asset_list.txt (retoc manifest).

## v0.17 (2026-11-16 02:30): the stand-up isn't a stance drop
- 02:23 clip + log: the v0.15 stance guard **never fired**. Stance stayed P_Eve_GunNikke and TPSModeType stayed 2 the whole time.
  - At ~6 s an enemy dies, the sword materialises (blue lightning), she stands, then she crouches back by herself.
  - At the end she stood for good right after shot #60, i.e. the 60 rounds granted on entry ran out.
- The object dump shows CH_P_EVE_01_Blueprint overrides SBCharacter's **Event_ChangeBattleState(bIsBattle)** and has a PlayMontage node, which fits a combat start/end sword montage.
- v0.17 battle guard: post-hook on Event_ChangeBattleState. While Gun Mode is on, for 2.5 s it checks the AnimInstance's GetCurrentActiveMontage every 50 ms. Any montage whose name lacks gun/nikke/tps/shoot gets Montage_Stop(0.15) and its name is logged.
- Temporary ammo top-up: +60 Bullet_Nikke every 50 shots, until the real ammo item exists. After that, running dry should exit Gun Mode cleanly.

## v0.18 (2026-11-16 02:40): crash during long bursts
- 02:29 clip: the v0.17 battle guard worked. Battle state flipped true and then false mid-fight, and she **stayed crouched** the whole time. No montage needed stopping (none logged), so the post-hook timing alone may have been enough, or the montage was gun-named; to watch. Top-ups worked.
- But the game **crashed** after about 190 shots of continuous fire ("Fatal error!").
- Crash dumps (ngm_grab_crash.py + the minidump python package):
  - 11-16 02:29: EXCEPTION_ACCESS_VIOLATION reading 0xa at **UE4SS.dll+0x90267d**
  - 11-15 20:02: reading 0x116151749 at **UE4SS.dll+0x910e80**
  - Both are inside UE4SS itself, not the game. Common factor: several ExecuteWithDelay chains re-arming every 50–110 ms (full auto, hold, pad poll, battle).
- v0.18 removes every periodic ExecuteWithDelay chain. One post-hook on CH_P_EVE_01_Blueprint_C:ReceiveTick (engineTick) now drives, throttled by os.clock: pad poll 50 ms, full-auto fireStep (nextShot timing, first-shot delay), hold/stance guard 50 ms, battle-montage check 50 ms. The +150 ms per-shot diagnostic delay is also gone. ExecuteWithDelay is now only used for one-offs (verify, drone repair).
- Runner gotcha: device_commit_files wrote a stale job.txt once (it ran ngm_missile_step.py). Verify job_done.txt names the intended script.

## v0.19 (2026-11-16 02:50)
- v0.18 result (02:39 controller clip): **no crash** after 380+ shots over about 55 s, so the central tick fixed it.
- Remaining issues from the clip:
  - The R1+L2 toggle zooms a little (L2 = TPSMode, the drone aim).
  - A stray shot goes off to the bottom left.
  - The sword still flashed out once, at battle state → false (02:38:59). The guard logged no montage stop, so it's either not a montage or its name passed the gun filter.
  - The reticle gets lost in the muzzle flash.
- v0.19 changes:
  - **Controller toggle is now hold L1 + tap D-pad Right** (user's choice). L1 = Guard / BetaSkillPreCommand; D-pad Right = CrossKey_Right only. It doesn't overlap UPS's RB + D-pad. Selected with CFG.PAD_COMBO ("R1+L2" is still available).
  - **AIM_READY 0.35 s:** the first shot waits until the aim key (Ctrl/L2) has been held that long, plus FIRST_SHOT_DELAY. Pressing L2+R2 together fired before the gun was up.
  - **Reticle ×1.6:** SetRenderScale on WB_NikkeHUD_Aim_C / WB_Tps_Aim_C instances 0.8 s after entry, reset to 1.0 on exit.
  - The battle guard now logs every montage name seen during its window.
- Found for later: DLC_2 widgets WB_NikkeHUD_Clip (the NIKKE magazine counter), WB_NikkeHUD_Reload and WB_NikkeHUD_Aim. These are candidates for the ammo display.
- 02:45 the user picked **plain D-pad Right** instead (no gameplay action in-game). CFG.PAD_COMBO = "DPadRight", ignored while R1 is held so it never fires together with UPS's RB + D-pad. Same 0.4 s debounce and menu/pause guard as G.
- Ammo HUD idea (user, 02:46, screenshot): add a slot to the **bottom-left quick-slot HUD**, which has the potion count above the D-pad cross and the item count below. Put the gun icon + Gun Mode ammo count on the cross's right side, matching the D-pad Right trigger. Replaces the earlier "splash at the top left" plan.
- Ammo HUD layout (user screenshot, 02:46, drone aim): the bottom-left column is a vertical stack.
  - Top: the drone weapon icon in an orange arc.
  - Then: potion slot (count), then the D-pad cross.
  - Bottom: the item slot, which **swaps to the current ammo icon + count (Stinger 32) while aiming**.
  - The right-side drone reticle shows the same ammo ("32 / R2 / Stinger").
- Plan: in Gun Mode the bottom slot shows the NIKKE ammo icon + count, in the same widget style (same column, font and number placement), not a new floating panel. Next step: find the quick-slot widget (WB_MainHUD_* / TPS bullet slot data: TPSBulletSlotData, TPSBulletGroupData, WB_Tps_Bullet2_Slot) and how it gets the ammo icon and count.

## v0.20 + research (2026-11-16 03:00)
- User: D-pad Right and the 1.6× reticle are good. New request: **the laser sight line also needs to be stronger**, because it gets lost in the gunfire.
- v0.20 laser diagnostic: 1.5 s after entry, logs every Niagara/Particle/SplineMesh/StaticMesh component owned by EVE or her attached actors (name, visible, asset). That should identify the laser so it can be widened/brightened (SetWorldScale3D / Niagara float params / material params).
- Sword flash: the v0.19 montage logger saw **no montage at all** during the battle windows (GetCurrentActiveMontage nil), so the battle-state sword isn't a montage. Candidate fix from NikkeStageTable: the real stage applies **PeacefulMode_Infinite** at start. That may be what keeps battle state from changing in the stage; it needs an EffectTable lookup (and its dispel) before trying.
- Reticle edges: no clamp in ItemBulletTable (Bullet_Nikke has TPS_ControllerYaw/PitchDegree 1.5, aim-slowdown settings). The reticle's screen position is SBCharacter::NikkeTPSPinScreenPoint (offset 0x159C, Vector2D). ngm_ghidra_reticle.py (NikkeOffsetScan.java) scans the exe for code using 0x159C / 0x15A0 to find the clamp.
- Ammo item research (json exported):
  - ItemTable already has **Bullet_Nikke** (ID 37, Category Bullet, IncludeDropPool true, AblePrice true). Its Name/Desc are None, so it needs ItemStringTable keys (Local/Localize/ItemStringTable). It reuses the slug ammo icon bullet_icon_01 and the BP_Item_ammo_slug pickup mesh.
  - Camp shop: Camp_Bullet_*_Buy rows (CheckConditionGroup CG_TPSMode_Opened); Normal costs 15 betacrystal, Missile 30. The ammo box is Bullet_Package_Dummy (Camp_Bullet_Package_Dummy_Buy, category BulletPackage, "Item_BuyAllAmmo"). Most likely the game buys every bullet sold in that shop, so a Camp_Bullet_Nikke_Buy row should be included automatically.
  - Drops: RewardGroupTable bullet groups subGroup_global_Normal(3)_Bullet, subGroup_FA_*_Bullet, subGroup_b_standard_*, subGroup_b_destruct_Bullet, Raven, LockedBox. Add a Bullet_Nikke row to each, with weights similar to Bullet_Normal.
- v0.20 diag result: EVE and her attached actors own only one StaticMeshComponent (AssistanceSlot), so the laser is spawned elsewhere. v0.20b also logs every *active* Niagara/Particle/SplineMesh component within 30 m, with its owner.
- v0.20b diag result: **the laser is NiagaraComponent NS_A_GuideLaser** (/Game/DLC_2/Art/FX/MiniGame/NS_A_GuideLaser), a pooled component owned by WorldSettings, not EVE.
- v0.21: while in Gun Mode, find the active NS_A_GuideLaser component (FindAllOf at most every 2 s until found, then cached) and SetWorldScale3D(LASER_SCALE = 2.5), checked every 0.5 s from the central tick. This is a first try; whether component scale widens the beam depends on the system. ngm_extract_laser.py (queued behind the Ghidra scan) exports the system to json to find its user parameters (width/colour) for a proper fix.
- **v0.21 crashed the game within 0.7 s of entering Gun Mode.** The log stops right after "Gun Mode ON requested", before the verify line. The likely cause is laserStep's first run, which did FindAllOf("NiagaraComponent") + .Asset reads (+ SetWorldScale3D) *inside the ReceiveTick hook*. The v0.20b diag did the same FindAllOf from ExecuteInGameThread without trouble.
- v0.21b: LASER_SCALE = 1.0 (off). Rule from now on: no object-array walks inside the tick hook. For the laser, wait for the NS_A_GuideLaser json (user params), then set a parameter once from a one-shot game-thread call.
- **Laser asset analysis** (ngm_extract_laser*.py):
  - NS_A_GuideLaser (DLC_2/Art/FX/Minigame, note the lowercase "g") has user params StartPos, EndPos, FadeDistanceNear, FadeDistanceFar and SceneDepthOffset. There's **no width/colour param**.
  - Emitters: BeamCenter (ribbon, MI_A_RibbonDefault_01) + 2 sprite emitters. The width is baked into the compiled VM (ScriptLiterals 1, 3, 6, 2, 1, 5).
  - NC_NikkeMinigame only has LaserPosition.
  - The enemy version Art/FX/Char/Monster/BotRange/NS_A_GuideLaser has the **same user params** plus a lens-flare and two extra sprite emitters, and an extra literal 4.0.
- v0.22: 1.5 s and 4 s after entry, a one-shot game-thread call does LoadAsset/StaticFindObject on the BotRange laser and SetAsset()s every NIKKE guide-laser component to it. The originals are restored on exit. If the look isn't strong enough, the fallback is patching the BeamCenter ScriptLiterals in a pak copy of the NIKKE laser.
- Ghidra reticle scan finished (1683 s): 42 functions use 0x159C/0x15A0, too common a constant to pinpoint the clamp quickly. Parked (user: the edge limit may not be worth it because of EVE's aim animation).
- v0.22 result: the laser "looks the same". The log has **no laser-swap line at all**, so the 1.5 s / 4 s searches found no guide-laser component. It only exists while aiming (the v0.20b diag found it because the user was aiming).
- v0.22b: on each aim press (Ctrl/L2 rising edge, detected in padTick), queue a one-shot laserSwap 0.3 s later via ExecuteWithDelay → ExecuteInGameThread. The first 5 attempts are logged even if they find nothing.
- User report 03:41: their CNS outfit (Muse Catsuit) was reset. Log: CNS loaded MuseCatsuit_muse_catsuit at startup (03:40:01). There are no CNS/outfit lines during Gun Mode (03:40:14–03:40:52); the user re-selected it at 03:41:34. The MuseCatsuit pak hasn't changed since 11-15 19:54. Cause unknown; asked the user when it happened.
- v0.22b result: still "looks the same". The swap ran on aim, at 1.5 s and at 4 s, and found **0** lasers every time. User: the CNS outfit was reverted on the **last 2 loads**.
- v0.22c: the swap now logs how many Niagara components it scanned and every component whose asset contains "GuideLaser" (path, active), matches the path case-insensitively, and retries at 0.3 / 0.9 / 1.8 s after each aim press.
- User (03:48): edit a copy of the laser file instead.
- cmdpak2 v11: zNikkeGunMode_P now also carries a patched **DLC_2/Art/FX/Minigame/NS_A_GuideLaser**. In every NiagaraDataInterfaceColorCurve ("Scale Color"), the cooked ShaderLUT (RGBA per sample, all 1.0) has RGB × LASER_GAIN 6, so the beam renders HDR-bright (bloom) with the same shape and alpha. Width is still baked into the VM literals; that's a follow-up if brightness isn't enough. Lua v0.23: LASER_SWAP off.

## 2026-11-16 08:00 — v0.24, stance findings, laptop handoff
- cmdpak2 v11 built OK: 1431 laser colour-LUT entries ×6, NS_A_GuideLaser in zNikkeGunMode_P.
- CharacterStanceTable:
  - **P_Eve_GunNikke** (aim) requires effect P_Eve_GunNikke, *no* P_Eve_GunNikke_BulletZero / _Block, and **PressCommandKey1 = TPSMode** (the aim key held). Walk 120.
  - Otherwise she's in **P_Eve_GunNikkeHide** (crouch, walk 150 / run 500, bForceFoldingWeapon).
  - Both stances' command arrays hold P_Eve_GunNikke_Evade1_1..4 (IDs 1007605-08) + BurstSkill1-3.
- EventActorEffectTable rows decoded:
  - GunOn = P_Eve_GunNikke
  - Pos2 = **P_Eve_GunNikke_Position2** (cover position)
  - MaxHP / HP = P_Eve_GunNikke_MaxHP100 / HP100 (the immortality)
  - Beta = MaxBetaGauge100
  - Ammo = BurstSkillReloadCompleted
  - Reload = ReloadStartDelay
  - Each has a matching *_Dispel row.
- Lua v0.24:
  - NIKKE_HP=false (no HP rows).
  - LOCK_POSITION=false (no Position2, so she should be able to move).
  - REAL_AMMO: tracks Bullet_Nikke via post-hooks on ClientBroadcast_ItemBucketItemAdd/Update (SBItemInstance.ItemAlias/ItemCount), spends one per shot with ServerRequest_ItemBucketItemRemove(1, guid, alias, 1, 0), and leaves Gun Mode at 0. A one-time starter of 60 is granted per session if she has none.
  - **Untested.**
- Mod pak scan (ngm_mod_tables.py): Survival Protocol's RoguelikeMode_P carries ItemTable + Localize/ItemStringTable (+ StringTable_UI, EffectTable, EAE, EIA, ...). ShopItemTable / ShopTable / RewardGroupTable aren't in any mod pak.
- New user requests (08:00):
  - Reposition, turn the camera and roll-evade while in Gun Mode.
  - Research a full third-person-shooter mode (Gears/RE-style standing/run/strafe with the gun).
  - Testing moves to the **laptop**: HANDOFF.md + HANDOFF_NikkeGunMode_2026-11-16.zip (only the run/test/rebuild essentials; json is re-created on the laptop by ngm_laptop_setup.py).

## 2026-11-16 15:14–17:40: new Ghidra project (build 26123051), reticle edges, v0.25
- The user supplied MotherSphere's current Ghidra project. It is extracted next to the old one: `Modding Tools\ghidra_sb\StellarBlade-26123051.gpr/.rep` (Steam build 26123051, Ghidra 12.1.2; opens read-only in C:\Tools\ghidra 12.2, owner mothersphere). The old StellarBlade.gpr is untouched. All new runner jobs (`ngm_ghidra26*.py`) use `NAME="StellarBlade-26123051"`.
- One headless run takes about 10 min just to open the 3.2 GB db. Batch several post-scripts into one run.
- **Reticle edge limit found: FUN_142119410** computes SBCharacter::NikkeTPSPinScreenPoint (+0x159C). It clamps the pin's X to a centred box of a *reference aspect*:
  - When the player camera (FUN_142321b70) has its constrain bits (+0x274 & 3), the reference is that camera's AspectRatio (+0x270).
  - Otherwise it is `int(W) / int(H)`, an **integer division**: 2560/1068 gives 2, 1920/1080 gives 1.
  - Screen aspect = W/H (FUN_142357440). If ref < screen, margin = (W − H·ref)/2 + TPS_Nikke_PinScreenMargin per side (≈212 px each side on 2560×1068; 420 px on 1920×1080).
- Named constants: FUN_141a986c0 is a singleton (built by FUN_142621100). It is a hash map keyed by a case-insensitive CRC of the wide name (FUN_1426234d0 lookup). FUN_1425d9510 registers every TPS_* constant with a hard-coded default:
  - TPS_Nikke_PinScreenMargin = **7.0**
  - TPS_Nikke_PinLocationOffset = 300.0
  - TPS_Nikke_ControllerPitch/YawPower = 0.01
  - …
  - FUN_1426219d0 then reads `.dat` files under Local/Default/Config (DistVer / TimeStamps), probably the shipped override. NikkeGunBuild\ghidra26c_out.txt lists all ~100 TPS_ names with their users. DefaultGame.ini has none of them.
- **Lua v0.25 `WIDE_RETICLE`**:
  - On Gun Mode entry (0.9 s in), every SBCameraComponent/CameraComponent owned by EVE or the PlayerCameraManager gets `AspectRatio = screen W/H` (from GameUserSettings:GetScreenResolution, or CFG.SCREEN_ASPECT) and `bConstrainAspectRatio = true`, so the reference equals the screen and the box is the whole screen.
  - The originals are restored on exit. It logs `wide reticle:` lines with the old values.
  - **Untested.** Installed on the PC (ngm_install25.py, backup main.lua.v024.bak). Laptop copy: `S:\Workspace\NikkeGunMode_update_v025\` (main.lua + README.txt).

## 2026-11-16 19:10 — v0.59 (laptop) failed on the desktop → v0.60
- Laptop v0.59 + cmdpak3 v12 + sp10 installed on the desktop (md5 OK). Schizo, 19:00: no roll, no camera turn, no ammo count, stuck in Gun Mode.
- Log findings:
  - LOCK_POSITION=true (centre cover) pinned EVE and the camera.
  - The standing roll was logged but didn't happen.
  - The 60 starter rounds were spent within ~2 min. After that every entry was dropped by EmptyExit within ~2 s.
  - An ON→OFF 1.6 s apart left the NIKKE stance on. After that G produced no log line at all (inMenu or similar).
- Lua v0.60 (desktop):
  - LOCK_POSITION=false. The guard re-applies only GunOn. Evade re-centre only with LOCK_POSITION.
  - The roll is tried from both NIKKE stances, with a +250 ms skill/stance diag.
  - OFF rows are re-sent at +1.2 s and +3 s.
  - G always forces the exit rows when Gun Mode is off but the NIKKE stance is still on. Blocked toggles are now logged.
  - Gun Mode won't start once the bag ran dry, until rounds arrive (Ctrl+F12 / item broadcast > 0 / map change).
  - Installed with the v0.59 paks. Untested.

## 2026-11-16 19:40–20:05: standing / crouched Gun Mode (v0.61 + zNikkeGunStance_P)
- Schizo's design (19:37):
  - **Standing** gun mode by default: aim upper body, upright legs with walk / sidestep / back-pedal.
  - **Crouched** = the standard NIKKE mode (crouch + dash roll), toggled with R3. The keyboard key was left to Claude.
  - The HUD must stay visible.
- v0.60 log: both rolls were sent but `skill running=false`. SkillCommandTable P_Eve_GunNikke_Evade1_1..4 need an active cover position: CheckActiveEffectAliasArray Position1 / Position2 (1_2 dir 0–180°, 1_3 dir 180–360°) / Position3. **Rolls only exist in cover = crouched mode.**
- **CharacterStanceTable has separate AnimSet_*_UpperBody / _LowerBody per stance.** So the standing pose needs no anim-blueprint work.
  - P_Eve_GunNikke's lower body was swapped to **P_Eve_Gun_Battle** (the drone-aim stance's lower body, which walks and strafes). The upper body stays P_Eve_GunNikke.
- The table is cooked with **unversioned properties**, which is why UAssetGUI can't write it. ngm_build_stancepak.py patches the .uexp in place: in the run of 6 FNames (Peaceful U/L, Battle U/L, Groggy U/L) for the GunNikke row, the 2nd and 4th values go 1779 → 1762. That's checked against the Hide row's layout.
  - The result goes into its **own container `zNikkeGunStance_P`**, because the laptop's v12 zNikkeGunMode_P can't be unpacked here (retoc to-legacy: 6 failed).
- Free keys:
  - In DefaultInput.ini, B / N / O / Y / CapsLock are unbound.
  - Mods use B (SP sounds, coop menu), N (DekCNS UI, coop menu), O (SP hazards) and Ctrl+Y (SplitScreen).
  - **Caps Lock** = crouch toggle. R3 also = ToggleLockOn in the base game.
- Lua v0.61:
  - STANDING by default. The aim stance is held without Ctrl via `ServerRequest_ActorStancePressCommandKey(guid, FName(v), true)`, probing v = P_Eve_GunNikke / SkillCommandState_TPSMode / TPSMode and logging which works. It is re-asserted every 0.5 s.
  - In standing mode, LMB / R2 alone fires.
  - R3 / Caps Lock: crouched = key released + Position2 (NIKKE cover, game rolls, evade re-centre) ↔ standing = PosOff + key held.
  - KEEP_HUD snapshots the root widgets on screen before entry and re-shows any Gun Mode hides, with a log line for each.
  - STAND_EVADE is off.

## 2026-11-16 20:05–20:40: v0.62–v0.65 (tested by Claude on the PC with computer use)
- v0.61 standing via the stance-table leg swap gave a **twisted pose** (Schizo's clip). The NIKKE upper body is authored side-on and kneeling, so it doesn't work on upright legs. zNikkeGunStance_P was moved to `NikkeGunBuild\stancepak_off`. A real standing mode needs new animations (FModel → Blender → UE 4.26 SBOutfitProject).
- `ServerRequest_ActorStancePressCommandKey` with P_Eve_GunNikke / SkillCommandState_TPSMode / TPSMode did nothing (the aim stance never came up).
- **HUD (v0.62):** the NIKKE mode hides children of WB_MainHUD_Master: Canvas_HUD/Overlay_EnemyInfo, Overlay_Interaction, Overlay_Skill (+ WB_MainHUD_Skill) go vis 4 → 2/1, and Overlay_ItemSlot goes to opacity 0.30. They are restored on entry and re-checked every 1.5 s (Overlay_Peace_Skill fades again).
- **Crouch key:** R3 / Caps Lock / **Y** (v0.63). Y was added because the test tooling can't send Caps Lock, and plain Y is free.
- **Rolls (v0.64/65):** the NIKKE side rolls (Evade1_x) need Position1/2/3 **and** a target (bCheckTargetExists, P_Eve_GunNikke_Evade1_x_Target). In the open world they never start, even in cover.
  - ROLL_SWAP: on Shift/Circle, lift the gun (NGM_AE_GunOff + PosOff), let the game's own evade input run (P_Eve_Default, skill running=true), then re-fire all ON_ROWS after 0.9 s.
  - Re-firing GunOn alone left IsTPSMode=false, and then the empty-bag check ended Gun Mode.
  - Tested: 4 rolls standing and crouched, Gun Mode stays on, IsTPSMode=true after each.
- The SP pak can't be rebuilt on the PC. The laptop's EAE patch (EmptyExit / GunOnAmmo / RealAmmo / Cond rows) isn't here, and retoc can't unpack the laptop-built zen containers (toc version DirectoryIndex vs global PartitionSize).

## 2026-11-16 22:20–23:00: standing-pose animation groundwork (stopped)
- FModel export (Export Session queue → Export): DLC_2 CH_P_EVE_01/Animation (47: NIKKE aim/hide/evade/reload, Aim/*, Cinema), base P_Eve_Gun_* (32: drone-aim walks F/B/L/R/diagonals, idle), CH_P_EVE_01_Body.uemodel, and blend-space JSON. Copied to NikkeGunBuild\anim_export.
- **P_Eve_GunNikke_BS has a single sample, P_Eve_GunNikke_Shoot_Idle** (likewise GunNikkeHide_BS → P_Eve_GunNikke_Hide), so the NIKKE stances slide a static pose. P_Eve_Gun_BS (drone aim) has 17 samples: WalkFw/Bw/Lw/Rw at ±0.25/0.625/1, diagonals FRw/BLw, Normal_Idle at centre.
- Plan: in Blender, build standing-aim anims (drone-aim walk lower body + NIKKE upper body, with the chest re-aligned in armature space). In SBOutfitProject (UE 4.26, which has the CH_P_EVE_01_Skeleton stand-in, headless like evie_build_hair13.py), import them and rebuild P_Eve_GunNikke_BS with 9–17 samples at the same path, cook, retoc.
- **Blocked:** FModel now writes UEFormat **v10**. The installed Blender add-on (io_scene_ueformat, user_default extension) only reads older versions. UEFormat 0.10.0 from GitHub reads v10, but replacing or loading it needs Schizo's OK (two attempts were refused by the permission check). Alternatives: Schizo updates the add-on in Blender, or FModel exports ActorX (.psk/.psa) with a PSK/PSA importer add-on.

## 11-17 — standing animations into the game, take 1/2; v0.66

**Pipeline that works (ngm_build_stand.py → ngm_build_stand2.py):**
- Blender: compose in ngm_bl_build_stand3.py, then ngm_bl_export_stand2.py.
  - Re-import the body with UE Format sockets OFF (203 bones), rename the armature to "Armature".
  - Work in centimetres: scene unit 0.01, armature x100 + transform_apply, every pose-bone location key x100.
  - FBX via OutfitWork\sbfbx_5, FBX_SCALE_NONE, 30 fps (game anims are 30 fps: 35 frames = 1.1333 s).
- UE 4.26 (ngm_ue_stand.py): import onto the CH_P_EVE_01_Skeleton stand-in, convert_scene_unit=False.
  - Gate: Bip001 local translation must be about 98 cm.
  - Two dead ends: import_uniform_scale does NOT reach bone tracks (the root node is dropped), and Blender FBX_SCALE_UNITS + convert_scene_unit changed nothing.
- **The stand-in skeleton is not the game's.** It has 324 bones in its own order and a different GUID; the game's CH_P_EVE_01_Skeleton has 3765 bones. The orders agree only for the first 26 bones.
  - Cooked anims index bones by skeleton index, so every cooked anim is remapped by bone NAME, using the skeleton dumps from cue_loose (this cook) and cue_json (paks).
  - Two places hold indices: the TrackToSkeletonMapTable property, edited via UAssetGUI json, and the compressed track table plus SkeletonGuid in the native Extras bytes.
  - Gate: read back with cue_loose; every track must name a game bone.
- **Blend space:** the vanilla P_Eve_Gun_BS (17 samples, LeftRight/FrontBack, same axes as P_Eve_GunNikke_BS) is retargeted by json: sample paths swapped, package renamed.
  - Its 6 SBAnimNotify_FootStep imports must be dropped. They are the tail of the import table, so nothing else moves. Without that, retoc fails with "Failed to find export … sbanimnotify_footstep_5".
- UAssetGUI (mapping "StellarBlade_1.1.0 (1)") round-trips CharacterAnimSetTable (uexp identical). CharacterStanceTable still writes nothing.

**What the tables say:**
- CharacterAnimSetTable row P_Eve_GunNikke: RunBlendSpace / RunTiltBlendSpace / LockOnRunBlendSpace = "Animation/BlendSpace/P_Eve_GunNikke_BS" (relative path), IdleAnimType Battle.
- Stances:
  - P_Eve_GunNikkeHide (priority 5, no conditions) is the kneel/cover that G lands in.
  - P_Eve_GunNikke (priority 15) needs effect P_Eve_GunNikke, none of BulletZero/Block, and PressCommandKey1 = SkillCommandState_TPSMode, i.e. aim held.
- `ServerRequest_ActorStancePressCommandKey(guid, "SkillCommandState_TPSMode", true)` DID bring up the aim stance once the NIKKE effect was on (11-17 08:49). It failed when sent 0.7 s after entry. v0.66 uses that variant from the start, with the 0.5 s keep-alive.

**Take 1 in game (11-17):**
- Lock-on walks plus a leaned NIKKE chest, replacing P_Eve_GunNikke_BS: the torso bent back, legs crossed, and the crouched aim was lost too. The pak was pulled (NikkeGunBuild\standpak_off).
- Take 2 (stand3): drone gun walks as the body, the NIKKE neck-and-below in the NIKKE chest facing, half the neck correction in the chest.
  - Its own NGM_Stand_BS plus an animset row NGM_Stand (ID 596102) in a patched CharacterAnimSetTable, so vanilla P_Eve_GunNikke_BS is untouched.
  - Built and gated, not installed yet.
- **Crash:** a second roll started about 0.3 s after the roll-back re-fired the entry rows. v0.66 adds ROLL_COOLDOWN 1.2 s.

**v0.66 tests pending:**
- SBCharacter:ActiveCustomMovingStanceData(SBCharMovingStanceData{OverrideStanceAnim = animset name}) while standing (STAND_OVERRIDE, test value P_Eve_Gun_Battle). If it overrides the locomotion animset, standing = override "NGM_Stand", crouch = override off.
- MOVE_DIAG logs velocity-vs-actor and actor-vs-camera yaw while moving, which gives the blend-space axis mapping.

## 11-17 09:20 test of v0.66 → v0.67
- **ActiveCustomMovingStanceData works.** With OverrideStanceAnim = P_Eve_Gun_Battle the log shows call ok, IsActiveCustomMovingStanceData = true, stance P_Eve_GunNikkeHide, and in game she walked with the drone gun body. The override replaces the locomotion animset whatever the stance.
- **Move diag in the Hide stance:** A → velocity −90° from the actor, D → +90°, S → 180°. This is strafing, so the blend space's LeftRight/FrontBack are actor-relative, as in any TPS.
  - Actor vs camera started at 0. After the normal-evade roll it stayed at 85–90°, because the NIKKE stances don't turn the actor with the camera. That's the "random position after dash" and "doesn't rotate with camera".
- The aim keep-alive (repeated press=true) never brought the P_Eve_GunNikke stance up, so fire was cancelled by the crash guard. Firing in Hide = folded gun = null muzzle socket crash.
- **v0.67:**
  - standing uses override NGM_Stand (take-2 anims, zNikkeGunStand_P installed);
  - the actor yaw is set to the control yaw every tick while standing (STAND_FACE_CAMERA);
  - the aim keep-alive sends release then press, the edge that worked at 08:49, and logs the result ("aim keep #n").

## 11-17 10:45: standing works (v0.69b + zNikkeGunStand_P take 4/5), self-tested on the desktop
**What works now (tested by Claude in game):**
- G puts Eve straight into standing with the rifle up.
- She walks and strafes on the standing blend space with no crash.
- LMB fires while standing: muzzle flash, rounds go to the reticle, and she stays standing with the new P_Eve_GunNikke_Shoot.
- Y/R3/Caps Lock goes to the NIKKE kneel and back.
- Dodge roll works.

**How:**
- **Stance table, row P_Eve_GunNikkeHide** (the cover stance G lands in; no conditions; it is the stance the game uses with the NIKKE effect and no aim key). Unversioned binary patch, read back with UAssetGUI:
  - bForceFoldingWeapon → zero: mask bit, 1 byte out, so the gun is out and the muzzle socket exists for the shot.
  - AnimSet_{Peaceful,Battle}_{Upper,Lower} → P_Eve_GunNikke: FName swap, so it uses the standing blend space.
  - bDisableMovingTransit → true: mask bit cleared, 1 byte in. Without it, moving froze and crashed the game (10:24), because the P_Eve_GunNikke animset has no start/stop transition anims.
  - Net size is unchanged.
- **P_Eve_GunNikke_BS** at the vanilla path carries the stand3 anims (drone gun walks plus the NIKKE neck-up).
- **P_Eve_GunNikke_Shoot** (DLC_2 path) is replaced by NGM_Stand_Shoot: NIKKE recoil on the drone idle legs, 15 frames. The ShootSlug shows play it full body, and there are no notifies; the projectile comes from SBShowProjectileKey.
- **Crouch:** ActiveCustomMovingStanceData OverrideStanceAnim = P_Eve_GunNikkeHide while crouched (kneel animset), off while standing.
- **Fire guard:** firing is allowed in P_Eve_GunNikkeHide while standing (FIRE_IN_COVER_STANCE), because the gun is no longer folded.
- **Facing:** the actor yaw follows the control yaw every tick (STAND_FACE_CAMERA). Move diag: actor vs camera about 5°.

**Dead ends this morning:**
- **Aim stance P_Eve_GunNikke:**
  - Zeroing both the key condition and bActiveCheck makes it unreachable, even with real Ctrl. Stances with a key condition are entered on key events.
  - Zeroing only bActiveCheck means Ctrl enters it and it then stays after release, but nothing from Lua can enter it.
  - Lua routes that changed nothing: ServerRequest_ActorStancePressCommandKey (stance alias, Hide alias, SkillCommandState_TPSMode, taps), ClientBroadcast_ActorSetStance, ConsoleCommand / constructed SBCheatManager SBPlayerChangeStance. One of the later taps preceded a crash (10:17).
- **Animset row added to CharacterAnimSetTable + new-path NGM_Stand_BS:** the BS never loaded (LoadAsset nil), and an override to the new row crashed the game (09:31).
- The camp blocks gun skills (BlockSkill), so test in the open.
- `device_commit_files` can silently write stale content. Lua now goes through `ngm_main_<md5>.lua` plus `ngm_put_lua_<md5>.py`, which copies it and verifies the md5.
- The crash reporter (crs-handler) can't be clicked from the tools; ngm_kill_crs.py closes it, which is the same as Don't report.

**Testing settings still on in v0.69b:** REAL_AMMO = false (unlimited) and MOVE_DIAG on.

**Open items:**
- Camera after a roll comes in close behind her: check whether that's just her position.
- Aim offset (pitch) while standing.
- Crouch moves at the cover run speed of 500.
- The shoot replacement also applies to the NIKKE missions.

## 11-17 (take 4): Mixamo rifle locomotion + standing look (v0.70)
- Take 3 (drone legs + NIKKE kneel-cover arms) looked scrunched. Replaced by the Mixamo "Rifle 8-Way Locomotion Pack"
  (free, Schizo's Adobe account, 49 FBX clips incl. a crouch set) retargeted in Blender: runner_jobs/ngm_bl_mixamo_stand.py.
  - World-space rotation deltas per mapped bone (mixamorig -> Bip001), calibrated so Eve's bind-pose bone directions match
    the Mixamo T-pose; FK done in Python (fast, no depsgraph updates); forward travel removed (in place).
  - Feminine fix (Schizo, 11:58: X Bot pelvis tucks her butt away, too masculine): pelvis tilted forward 14 deg, hips raised
    by half the clip's crouch with two-bone leg IK (feet kept), feet pulled 30% toward the centre line. Env knobs
    NGM_PELVIS_TILT / NGM_HIP_RAISE / NGM_NARROW.
  - Gun props: NIKKE right-hand grip, turned so the barrel runs right hand -> left hand.
  - First in-game test (v0.69b Lua): upright, walks/strafes/fires; one crash a few seconds in (cause not read).
- Camera: the NIKKE stances send the mouse to the reticle and keep the camera fixed, so in standing mode nothing turned it.
  v0.70 STAND_LOOK reads MouseX/MouseY / Gamepad_RightX/Y (GetInputAxisKeyValue) and sets the control rotation itself when
  the game didn't move it that tick; resets IgnoreLookInput; logs "look diag" (control vs camera-manager rotation).
- Build: ngm_build_stand6.py = stand5 + NGM_STAND_BLEND_SRC (stand4\NGM_Stand4.blend).
- **v0.70d (11-17 12:50) - working standing TPS, self-tested:**
  - Camera: Lua sets SBCharacter.TPSModeType 2 -> 0 while standing (plain property write works; tps probe lists
    TPSMode/bTPSMode/TPSModeType/TPSLookAtDirection...). Mode 0 = the drone-aim TPS camera: the game itself turns camera
    and EVE with the mouse; the NIKKE stance (P_Eve_GunNikkeHide), firing and the stand anims all keep working. Back to 2
    for crouch (NIKKE cover) and on exit. In mode 2 the camera is locked and drags the control rotation back every frame
    (our SetControlRotation got undone within a frame; mouse is only readable via pawn:GetInputAxisValue("Turn"/"LookUp")).
  - Crashes (3x, EXCEPTION_ACCESS_VIOLATION inside UE4SS converting UFunction params from Lua, inside EVE's ReceiveTick
    hook): the per-tick K2_SetActorRotation (faceCamera) / SetControlRotation (standLook) calls. With mode 0 both are off
    (fallback only if the mode switch fails). valid() is pcall'd and the tick skips 2 s when the controller/pawn go invalid.
  - Butt/feminine (Schizo: "butt tucked in and disappears", "too masculine"): the cause was Mixamo's (male) LEG motion, not
    the pelvis tilt alone (measured: X Bot pelvis -1..-10 deg back, Eve's gun walk +10 fwd; a +14 deg fix didn't help).
    ngm_bl_mixamo_stand5.py = hybrid: pelvis + legs + hip height + all helper/corrective bones from Eve's own drone gun
    walks (P_Eve_Gun_Walk*w / Normal_Idle, yaw aligned -270, 39-frame cycles), spine/arms/head/rifle hold from Mixamo.
  - Tooling: device_commit_files reusing the same staged job.txt path can deliver the OLD content (re-ran a build job twice,
    which looked like the game "restarting itself"). Use a unique staged name per job file.
  - Open: Y crouch didn't toggle in the self-test; camera is the close drone-aim shoulder view; REAL_AMMO false (test).
- **v0.70p (11-17 15:00)**: aim = live ProjectileTable row (FindRow works; Dest switched to the drone shot's Base/RootAxis
  frame, rel. location written per shot -> bullets land on the screen centre, pitch included, confirmed). Laser sight =
  NS_A_GuideLaser attached once to FollowCamera (per-frame steering crashed). Aim offset: our 9 rifle poses
  (NGM_Stand_Aim_*, local-space additive on NGM_Stand_Aim_Base) replace the samples of Aim_BS (aimbs build step; Aim_BS
  is shared with the drone stance P_Eve_Gun_Battle). Rifle stays upright in game although SC_WeaponConstraint/Prop1 match
  the NIKKE shot - not an anim issue, cause open (weapon fold/aim IK state). Camera: CameraBoom.CustomOffset / SocketOffset
  are writable (SBSpringArmComponent). Crashes: world-wide FindAllOf over components + calls on them crash UE4SS (gun
  probe 14:51/15:00) - only ever touch EVE's own objects.
