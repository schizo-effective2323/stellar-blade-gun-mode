# Stellar Blade Gun Mode (NikkeGunMode)

A UE4SS mod that brings the NIKKE collab's **Gun Mode** out of the DLC stages and into normal Stellar Blade gameplay,
reworked into a standing third-person shooter: free camera, crosshair aiming, rifle locomotion that keeps EVE's own
walk, and the NIKKE kneeling cover as a crouch.

Status: **in development** (v0.70). See [docs/RESEARCH_LOG.md](docs/RESEARCH_LOG.md) for the full history and findings.

## What works

- **G** (or D-pad Right) toggles Gun Mode, standing. **Y** / Caps Lock / R3 = crouch (NIKKE cover). LMB / R2 fires.
- Free mouse/stick camera while standing (the game's TPS mode is switched from NIKKE's fixed camera to the drone-aim one).
- Bullets fly to the screen centre, pitch included (the shot's projectile row is aimed at the crosshair point per shot).
- Standing animations: EVE's own legs, hips and corrective bones from her gun walks + a Mixamo rifle upper body
  (`tools/blender/retarget_mixamo_stand.py`), rifle aim offset (`NGM_Stand_Aim_*` in `Aim_BS`), recoil.

## Open work (good places to help)

- The rifle is still held upright in game (weapon fold / TPS aim IK state, not the animation).
- Reticle while standing (the HUD's TPS reticle only shows in the game's aim state).
- Over-the-shoulder camera framing (`CameraBoom.CustomOffset` is writable from Lua).
- Co-op: how a partner sees this through Stellar Blade Online (SBO).
- Crash hardening: never run world-wide `FindAllOf` over components from a tick; see the log.

## Layout

| Path | What |
|---|---|
| `mod/NikkeGunMode/` | the UE4SS mod (copy into `SB/Binaries/Win64/ue4ss/Mods/`) |
| `data/patches/` | data-table patches applied by the pak build |
| `tools/blender/` | Mixamo -> EVE retarget and FBX export (Blender 5.2) |
| `tools/unreal/` | UE 4.26 headless import onto the CH_P_EVE_01 skeleton stand-in |
| `tools/build/` | cook / bone-remap / blend-space / pak builds (retoc, UAssetGUI) |
| `tools/ghidra/` | headless Ghidra scripts (scripts only; no decompiled game code is kept in this repo) |
| `native/` | small native helper |
| `docs/` | research log |

The build tools were written for one PC and still carry its folder layout (`~/Downloads/Modding Tools`, override with
the `NGM_TOOLS` environment variable). Making them portable is welcome work.

## Not in this repo

No game files, no extracted or cooked game assets, no paks, and no decompiled game code. Build them locally from your
own copy of the game.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).
