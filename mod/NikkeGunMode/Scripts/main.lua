-- ============================================================================
--  NikkeGunMode v0.70  (Schizo.Effective)
--  Lets Eve enter the NIKKE-collab "Gun Mode" (the TPS cover-shooter mode from
--  the DLC missions) during normal gameplay.
--
--  How it works (from the game's own data, no new assets):
--    * The NIKKE stages switch Eve into gun mode by applying the effect
--      P_Eve_GunNikke  (EffectTable row 10082). Its one action is
--      EffectAction_TPSNikke (enum 35) with the parameter "Eve_NikkeGun", which
--      puts the character into ESBTPSModeType_Nikke (= 2).
--    * P_Eve_GunNikke_Dispel ends it.
--    * Gun mode runs on its own stats/items: Nikke_HP / Nikke_MaxHP,
--      Nikke_BetaGauge (burst), and the Bullet_Nikke item as the 60-round clip
--      (reload = P_Eve_GunNikke_Reload, which refills Bullet_Nikke to 60).
--    * We apply those effects through the game's own zone-event system
--      (needs the NGM_AE_* rows in EventActorEffectTable - see below).
--
--  v0.5: firing comes from the data pak zNikkeGunMode_P (SkillCommandTable: the NIKKE fire commands
--  use RangedFireSkill, so they no longer need Bullet_Nikke equipped).
--
--  v0.7: firing is sent straight to the skill system. Ctrl+Left-click (while in Gun Mode) sends
--  ServerRequest_UseSkill(EVE, SkillCommandState_TPSFire = 44, skill 1007601, "P_Eve_GunNikke_ShootSlug1_1",
--  {}, aim point, aim direction) - the request the game's own input would send if it routed the NIKKE fire
--  command outside a NIKKE stage (it doesn't: the stance never sees TPSFire there).
--
--  Keys (change below):
--    Ctrl+G        toggle Gun Mode   (F6/F8 clash with the outfit mod)
--    Ctrl+LMB      fire (in Gun Mode, while aiming)
--    Ctrl+Shift+G  print a status line to the UE4SS log (TPS mode / type)
-- ============================================================================

local CFG = {
    TOGGLE_KEY      = Key.G,           -- v0.16: plain G (no Ctrl: holding Ctrl first started the drone aim zoom). In the
                                       -- game's DefaultInput.ini, G is only UI_RightThumbstick (menus), so it is ignored
                                       -- while a menu is open / the game is paused.
    PAD_TOGGLE      = true,            -- v0.16: controller - hold R1 (RightShoulder) and press L2 (LeftTrigger)
    PAD_POLL_MS     = 50,              --   polled with IsInputKeyDown; L2+R2 fires in Gun Mode (= Ctrl+LMB)
    STATUS_KEY      = Key.G,           -- (unused since v0.16)
    VERIFY_DELAY_MS = 700,             -- how long after turning on to check the mode actually engaged
    FORCE_BULLET    = false,
    FIRE_KEY        = Key.LEFT_MOUSE_BUTTON, -- with Ctrl (Ctrl is the aim key)
    FIRE_SKILL_ID   = 1007601,         -- SkillTable / SkillCommandTable P_Eve_GunNikke_ShootSlug1_1
    FIRE_NODE       = "P_Eve_GunNikke_ShootSlug1_2", -- the non-DualSense fire command (ShootSlug1_1 needs the
                                       -- DualSense trigger "weapon fired" state: DualSenseCheckType True)
    FIRE_COMMAND    = 44,              -- ESBSkillCommandState::SkillCommandState_TPSFire
    EVE_GUID_GUESS  = 1501,            -- PC value (11-14); only a fallback since v0.36
    WIDE_RETICLE    = true,            -- v0.25 (desktop): reticle reaches the screen edges (camera aspect = screen W/H in Gun Mode)
    SCREEN_ASPECT   = nil,             --   nil = read from GameUserSettings; or e.g. 1920/1080
    GUID_SEARCH     = false,           -- v0.40: OFF - bullet requests to random GUIDs crashed story maps
    DRONE_FIX       = false,           -- v0.39: v0.8c drone unlock/summon repair on load (only for saves hit by v0.8b)
    AMMO_WATCH      = false,            -- v0.41: log the quick slot / TPS counters in Gun Mode (does one show the NIKKE bag count?)
    SCAN_ALT_ALIAS  = "Bullet_Normal", -- v0.37: second alias for the bisection if her start bullet is unknown
    FULL_AUTO       = true,            -- v0.10: hold Ctrl+LMB for continuous fire
    INPUT_AIM       = false,           -- v0.12: movement input toward the aim point right before each shot
    FACE_AIM        = false,           -- v0.10: turn EVE to the aim point before each shot (projectile follows her facing)
    STANCE_GUARD    = true,            -- v0.15: put EVE back in the gun stance when the game drops it (the automatic
    STANCE_CHECK    = 0.25,            --   sword draw on entering combat), checked every STANCE_CHECK s,
    STANCE_COOLDOWN = 1.0,             --   at most once per STANCE_COOLDOWN s
    BATTLE_GUARD    = true,            -- v0.17: the "stand up and draw the sword" is EVE's blueprint answering
    BATTLE_WINDOW   = 2.5,             --   Event_ChangeBattleState (combat start/end) with a montage; in Gun Mode stop any
                                       --   non-gun montage for BATTLE_WINDOW s after that event
    AMMO_TOPUP_EVERY = nil,            -- v0.17 (until the real ammo item): grant 60 more every 50 shots - she stood up when
                                       --   the 60 from entry ran out (11-16 02:23 clip, shot #60)
    AIM_READY       = 0.35,            -- v0.19: no shot until the aim key (Ctrl / L2) has been held this long - the stray
                                       --   low-left first shot came when L2 and R2 were pressed together (gun not up yet)
    RETICLE_SCALE   = 1.6,             -- v0.19: enlarge the NIKKE reticle while in Gun Mode (lost in the muzzle flash)
    PAD_COMBO       = "DPadRight",           -- v0.19: controller toggle; "R1+L2" (L2 also starts the drone zoom) or
                                       --   "L1+DPadRight", or (default, user's pick) "DPadRight": D-pad Right alone has no
                                       --   gameplay action; ignored while R1 is held (Unified Projection Suit's RB+D-pad)
    LASER_SCALE     = 1.0,             -- v0.21: thicken the NIKKE guide laser (Niagara NS_A_GuideLaser, owned by
                                       --   WorldSettings) by scaling its component - first try, before its params are known
    LASER_BOOST     = true,            -- v0.55: brighter-looking laser via runtime fade parameters (no asset patch)
    LASER_FADE_NEAR = 0.0,             --   User.FadeDistanceNear
    LASER_FADE_FAR  = 100000.0,        --   User.FadeDistanceFar (cm)
    LASER_SWAP      = false,           -- v0.22: give the NIKKE guide laser the enemy (BotRange) guide-laser look - same
                                       --   user params (StartPos/EndPos), more emitters (flares). Done from a one-shot game
                                       --   thread call, never inside the tick hook (v0.21 crashed doing that)
    NIKKE_HP        = false,           -- v0.24: false = keep EVE's normal HP/damage (the NIKKE MaxHP100/HP100 rows made her
                                       --   immortal in the stance)
    LOCK_POSITION   = false,           -- v0.60: OFF again - on the desktop centre cover pinned EVE and the camera (Schizo 11-16 19:00). v0.28: back ON - Position2 (centre cover) is only a HUD event; the walking lock
                                       --   was P_Eve_GunNikke's own ActorState_BlockMove (removed in sp_pak3). With centre
                                       --   cover on, the DLC's side-dash evades Evade1_2 (left) / Evade1_3 (right) work
                                       --   with the game's evade input + direction.
    DEBUG_AMMO_KEY  = true,
    EFFECT_PROBE    = false,           -- v0.54: OFF - its world-wide object walk crashed the game (11-16)
    AMMO_HUD        = false,           -- v0.57: OFF - the quick slot is hidden in Gun Mode and category 13 didn't change its count
    AIM_DIAG        = true,            -- v0.58 TEST ONLY: dump the NIKKE reticle widget after shots 3 and 15
    SLOT_DIAG       = false,            -- v0.56 TEST ONLY: one-shot quick-slot widget dump on the first Gun Mode entry            -- v0.53 TEST ONLY: Ctrl+F12 = +60 NIKKE Rounds (set false for release)
    STAND_EVADE     = false,           -- v0.61: off - the NIKKE roll commands need a cover position (Position1/2/3); rolls are crouch-mode only. v0.52: Shift/Circle + A/D (left stick) also rolls while standing/aiming
    EVADE_SWAP      = false,           --   true if left/right come out reversed
    EVADE_RECENTER  = 0.9,             -- v0.28: s after an evade press to put EVE back on "centre cover" (PosOff + Pos2),
                                       --   so the next roll can go either way. nil = off
    -- (v0.24 note kept below)
    LOCK_POSITION_OLD = false,           -- v0.24: false = no NIKKE cover position (P_Eve_GunNikke_Position2), so she can
                                       --   walk/turn between shots (the hide stance has walk/run speeds)
    STANDING        = true,            -- v0.61: Gun Mode starts STANDING - aim pose held (no Ctrl needed), upright legs
                                       --   from the drone-aim lower body (zNikkeGunMode_P cmdpak4 stance edit), LMB / R2 fires
    ROLL_SWAP       = true,            -- v0.64: Shift/Circle in Gun Mode = EVE's normal dodge roll: the NIKKE gun is
                                       --   lifted for ROLL_TIME s (the game's own evade input then rolls), then put back.
                                       --   The NIKKE side rolls need a stage cover target and never start in the open world.
    ROLL_TIME       = 0.9,
    ROLL_COOLDOWN   = 1.2,
    STAND_OVERRIDE  = nil,             -- v0.68: off - the stand anims now live in P_Eve_GunNikke_BS itself (NGM_Stand_BS never loaded in game)
    STAND_OVERRIDE_ASSET = "/Game/Art/Character/PC/CH_P_EVE_01/Animation/BlendSpace/NGM_Stand_BS.NGM_Stand_BS",   -- must load, or no override     -- v0.67: animset forced while standing (ActiveCustomMovingStanceData; v0.66 test with P_Eve_Gun_Battle worked). NGM_Stand = zNikkeGunStand_P
    STAND_FACE_CAMERA = true,          -- v0.67: standing - EVE always faces the camera direction (TPS)
    STAND_LOOK      = true,            -- v0.70: standing - mouse / right stick turn the camera ourselves (the NIKKE stances
                                       --   send the mouse to the reticle and keep the camera fixed, 11-17 11:58)
    LOOK_SENS_MOUSE = 0.6,             --   degrees per MouseX/MouseY unit
    LOOK_SENS_PAD   = 160,             --   degrees per second at full stick
    LOOK_PITCH_MIN  = -60, LOOK_PITCH_MAX = 50,
    STAND_AO_OFF    = false,            -- v0.70e: mode 0 layers the drone-aim upper-body offset over our anims (twisted torso,
                                       --   11-17 13:17) - bIsActiveTPSAimOffset false while standing (test)
    STAND_RETICLE   = true,            -- v0.70f: standing - keep a reticle widget visible (probe + force visible)
    OWN_RETICLE     = false,           -- v0.70m: off (drew nothing; possible crash suspect)
    FORCE_ZOOM      = false,
    CAM_CUSTOM_OFFSET = { X = 0, Y = 60, Z = 0 },   -- v0.70n: CameraBoom.CustomOffset while standing (test: Y only, to learn its axes)            -- v0.70m: hold the game's TPS "aiming" state while standing (bTPSZoomIn): reticle,
                                       --   unfolded rifle, closer shoulder camera            -- v0.70j: our own WB_Tps_Aim_C in the viewport (the HUD's copy stays faded outside aim)
    AIM_ROW_WRITE   = true,            -- v0.70g: every shot aims exactly at the crosshair point (ProjectileTable row, live)
    LASER_SIGHT     = true,            -- v0.70g: NIKKE guide laser on the gun muzzle, end on the crosshair point
    LASER_SOCKET    = "SC_GunShoot",
    LASER_PITCH_OFS = 0, LASER_YAW_OFS = 0,   -- v0.70h: beam axis correction if the effect's beam isn't along +X
    LASER_ATTACH    = "camera",        -- v0.70i: "camera" (beam to the crosshair, no per-frame calls) or "gun" (muzzle socket)
    LASER_CAM_OFFSET = { X = 140, Y = -35, Z = -30 },   -- forward / right / up from the camera: start by the gun on screen
    STAND_TPS_ZERO  = true,            -- v0.70c: standing - TPS mode 2 (NIKKE: fixed camera, mouse moves a reticle) -> 0 (the
                                       --   drone-aim mode, camera follows the mouse); put back to 2 if the gun stance drops
    AIM_UP_PROBE    = false,           -- v0.69: off - none of the Lua routes brought the aim stance up, and one of them crashed (11-17 10:17)
    CROUCH_OVERRIDE = "P_Eve_GunNikkeHide",   -- v0.69: crouched = the NIKKE kneel animset (the cover stance itself now stands)
    FIRE_IN_COVER_STANCE = true,       -- v0.69: the cover stance's gun is no longer folded (zNikkeGunStand_P), so standing fires in it
    MOVE_DIAG       = false,           -- v0.70d: off (fewer calls from the tick)
    MOVE_DIAG_OLD   = true,            -- v0.66: log body/actor/camera yaw while moving in Gun Mode (60 lines max)             -- v0.66: no new roll until this long after the gun is put back (a quick second roll crashed)

    CROUCH_KEY2     = "Y",             --   v0.63: Y as well (free: SplitScreen only uses Ctrl+Y); Caps Lock can't be sent by the test tooling
    CROUCH_KEY      = "CapsLock",      --   v0.61: keyboard key for crouch <-> stand (free in DefaultInput.ini and the hotkey scan)
    CROUCH_PAD      = "Gamepad_RightThumbstick",   -- R3 (Schizo's pick; the game also has R3 = lock-on toggle)
    KEEP_HUD        = true,            -- v0.61: put back the HUD widgets the NIKKE mode hides (HP etc.)
    REAL_AMMO       = false,           -- v0.24: each shot spends one Bullet_Nikke; Gun Mode ends when it runs out
    STARTER_AMMO    = 60,              --   granted once per session if she has none yet (until shops/drops carry it)
    FREE_EVADE      = false,           -- v0.28: off - replaced by LOCK_POSITION + EVADE_RECENTER (CharacterStanceTable
                                       --   can't be rebuilt, so the NGM_Evade_L/R commands never reached the stances)            -- v0.27: NGM_FreeEvade marker -> the DLC side-dash evades (cmdpak3 NGM_Evade_L/R)
                                       --   work anywhere in Gun Mode: the game's own evade input + left/right
    PEACEFUL        = true,            -- v0.27: PeacefulMode_Infinite while in Gun Mode, as the real NIKKE stage applies at
                                       --   start (against the sword flash on battle start/end)
    EXIT_WHEN_EMPTY = true,            -- v0.35: leave Gun Mode when aim falls back to the drone stance (BulletZero)
    HUD_DIAG        = false,           -- v0.25-v0.34 diagnostics (HUD widgets, util slot / TPS counters, class scans): off            -- v0.25: log the HUD widgets (quick-slot column, TPS bullet slot, NIKKE clip) so the
                                       --   ammo counter can reuse the slot that swaps to Stinger ammo while drone-aiming.
                                       --   One-shot game-thread calls only (never inside the tick hook). A few per session.
    FIRST_SHOT_DELAY = 0.12,           -- v0.14: the first shot of each burst left before the gun had come up into the
                                       -- shoot pose (muzzle still pointing low-left), so wait this long before it.
    FIRE_INTERVAL   = 0.11,            -- v0.9g: full auto at the shot skill's own CoolTime (0.11 s) while LMB is held
    FIRE_EFFECT_ID  = 9900301,         -- v0.9: EffectTable NGM_Fire = Self, 0.1 s, Action1 UseSkill "P_Eve_GunNikke_ShootSlug1_1"
    FIRE_ZONE_ROW   = "NGM_AE_Fire",   -- EventActorEffectTable row that applies NGM_Fire to EVE
    DIAG            = false,
    NATIVE_SWITCHES = false,           -- v0.9f: OFF. The stage-entry memory switches never helped firing, and
                                       -- DAT_147032aa8 is a bit field (read 0xC0 / 0x40), not a flag: writing 1 there
                                       -- is the likely cause of the HUD vanishing (11-15). Leave the game's memory alone.
    HOLD_BULLET     = true,            -- v0.8: write SBCharacter.CurrentBulletItemAlias = Bullet_Nikke directly
                                       -- (a real stage has it; ours reverts to Bullet_Normal) - property write, no RPC
    HOLD_MS         = 250,
    LOOKAT          = true,            -- v0.8: CustomLookAtActive = true, as in a real stage           -- v0.5b state logger; off since v0.7d (polling it ~7/s caused stutter)            -- s between shots while the key repeats (v0.7 spammed 4/s and lagged)            -- found by the v0.4d search on 11-14; used until a search confirms it           -- v0.4c/d bullet-switch experiment (the game reverts it); off since v0.5
}

local TAG = "[NikkeGunMode] "
local function log(s) print(TAG .. tostring(s) .. "\n") end

-- Rows NGM_AE_* live in EventActorEffectTable (added by NGM_2_build.bat). Each one puts one
-- EffectTable effect on Eve when fired through SBBlueprintLibrary.CreateSBZoneEvent(2, row),
-- the same route Survival Protocol uses. (The debug command SBApplyEffectMe does nothing in the
-- release build - tested 2026-11-14.)
-- {zone event type, row}: 2 = AttachActorEffect (EventActorEffectTable), 13 = ItemAction (EventItemActionTable)
-- Order copies a NIKKE stage start: ammo item first, then the mode, the centre cover spot and the stat bars.
-- v0.8b adds the NIKKE stage start effects we were missing (NikkeStageTable PlayerStartEffects):
--   NGM_AE_NoDrone = LV_SummonDrone_Dispel, NGM_AE_DroneLock = P_EVE_DoNotSummonDrone (exit: _Dispel),
--   NGM_AE_Reload = P_Eve_GunNikke_ReloadStartDelay (the stage's opening reload - fills the magazine)
-- v0.8c: the drone rows are OUT again - dismissing + locking the drone stopped it coming back after exit (no ranged
-- weapon at all), and firing still didn't work without it. Exit now also unlocks and re-summons the drone using the
-- game's own rows: Xion_11_E_ActorEff_001 = P_EVE_DoNotSummonDrone_Dispel, CGH_data_E_ActorEff_003 = P_Eve_Sword_SummonDrone.
local ON_ROWS  = { {13, "NGM_ItemA_Ammo"}, {2, "NGM_AE_Reload"},
                   {2, "NGM_AE_GunOn"}, {2, "NGM_AE_Pos2"},
                   {2, "NGM_AE_MaxHP"}, {2, "NGM_AE_HP"}, {2, "NGM_AE_Beta"}, {2, "NGM_AE_Ammo"} }
do  -- v0.24: optional rows
    local keep = {}
    for _, r in ipairs(ON_ROWS) do
        local n = r[2]
        -- v0.27: with REAL_AMMO, no free 60 on every entry (NGM_ItemA_Ammo gave +60, NGM_AE_Ammo refilled to 60)
        if not ((n == "NGM_AE_Pos2" and not CFG.LOCK_POSITION) or ((n == "NGM_AE_MaxHP" or n == "NGM_AE_HP") and not CFG.NIKKE_HP)
                or ((n == "NGM_ItemA_Ammo" or n == "NGM_AE_Ammo") and CFG.REAL_AMMO)) then
            keep[#keep + 1] = r
        end
    end
    ON_ROWS = keep
end
-- v0.47: the NIKKE auto-reload (P_Eve_GunNikke_Reload -> ReloadCompleted: ItemRefill Bullet_Nikke +60) refilled the bag
-- whenever she stopped firing = infinite ammo. sp7 makes that reload wait while NGM_RealAmmo is on.
if CFG.REAL_AMMO then ON_ROWS[#ON_ROWS + 1] = {2, "NGM_AE_RealAmmo"} end
if CFG.FREE_EVADE then ON_ROWS[#ON_ROWS + 1] = {2, "NGM_AE_FreeEvade"} end   -- v0.27 (rows from sp_pak3)
if CFG.PEACEFUL then ON_ROWS[#ON_ROWS + 1] = {2, "NGM_AE_Peace"} end
local OFF_ROWS = { {2, "NGM_AE_FreeEvadeOff"}, {2, "NGM_AE_PeaceOff"}, {2, "NGM_AE_GunOff"}, {2, "NGM_AE_PosOff"}, {2, "NGM_AE_HPOff"}, {2, "NGM_AE_MaxHPOff"}, {2, "NGM_AE_BetaOff"},
                   {2, "NGM_AE_DroneFree"}, {2, "Xion_11_E_ActorEff_001"}, {2, "CGH_data_E_ActorEff_003"} }
local DRONE_FIX_ROWS = { {2, "NGM_AE_DroneFree"}, {2, "Xion_11_E_ActorEff_001"}, {2, "CGH_data_E_ActorEff_003"} }

-------------------------------------------------------------------------------
-- native part (v0.6): NikkeGunMode.dll does the NIKKE stage-entry switches Lua can't reach (game-state singleton
-- +0x43/+0x4c, global switch 0x147032aa8, EVE's bullet through the game's own setter). Its exports ignore the Lua
-- state (no Lua linked, StellarCoop's trick): the result code is how many of the 8 arguments come back.
-- 1 done, 2 not the pinned build 26123051, 3 fault caught, 4 EVE not found. Details: NikkeGunMode_native.log.
-------------------------------------------------------------------------------
local NATIVE = {}
local MODFOLDER = nil
do
    local folder = debug.getinfo(1, 'S').source:match('^@(.*)[\\/]Scripts[\\/][^\\/]*$')
    MODFOLDER = folder
    -- v0.9h: the DLL is no longer loaded at all (its memory switches are off since v0.9f, and a loaded DLL is the
    -- likeliest reason UE4SS hot reload crashed the game twice on 11-15). Set CFG.NATIVE_SWITCHES to bring it back.
    if CFG.NATIVE_SWITCHES and folder and package and package.loadlib then
        for _, name in ipairs({ "ngm_on", "ngm_off", "ngm_probe", "ngm_vtable" }) do
            local f, why = package.loadlib(folder .. '\\NikkeGunMode.dll', name)
            if type(f) == 'function' then NATIVE[name] = f
            else print("[NikkeGunMode] native " .. name .. " not loaded: " .. tostring(why) .. "\n") end
        end
    end
end
local NATIVE_CODES = { [1] = "done", [2] = "not the pinned build", [3] = "fault caught", [4] = "EVE not found" }
local function native(name)
    local f = NATIVE[name]
    if not f then return "unavailable" end
    local ok, n = pcall(function() return select('#', f(0, 0, 0, 0, 0, 0, 0, 0)) end)
    if not ok then return "error " .. tostring(n) end
    return NATIVE_CODES[n] or ("code " .. tostring(n))
end

-------------------------------------------------------------------------------
-- helpers
-------------------------------------------------------------------------------
local function valid(o)   -- v0.70b: pcall'd (a nullptr wrapper made this throw, right before a crash 11-17 12:05)
    if o == nil then return false end
    local ok, r = pcall(function() return o:IsValid() end)
    return ok and r == true
end
local function try(fn) local ok, r = pcall(fn); if ok then return r end end

-- v0.7d: FindFirstOf walks the whole object array - cache the controller instead of looking it up every call
local cachedPC = nil
tickPauseUntil = 0   -- v0.59 (global: set by the new-controller callback, read by the tick)
local function getPC()
    if valid(cachedPC) then return cachedPC end
    local pc = FindFirstOf("SBPlayerController")
    if valid(pc) then cachedPC = pc; return pc end
end
local function getPawn()
    local pc = getPC()
    if not pc then return nil end
    local p = pc.Pawn
    if valid(p) then return p end
end
local function fireRow(e)
    local zeType, row = e[1], e[2]
    local lib = StaticFindObject("/Script/SB.Default__SBBlueprintLibrary")
    if not valid(lib) then log("no SBBlueprintLibrary"); return false end
    local ok, err = pcall(function() lib:CreateSBZoneEvent(zeType, FName(row)) end)
    if not ok then log("event " .. row .. " failed: " .. tostring(err)) end
    return ok
end

local function modeInfo()
    local p = getPawn()
    if not p then return "no pawn" end
    local isTps = try(function() return p:IsTPSMode() end)
    local mtype = try(function() return p:GetTPSModeType() end)
    return string.format("IsTPSMode=%s TPSModeType=%s (0=default drone aim, 1=minigame, 2=NIKKE)",
        tostring(isTps), tostring(mtype)), isTps, mtype
end

-------------------------------------------------------------------------------
-- bullet: a NIKKE stage switches Eve's equipped TPS bullet to Bullet_Nikke on entry
-- (game config NikkeStage_ChangeBullet, read by the stage-entry code at 0x141c2ede0 in the
-- Ghidra project). The shot comes from the equipped bullet, so without this she aims but never fires.
-- We use the same request the bullet wheel sends: ServerRequest_ChangeBulletItem(actorGUID, alias).
-- Eve's actor GUID isn't exposed, so it is picked up from her own requests (jump, land, lock-on,
-- interact, bullet change...). One jump after loading is enough.
-------------------------------------------------------------------------------
local eveGUID, prevBullet = nil, nil
local gunOn, startKeeper = false, nil   -- (defined further down; declared here for the GUID search)
local function learnGUID(src, p)
    local g = try(function() return p:get() end)
    if g and g ~= 0 and g ~= eveGUID then
        eveGUID = g
        log("Eve's actor GUID = " .. tostring(g) .. " (from " .. src .. ")")
    end
end
local GUID_SOURCES = { "ActorJump", "ActorLanded", "ActorLockOnTarget", "ActorInteraction",
                       "ChangeBulletItem", "ActorStancePressCommandKey", "ActorTransform", "SetSkillSlot" }
local BROADCAST_SOURCES = { "ClientBroadcast_ActorSetBulletItem" }
local hooksDone = false
local function hookGUIDSources()
    if hooksDone then return end
    hooksDone = true
    for _, fn in ipairs(GUID_SOURCES) do
        local ok, err = pcall(function()
            RegisterHook("/Script/SB.SBNetworkPlayerController:ServerRequest_" .. fn, function(self, guid)
                learnGUID(fn, guid)
            end)
        end)
        if not ok then log("hook " .. fn .. " failed: " .. tostring(err)) end
    end
    for _, fn in ipairs(BROADCAST_SOURCES) do
        pcall(function()
            RegisterHook("/Script/SB.SBNetworkPlayerController:" .. fn, function(self, turn, guid, alias)
                local a = try(function() return alias:get():ToString() end)
                log(fn .. " guid=" .. tostring(try(function() return guid:get() end)) .. " bullet=" .. tostring(a))
                learnGUID(fn, guid)
            end)
        end)
    end
end

-- the player's actor GUID is also kept on the player state (SBNetworkPlayerState.ActorNetGuid)
local function guidFromPlayerState()
    local pc = getPC()
    if not pc then return nil end
    local ps = try(function() return pc.PlayerState end)
    if not valid(ps) then return nil end
    local cls = try(function() return ps:GetClass():GetFName():ToString() end)
    local g = try(function() return ps.ActorNetGuid end)
    log("player state " .. tostring(cls) .. " ActorNetGuid=" .. tostring(g))
    if g and g ~= 0 then return g end
end

-- Last resort: Eve's GUID is not exposed anywhere a Lua mod can read, so try the bullet request
-- with GUIDs 1, 2, 3, ... in small batches and stop as soon as her equipped bullet becomes the one asked
-- for. A wrong GUID matches no actor (nothing happens) or another actor (its bullet field changes, which
-- nothing but the player uses). Runs once per load; the GUID is kept afterwards.
local scanning = false
local SCAN_MAX, SCAN_BATCH, SCAN_WAIT = 300000, 1500, 120
-- v0.37: the request is applied a tick later, so v0.36's check right after each call never saw the change (and it
-- ran on the start-up level, before the title). Now: send a batch, look a moment later; when her bullet flips, bisect
-- the last two batches by alternating between two aliases until one GUID is left.
local function scanForGUID(alias, onFound, onFail)
    if scanning then return end
    local p0, pc = getPawn(), getPC()
    if not (p0 and pc) then if onFail then pcall(onFail) end; return end
    local start = try(function() return p0:GetCurrentBulletItemAlias():ToString() end)
    if start == alias then
        -- already that bullet: use the other alias for the sweep
        alias = (CFG.SCAN_ALT_ALIAS ~= alias) and CFG.SCAN_ALT_ALIAS or "Bullet_Nikke"
    end
    local other = (start and start ~= "None" and start ~= alias) and start
                  or ((CFG.SCAN_ALT_ALIAS ~= alias) and CFG.SCAN_ALT_ALIAS or "Bullet_Normal")
    scanning = true
    log("searching for Eve's GUID (bullet requests 1.." .. SCAN_MAX .. ", sweep alias " .. alias .. ", start " .. tostring(start) .. ")...")
    local t0 = os.clock()
    local function bullet() local p = getPawn(); return p and try(function() return p:GetCurrentBulletItemAlias():ToString() end) end
    local function send(lo, hi, a)
        local pc2 = getPC(); if not pc2 then return false end
        local fa = FName(a)
        for g = lo, hi do pcall(function() pc2:ServerRequest_ChangeBulletItem(g, fa) end) end
        return true
    end
    local function done(g)
        scanning = false
        if g then
            eveGUID = g
            log(string.format("Eve's actor GUID = %d (found by search in %.1f s)", g, os.clock() - t0))
            if onFound then pcall(onFound, start) end
            if NGM_onGUIDKnown then pcall(NGM_onGUIDKnown, g) end
        else
            log("GUID search: not found")
            if onFail then pcall(onFail) end
        end
    end
    -- bisection inside [lo,hi]; cur = alias her bullet shows now
    local function bisect(lo, hi, cur)
        if lo == hi then return done(lo) end
        local mid = math.floor((lo + hi) / 2)
        local a = (cur == alias) and (other or "Bullet_Nikke") or alias
        if a == cur then return done(nil) end
        ExecuteInGameThread(function()
            if not send(lo, mid, a) then return done(nil) end
            ExecuteWithDelay(SCAN_WAIT, function() ExecuteInGameThread(function()
                local b = bullet()
                if b == a then bisect(lo, mid, a) else bisect(mid + 1, hi, cur) end
            end) end)
        end)
    end
    local prevLo = 1
    local function sweep(lo)
        ExecuteInGameThread(function()
            if not getPawn() then scanning = false; log("GUID search stopped: no player"); return end
            local hi = math.min(lo + SCAN_BATCH - 1, SCAN_MAX)
            send(lo, hi, alias)
            ExecuteWithDelay(SCAN_WAIT, function() ExecuteInGameThread(function()
                if bullet() == alias then
                    log("GUID search: bullet flipped in " .. prevLo .. ".." .. hi .. ", narrowing")
                    if not other then
                        -- no second alias to bisect with: probe the last range one by one
                        local g = prevLo
                        local function one()
                            ExecuteInGameThread(function()
                                if g > hi then return done(nil) end
                                send(g, g, CFG.SCAN_ALT_ALIAS)
                                ExecuteWithDelay(SCAN_WAIT, function() ExecuteInGameThread(function()
                                    if bullet() == CFG.SCAN_ALT_ALIAS then return done(g) end
                                    g = g + 1; one()
                                end) end)
                            end)
                        end
                        return one()
                    end
                    return bisect(prevLo, hi, alias)
                end
                if hi >= SCAN_MAX then return done(nil) end
                if (hi + 1) % 30000 < SCAN_BATCH then log("GUID search at " .. (hi + 1) .. " ...") end
                prevLo = lo
                sweep(hi + 1)
            end) end)
        end)
    end
    sweep(1)
end

-- v0.37: only search in real gameplay (the main HUD is on screen), not on the start-up level or the title
local function inGameplay()
    -- the bottom quick slot of the main HUD only exists (and is visible) in gameplay
    local ws = try(function() return FindAllOf("WB_MainHUD_ItemSlot_C") end)
    for _, w in ipairs(ws or {}) do
        if valid(w) and w:GetFName():ToString() == "WB_MainHUD_UtilItem"
           and try(function() return w:IsVisible() end) == true then return true end
    end
    return false
end

local function curBullet()
    local p = getPawn()
    if not p then return nil end
    return try(function() return p:GetCurrentBulletItemAlias():ToString() end)
end

local function setBullet(alias)
    local pc = getPC()
    if not pc then return false end
    if not eveGUID then
        local g = guidFromPlayerState()
        if g then eveGUID = g; log("Eve's actor GUID = " .. tostring(g) .. " (from player state)") end
    end
    if not eveGUID then
        scanForGUID(alias, function()
            ExecuteWithDelay(CFG.VERIFY_DELAY_MS, function() ExecuteInGameThread(function()
                log("after GUID search: bullet=" .. tostring(curBullet()) .. "  " .. (modeInfo()))
            end) end)
        end)
        return false
    end
    local ok, err = pcall(function() pc:ServerRequest_ChangeBulletItem(eveGUID, FName(alias)) end)
    if not ok then log("ChangeBulletItem " .. alias .. " failed: " .. tostring(err)) end
    return ok
end

-------------------------------------------------------------------------------
-- v0.4d: the search found Eve (GUID 1501 on 11-14) - her bullet read Bullet_Nikke for a moment and was
-- Bullet_Missile again 0.5 s later. Something puts it back (likely the ammo-slot manager: Bullet_Nikke is
-- not in the game's ammo list BulletItemSlotArray). Test: while Gun Mode is on, put it back to
-- Bullet_Nikke every 100 ms and log how often the game reverts it.
-------------------------------------------------------------------------------
local keepRun, reverts, keepT0 = 0, 0, 0

-- v0.5b diagnostics: while Gun Mode is on, log (only when it changes) what Eve is doing:
-- skill running, TPS aim offset active, zoomed in, TPS mode/type, equipped bullet.
local diagRun, lastDiag = 0, nil
local function diagTick(run)
    if run ~= diagRun or not gunOn then return end
    local p = getPawn()
    if p then
        local s = string.format("skill=%s aim=%s zoom=%s tps=%s type=%s bullet=%s",
            tostring(try(function() return p:IsRunningSkill() end)),
            tostring(try(function() return p:IsActiveTPSAimOffset() end)),
            tostring(try(function() return p.bTPSZoomIn end)),
            tostring(try(function() return p:IsTPSMode() end)),
            tostring(try(function() return p:GetTPSModeType() end)),
            tostring(try(function() return p:GetCurrentBulletItemAlias():ToString() end)))
        if s ~= lastDiag then lastDiag = s; log("state: " .. s) end
    end
    ExecuteWithDelay(150, function() ExecuteInGameThread(function() pcall(diagTick, run) end) end)
end
local function startDiag()
    if not CFG.DIAG then return end
    diagRun = diagRun + 1; lastDiag = nil
    local run = diagRun
    ExecuteWithDelay(150, function() ExecuteInGameThread(function() pcall(diagTick, run) end) end)
end
local function keepBullet(run)
    if run ~= keepRun or not gunOn or not eveGUID then return end
    local b = curBullet()
    if b ~= "Bullet_Nikke" then
        reverts = reverts + 1
        if reverts <= 5 or reverts % 50 == 0 then
            log(string.format("bullet back to %s after %.2f s (revert #%d) - setting Bullet_Nikke again", tostring(b), os.clock() - keepT0, reverts))
        end
        setBullet("Bullet_Nikke")
        keepT0 = os.clock()
    end
    ExecuteWithDelay(100, function() ExecuteInGameThread(function() pcall(keepBullet, run) end) end)
end
startKeeper = function()
    keepRun = keepRun + 1; reverts = 0; keepT0 = os.clock()
    local run = keepRun
    ExecuteWithDelay(100, function() ExecuteInGameThread(function() pcall(keepBullet, run) end) end)
end

-- v0.10c aim hold (see fireOnce)
local aimYaw, aimUntil, aimHooked = nil, 0, false
local function applyAimYaw(p)
    if not aimYaw then return end
    local r = p:K2_GetActorRotation()
    if math.abs(((r.Yaw - aimYaw + 540) % 360) - 180) > 0.5 then
        p:K2_SetActorRotation({ Pitch = r.Pitch, Yaw = aimYaw, Roll = r.Roll }, false)
    end
end
local function hookAim()
    if aimHooked then return end
    local ok = pcall(function()
        RegisterHook("/Game/Art/Character/PC/CH_P_EVE_01/Blueprints/CH_P_EVE_01_Blueprint.CH_P_EVE_01_Blueprint_C:ReceiveTick",
            function(ctx)
                if not gunOn or os.clock() > aimUntil then return end
                pcall(function() applyAimYaw(ctx:get()) end)
            end)
    end)
    aimHooked = ok
    log("aim hold: EVE tick hook " .. (ok and "registered" or "FAILED"))
end

-- v0.15 stance guard: entering combat makes the game draw EVE's sword, which ends the NIKKE gun stance while Gun Mode
-- is still on (user, 11-15 19:51). Watch the stance/TPS mode and re-apply the stance rows when it has been dropped.
local GUARD_ROWS = CFG.LOCK_POSITION and { {2, "NGM_AE_GunOn"}, {2, "NGM_AE_Pos2"} } or { {2, "NGM_AE_GunOn"} }   -- v0.60
local guardCheck, guardLast, guardCount, guardSince = 0, 0, 0, 0
local guardFails = 0
local function stanceGuard(p)
    local now = os.clock()
    if now - guardCheck < CFG.STANCE_CHECK then return end
    guardCheck = now
    if now - guardSince < 1.5 then return end              -- give the entry rows time to take hold
    local stance = try(function() return p:GetCurrentStanceName():ToString() end) or "?"
    local mtype = tonumber(try(function() return p:GetTPSModeType() end))
    local tps = try(function() return p:IsTPSMode() end)
    local inStance = stance:find("GunNikke", 1, true) ~= nil
    if inStance and tps and (mtype == 2 or (mtype == 0 and CFG.STAND_TPS_ZERO and not crouched and not tpsZeroDead)) then guardFails = 0; return end
    if now - guardLast < CFG.STANCE_COOLDOWN then return end
    -- v0.30: give up after 5 re-applies in a row that didn't bring the stance back (EVE dead/down: the 11-16 laptop log
    -- showed the guard firing every second while she died). Resets once the stance is back.
    if guardFails >= 5 then return end
    guardFails = guardFails + 1
    guardLast = now
    guardCount = guardCount + 1
    for _, r in ipairs(GUARD_ROWS) do
        -- v0.43: with real ammo the gun only comes back while the bag has rounds (NGM_AE_GunOnAmmo is conditional)
        if CFG.REAL_AMMO and r[2] == "NGM_AE_GunOn" then fireRow({2, "NGM_AE_GunOnAmmo"}); fireRow({2, "NGM_AE_ZeroOff"}) else fireRow(r) end
    end
    if crouched then fireRow({2, "NGM_AE_Pos2"}) end   -- v0.61
    if guardCount <= 10 or guardCount % 10 == 0 then
        log(string.format("stance guard #%d: stance=%s IsTPSMode=%s TPSModeType=%s -> gun stance re-applied",
            guardCount, stance, tostring(tps), tostring(mtype)))
    end
end

-- v0.8: hold Bullet_Nikke + CustomLookAtActive by plain property writes (snapshot diff vs a real stage, 11-15)
local holdRun, holdFixes, holdLog = 0, 0, 0
local function holdTick(run)
    if run ~= holdRun or not gunOn then return end
    local p = getPawn()
    if p then
        pcall(function()
            local cur = p.CurrentBulletItemAlias:ToString()
            if cur ~= "Bullet_Nikke" then
                p.CurrentBulletItemAlias = FName("Bullet_Nikke")
                holdFixes = holdFixes + 1
            end
        end)
        if CFG.LOOKAT then pcall(function() if not p.CustomLookAtActive then p.CustomLookAtActive = true end end) end
        if CFG.STANCE_GUARD then pcall(stanceGuard, p) end
    end
    local now = os.clock()
    if now - holdLog > 5 then
        holdLog = now
        log("hold: bullet rewrites so far " .. holdFixes .. ", now " .. tostring(curBullet()))
    end
end
local function startHold()
    if not CFG.HOLD_BULLET then return end
    holdRun = holdRun + 1; holdFixes = 0; holdLog = os.clock()
    guardSince = os.clock(); guardCount = 0; guardFails = 0; tpsProps = nil   -- v0.70c: probe again per entry
    -- v0.18: holdTick now runs from the central EVE tick (see engineTick), not from an ExecuteWithDelay chain
end

-- v0.17 battle guard. The stance never changes when she stands up (the v0.15 guard never fired in the 11-16 02:23
-- clip): CH_P_EVE_01_Blueprint's Event_ChangeBattleState plays a sword montage (sword summon flash, stands up) when
-- combat starts or ends. While Gun Mode is on, stop whatever non-gun montage is playing during the next few seconds.
local battleHooked, battleUntil, battleRun, battleStops = false, 0, 0, 0
local battleSeen = {}
local function isGunMontage(name)
    local n = name:lower()
    return n:find("gun", 1, true) or n:find("nikke", 1, true) or n:find("tps", 1, true) or n:find("shoot", 1, true)
end
local function battleTick(run)
    if run ~= battleRun or not gunOn or os.clock() > battleUntil then return end
    local p = getPawn()
    if p then
        pcall(function()
            local ai = p.Mesh:GetAnimInstance()
            if not valid(ai) then return end
            local m = ai:GetCurrentActiveMontage()
            if not valid(m) then return end
            local name = m:GetFName():ToString()
            if battleSeen[name] == nil then battleSeen[name] = true; log("battle guard: montage playing: " .. name) end
            if not isGunMontage(name) then
                ai:Montage_Stop(0.15, m)
                battleStops = battleStops + 1
                if battleStops <= 20 then log("battle guard: stopped montage " .. name) end
            end
        end)
    end
end
local function hookBattle()
    if battleHooked or not CFG.BATTLE_GUARD then return end
    local ok, err = pcall(function()
        RegisterHook("/Game/Art/Character/PC/CH_P_EVE_01/Blueprints/CH_P_EVE_01_Blueprint.CH_P_EVE_01_Blueprint_C:Event_ChangeBattleState",
            function(ctx, isBattle)
                if not gunOn then return end
                local b = try(function() return isBattle:get() end)
                log("battle state -> " .. tostring(b) .. " (Gun Mode on: suppressing the sword montage)")
                battleUntil = os.clock() + CFG.BATTLE_WINDOW
                battleRun = battleRun + 1
            end)
    end)
    battleHooked = ok
    log("battle guard: Event_ChangeBattleState hook " .. (ok and "registered" or ("FAILED " .. tostring(err))))
end

local outOfAmmoLogged, spendErrs = false, 0
local hookTick   -- v0.18: defined with the central tick further down
-- v0.24 real ammo: Bullet_Nikke count from the item broadcasts (add/update carry the item instance with its total)
local nikkeAmmo, ammoHooked, starterGiven = nil, false, false
bagEmpty = false   -- v0.60: set when Gun Mode ended for lack of rounds; cleared by any Bullet_Nikke > 0 / Ctrl+F12 / map change
local function readInst(inst)
    local alias = try(function() return inst.ItemAlias:ToString() end)
    local cnt = tonumber(try(function() return inst.ItemCount end))
    return alias, cnt
end
local function hookAmmo()
    if ammoHooked then return end
    ammoHooked = true
    for _, fn in ipairs({ "ClientBroadcast_ItemBucketItemAdd", "ClientBroadcast_ItemBucketItemUpdate" }) do
        local ok, err = pcall(function()
            RegisterHook("/Script/SB.SBNetworkPlayerController:" .. fn, function(ctx, turn, bucket, inst)
                pcall(function()
                    local alias, cnt = readInst(inst:get())
                    if alias == "Bullet_Nikke" and cnt then
                        if nikkeAmmo ~= cnt then log("ammo: Bullet_Nikke = " .. cnt .. " (" .. fn:gsub("ClientBroadcast_ItemBucket", "") .. ")") end
                        nikkeAmmo = cnt
                        if cnt > 0 then bagEmpty = false end
                    end
                end)
            end)
        end)
        log("ammo hook " .. fn .. ": " .. (ok and "registered" or ("FAILED " .. tostring(err))))
    end
end
-- v0.22 laser swap
local LASER_ALT = "/Game/Art/FX/Char/Monster/BotRange/NS_A_GuideLaser.NS_A_GuideLaser"
local laserSwapped, laserSwapLogs = {}, 0     -- component full name -> original system
local function laserSwap(tag)
    if not CFG.LASER_SWAP or not gunOn then return end
    local alt = try(function() return StaticFindObject(LASER_ALT) end)
    if not valid(alt) then
        pcall(function() LoadAsset(LASER_ALT) end)
        alt = try(function() return StaticFindObject(LASER_ALT) end)
    end
    if not valid(alt) then log("laser swap " .. tag .. ": BotRange guide laser not loadable"); return end
    local all = FindAllOf("NiagaraComponent")
    if not all then return end
    local n, seen, guide = 0, 0, {}
    for _, c in ipairs(all) do
        pcall(function()
            seen = seen + 1
            local fn = c.Asset:GetFullName()
            if fn:find("GuideLaser", 1, true) then guide[#guide + 1] = fn:gsub("^NiagaraSystem ", "") .. (c:IsActive() and "(active)" or "") end
            if fn:lower():find("dlc_2/art/fx/minigame/ns_a_guidelaser", 1, true) then
                local a = c.Asset
                laserSwapped[c:GetFullName()] = { comp = c, orig = a }
                c:SetAsset(alt, false)
                n = n + 1
            end
        end)
    end
    if n > 0 or laserSwapLogs < 8 then
        laserSwapLogs = laserSwapLogs + 1
        log("laser swap " .. tag .. ": " .. n .. " swapped -> BotRange look (scanned " .. seen .. ", guide lasers: " ..
            (#guide > 0 and table.concat(guide, ", ") or "none") .. ")")
    end
end
-- v0.55 brighter laser without touching the asset (the patched asset crashed): the guide laser fades with distance
-- (User.FadeDistanceNear / User.FadeDistanceFar); push the far fade out and the near fade in so the whole beam stays strong.
local laserBoostLogs = 0
local function laserBoost(tag)
    if not CFG.LASER_BOOST or not gunOn then return end
    local all = FindAllOf("NiagaraComponent")
    if not all then return end
    local n = 0
    for _, c in ipairs(all) do
        pcall(function()
            local fn = c.Asset:GetFullName():lower()
            if not fn:find("ns_a_guidelaser", 1, true) then return end
            local ok1 = pcall(function() c:SetVariableFloat(FName("User.FadeDistanceFar"), CFG.LASER_FADE_FAR) end)
            if not ok1 then pcall(function() c:SetNiagaraVariableFloat("User.FadeDistanceFar", CFG.LASER_FADE_FAR) end) end
            local ok2 = pcall(function() c:SetVariableFloat(FName("User.FadeDistanceNear"), CFG.LASER_FADE_NEAR) end)
            if not ok2 then pcall(function() c:SetNiagaraVariableFloat("User.FadeDistanceNear", CFG.LASER_FADE_NEAR) end) end
            n = n + 1
        end)
    end
    if laserBoostLogs < 6 then
        laserBoostLogs = laserBoostLogs + 1
        log("laser boost " .. tag .. ": " .. n .. " guide laser(s) set (fade near " .. CFG.LASER_FADE_NEAR .. ", far " .. CFG.LASER_FADE_FAR .. ")")
    end
end
local function laserRestore()
    for k, v in pairs(laserSwapped) do
        pcall(function() if valid(v.comp) and valid(v.orig) then v.comp:SetAsset(v.orig, false) end end)
        laserSwapped[k] = nil
    end
end
-- v0.25 (desktop, ported into v0.51): ultrawide reticle. FUN_142119410 (build 26123051) clamps the NIKKE pin's X to the part of the screen that
-- matches a reference aspect: the player camera's AspectRatio when bConstrainAspectRatio is set, else integer W/H.
-- Make that reference equal the real screen aspect while Gun Mode is on.
local wideSaved = {}
local function screenAspect()
    if CFG.SCREEN_ASPECT then return CFG.SCREEN_ASPECT end
    local r = try(function()
        local gus = FindFirstOf("GameUserSettings")
        local pt = gus:GetScreenResolution()
        if pt.X and pt.Y and pt.Y > 0 then return pt.X / pt.Y end
    end)
    return r
end
local function wideReticle(on)
    if on then
        local asp = screenAspect()
        if not asp then log("wide reticle: screen aspect unknown (set CFG.SCREEN_ASPECT)"); return end
        local p = getPawn()
        if not p then return end
        local pcm = try(function() return getPC().PlayerCameraManager end)
        local n = 0
        for _, cls in ipairs({ "SBCameraComponent", "CameraComponent" }) do
            pcall(function()
                local all = FindAllOf(cls)
                if not all then return end
                for _, c in ipairs(all) do
                    pcall(function()
                        local key = c:GetFullName()
                        if wideSaved[key] then return end
                        local o = c:GetOwner()
                        local mine = valid(o) and (o:GetFullName() == p:GetFullName() or (valid(pcm) and o:GetFullName() == pcm:GetFullName()))
                        if not mine then return end
                        local ar, cn = c.AspectRatio, c.bConstrainAspectRatio
                        wideSaved[key] = { c = c, ar = ar, cn = cn }
                        c.AspectRatio = asp
                        c.bConstrainAspectRatio = true
                        n = n + 1
                        log(string.format("wide reticle: %s was AspectRatio=%s constrain=%s -> %.4f", c:GetFName():ToString(), tostring(ar), tostring(cn), asp))
                    end)
                end
            end)
        end
        log("wide reticle: " .. n .. " camera(s) set to screen aspect " .. string.format("%.4f", asp))
    else
        for k, v in pairs(wideSaved) do
            pcall(function()
                if valid(v.c) then v.c.AspectRatio = v.ar; v.c.bConstrainAspectRatio = v.cn end
            end)
            wideSaved[k] = nil
        end
    end
end

-- v0.19: make the NIKKE reticle bigger while in Gun Mode
local RETICLE_CLASSES = { "WB_NikkeHUD_Aim_C", "WB_Tps_Aim_C" }
local function setReticle(scale)
    for _, cls in ipairs(RETICLE_CLASSES) do
        pcall(function()
            local ws = FindAllOf(cls)
            if not ws then return end
            for _, w in ipairs(ws) do
                if valid(w) then pcall(function() w:SetRenderScale({ X = scale, Y = scale }) end) end
            end
            if scale ~= 1.0 then log("reticle: " .. cls .. " x" .. #ws .. " scaled to " .. scale) end
        end)
    end
end
-- v0.20 laser diagnostic: list the FX components that belong to EVE (or actors attached to her) while aiming, to find
-- the NIKKE laser sight so it can be made stronger. Runs once per Gun Mode entry, 1.5 s in (and again at 4 s).
local laserDiag = function(tag)
    local p = getPawn()
    if not p then return end
    local owners = { [p:GetFullName()] = true }
    pcall(function()
        local att = p:GetAttachedActors({}, true)
        if att then for _, a in ipairs(att) do pcall(function() owners[a:get():GetFullName()] = true end) end end
    end)
    local n = 0
    for _, cls in ipairs({ "NiagaraComponent", "ParticleSystemComponent", "SplineMeshComponent", "StaticMeshComponent" }) do
        pcall(function()
            local all = FindAllOf(cls)
            if not all then return end
            for _, c in ipairs(all) do
                pcall(function()
                    local o = c:GetOwner()
                    local mine = valid(o) and owners[o:GetFullName()]
                    if not mine then
                        -- v0.20b: the laser isn't owned by EVE (v0.20 found only one mesh) - also take any active FX
                        -- within 30 m of her
                        if cls == "StaticMeshComponent" then return end
                        local act = try(function() return c:IsActive() end)
                        if not act then return end
                        local a, b = c:K2_GetComponentLocation(), p:K2_GetActorLocation()
                        local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
                        if dx * dx + dy * dy + dz * dz > 3000 * 3000 then return end
                    end
                    local asset = try(function() return c.Asset:GetFullName() end) or try(function() return c.Template:GetFullName() end)
                        or try(function() return c.StaticMesh:GetFullName() end) or "?"
                    local vis = try(function() return c:IsVisible() end)
                    n = n + 1
                    if n <= 80 then log("laser diag " .. tag .. ": " .. cls .. " " .. c:GetFName():ToString() .. " owner=" ..
                        (valid(o) and o:GetFName():ToString() or "none") .. " vis=" .. tostring(vis) .. " asset=" .. asset) end
                end)
            end
        end)
    end
    log("laser diag " .. tag .. ": " .. n .. " FX/mesh components on EVE + attached actors + active FX nearby")
end

-- v0.25 HUD diagnostic (to-do #2, ammo counter). While drone-aiming, the bottom slot of the bottom-left quick-slot
-- column swaps to the current ammo (icon + count, e.g. Stinger 32). Log every live UserWidget whose class looks like a
-- HUD slot / bullet / clip widget, with visibility and its owning widget chain, so that slot can be found and reused.
-- Runs from one-shot ExecuteWithDelay -> ExecuteInGameThread calls, at most HUD_DIAG_MAX times per session.
local HUD_PAT = { "slot", "bullet", "ammo", "clip", "quick", "crosskey", "potion", "tps", "nikke", "mainhud", "hud" }
local HUD_SKIP = { "setting", "gamemenu", "inventory", "shop", "equip", "skilltree", "worldmap", "photo" }
local hudDiagN, HUD_DIAG_MAX = 0, 6
-- v0.26: only VISIBLE widgets, settings/menu trees skipped (v0.25 logged 120 hidden settings slots and nothing else)
local function hudDiag(tag)
    if not CFG.HUD_DIAG or hudDiagN >= HUD_DIAG_MAX then return end
    hudDiagN = hudDiagN + 1
    local all = FindAllOf("UserWidget")
    if not all then log("hud diag " .. tag .. ": no UserWidgets"); return end
    local n, shown, logged = 0, 0, 0
    for _, w in ipairs(all) do
        pcall(function()
            local cls = w:GetClass():GetFName():ToString()
            local lc = cls:lower()
            local hit = false
            for _, p in ipairs(HUD_PAT) do if lc:find(p, 1, true) then hit = true; break end end
            if not hit then return end
            n = n + 1
            if not try(function() return w:IsVisible() end) then return end
            local chain, o, guard = {}, try(function() return w:GetOuter() end), 0
            while o and guard < 6 and try(function() return o:IsValid() end) do
                guard = guard + 1
                local on = try(function() return o:GetFName():ToString() end) or "?"
                if on ~= "WidgetTree" then chain[#chain + 1] = on end
                o = try(function() return o:GetOuter() end)
            end
            local ch = table.concat(chain, "<")
            local lch = (lc .. ch):lower()
            for _, k in ipairs(HUD_SKIP) do if lch:find(k, 1, true) then return end end
            shown = shown + 1
            if logged < 150 then
                logged = logged + 1
                local path = try(function() return w:GetClass():GetFullName() end) or cls
                log(string.format("hud diag %s: %s | %s | in=%s", tag, w:GetFName():ToString(), path, ch))
            end
        end)
    end
    log(string.format("hud diag %s: %d matching, %d visible HUD widgets logged (gunOn=%s, scanned %d)", tag, n, shown, tostring(gunOn), #all))
end
-- v0.26: REAL_AMMO's broadcast hooks never fire in single player (v0.25 laptop test: 60 granted, no "ammo:" line). List
-- the reflected functions that could read the Bullet_Nikke count, once per session.
local fnDiagDone = false
local FN_CLASSES = { "/Script/SB.SBBlueprintLibrary", "/Script/SB.SBCharacter", "/Script/SB.SBPlayerController",
                     "/Script/SB.SBNetworkPlayerController", "/Script/SB.SBNetworkPlayerState", "/Script/SB.SBPlayerState",
                     "/Script/SB.SBItemBucket", "/Script/SB.SBItemInstance", "/Script/SB.SBGameInstance" }
local function fnDiag()
    if fnDiagDone then return end
    fnDiagDone = true
    for _, path in ipairs(FN_CLASSES) do
        pcall(function()
            local c = StaticFindObject(path)
            if not valid(c) then log("fn diag: " .. path .. " not found"); return end
            local names = {}
            c:ForEachFunction(function(f)
                local nm = f:GetFName():ToString()
                local l = nm:lower()
                if l:find("item", 1, true) or l:find("bullet", 1, true) or l:find("ammo", 1, true) or l:find("count", 1, true)
                    or l:find("bucket", 1, true) or l:find("inventory", 1, true) then names[#names + 1] = nm end
            end)
            log("fn diag " .. path .. " (" .. #names .. "): " .. table.concat(names, ", "))
        end)
    end
end
-- v0.54: one-shot probe for a readable effect/item check (ammo counter lead). Lists matching functions on EVE's class
-- chain and on SB classes whose name has Effect/Item/Inven/Bucket in it. Off after the first Gun Mode entry.
local effProbeDone = false
local function effProbe()
    if effProbeDone or not CFG.EFFECT_PROBE then return end
    effProbeDone = true
    local p = getPawn()
    if not p then return end
    local cls = try(function() return p:GetClass() end)
    local depth = 0
    while cls and depth < 8 do
        local names = {}
        pcall(function()
            cls:ForEachFunction(function(f)
                local nm = f:GetFName():ToString(); local l = nm:lower()
                if l:find("effect", 1, true) or l:find("actorstate", 1, true) or l:find("item", 1, true) then names[#names + 1] = nm end
            end)
        end)
        log("probe " .. tostring(try(function() return cls:GetFName():ToString() end)) .. " (" .. #names .. "): " .. table.concat(names, ", "))
        depth = depth + 1
        cls = try(function() local sup = cls:GetSuperStruct(); if sup and sup:IsValid() then return sup end end)
    end
    local found = 0
    ForEachUObject(function(obj)
        pcall(function()
            if obj:GetClass():GetFName():ToString() ~= "Class" then return end
            local n = obj:GetFName():ToString()
            if not n:find("^SB") then return end
            local ln = n:lower()
            if not (ln:find("effect", 1, true) or ln:find("item", 1, true) or ln:find("inven", 1, true) or ln:find("bucket", 1, true)) then return end
            local fns = {}
            obj:ForEachFunction(function(f) fns[#fns + 1] = f:GetFName():ToString() end)
            if #fns > 0 then
                found = found + 1
                if found <= 60 then log("probe class " .. n .. ": " .. table.concat(fns, ", ", 1, math.min(#fns, 60))) end
            end
        end)
    end)
    log("probe done: " .. found .. " SB effect/item classes with functions")
end
-- v0.56: the quick slot widget (WB_MainHUD_UtilItem) - every property and function (with parameters) of its WB_/SB
-- classes. Lead: point it at Bullet_Nikke so the game itself fills in the live count. One-shot, safe (no object walk).
local slotDiagDone = false
local function slotDiag()
    if slotDiagDone or not CFG.SLOT_DIAG then return end
    slotDiagDone = true
    local w
    for _, x in ipairs(FindAllOf("WB_MainHUD_ItemSlot_C") or {}) do
        pcall(function() if x:GetFName():ToString() == "WB_MainHUD_UtilItem" then w = x end end)
    end
    if not valid(w) then log("slot diag: WB_MainHUD_UtilItem not found"); return end
    local cls, guard = w:GetClass(), 0
    while cls and guard < 6 do
        guard = guard + 1
        local cname = try(function() return cls:GetFName():ToString() end) or "?"
        if not (cname:find("^WB_") or cname:find("^SB")) then break end
        local props = {}
        pcall(function()
            cls:ForEachProperty(function(prop)
                local n = prop:GetFName():ToString()
                local ty = try(function() return prop:GetClass():GetFName():ToString() end) or "?"
                local v = try(function() local o = w[n]; if type(o) == "userdata" then return (o.ToString and o:ToString()) or "obj" end; return o end)
                props[#props + 1] = n .. ":" .. ty .. "=" .. tostring(v)
            end)
        end)
        for i = 1, #props, 15 do log("slot diag " .. cname .. " props: " .. table.concat(props, ", ", i, math.min(i + 14, #props))) end
        local fns = {}
        pcall(function()
            cls:ForEachFunction(function(f)
                local ps = {}
                pcall(function() f:ForEachProperty(function(pp) ps[#ps + 1] = pp:GetFName():ToString() .. ":" .. (try(function() return pp:GetClass():GetFName():ToString() end) or "?") end) end)
                fns[#fns + 1] = f:GetFName():ToString() .. "(" .. table.concat(ps, " ") .. ")"
            end)
        end)
        for i = 1, #fns, 10 do log("slot diag " .. cname .. " fns: " .. table.concat(fns, ", ", i, math.min(i + 9, #fns))) end
        cls = try(function() local sup = cls:GetSuperStruct(); if sup and sup:IsValid() then return sup end end)
    end
end
-- v0.57 ammo counter: the bottom quick slot (WB_MainHUD_UtilItem) is category-driven; in drone aim it shows the current
-- bullet's count. Switch it to ESBItemCategory_Bullet (13) in Gun Mode - the current bullet is Bullet_Nikke - and let the
-- game fill in the count. Restored on exit.
local ammoSlot, ammoSlotPrev = nil, nil
local function ammoHud(tag, restore)
    if not CFG.AMMO_HUD then return end
    if not valid(ammoSlot) then
        for _, x in ipairs(FindAllOf("WB_MainHUD_ItemSlot_C") or {}) do
            pcall(function() if x:GetFName():ToString() == "WB_MainHUD_UtilItem" then ammoSlot = x end end)
        end
    end
    local w = ammoSlot
    if not valid(w) then log("ammo hud " .. tag .. ": slot not found"); return end
    if restore then
        if ammoSlotPrev then
            pcall(function() w.ChangeItemCategory = ammoSlotPrev; w:ItemSlotChanged(); w:UpdateItemCount() end)
            log("ammo hud: slot back to category " .. tostring(ammoSlotPrev))
        end
        ammoSlotPrev = nil
        return
    end
    if not ammoSlotPrev then ammoSlotPrev = try(function() return w.CurrentItemCategory end) end
    local okA = pcall(function() w.ChangeItemCategory = 13 end)
    local okB = pcall(function() w:ItemSlotChanged() end)
    local okC = pcall(function() w:UpdateItemCount() end)
    log(string.format("ammo hud %s: set=%s changed=%s update=%s -> category %s count %s", tag, tostring(okA), tostring(okB), tostring(okC),
        tostring(try(function() return w.CurrentItemCategory end)), tostring(try(function() return w.ItemCount end))))
end
-- v0.58: does the NIKKE reticle widget carry an ammo count? Dump WB_Tps_Aim_C's own properties (numbers/text) - safe,
-- no object walk. Called after shots.
local aimDiagN = 0
local function aimDiag(tag)
    if not CFG.AIM_DIAG or aimDiagN >= 4 then return end
    aimDiagN = aimDiagN + 1
    for _, w in ipairs(FindAllOf("WB_Tps_Aim_C") or {}) do
        pcall(function()
            local cls, guard = w:GetClass(), 0
            while cls and guard < 3 do
                guard = guard + 1
                local cname = cls:GetFName():ToString()
                if not cname:find("^WB_") then break end
                local props = {}
                cls:ForEachProperty(function(prop)
                    local n = prop:GetFName():ToString()
                    local ty = try(function() return prop:GetClass():GetFName():ToString() end) or "?"
                    local v
                    if ty == "ObjectProperty" then
                        v = try(function() local o = w[n]; if o and o:IsValid() then
                            local c = o:GetClass():GetFName():ToString()
                            if c == "TextBlock" then return "Text'" .. o:GetText():ToString() .. "'" end
                            if c == "ProgressBar" then return "Bar " .. tostring(o.Percent) end
                            return c end end)
                    else
                        v = try(function() local o = w[n]; if type(o) == "userdata" then return o.ToString and o:ToString() or "?" end; return o end)
                    end
                    props[#props + 1] = n .. "=" .. tostring(v)
                end)
                for i = 1, #props, 14 do log("aim diag " .. tag .. " " .. w:GetFName():ToString() .. " " .. cname .. ": " .. table.concat(props, ", ", i, math.min(i + 13, #props))) end
                cls = try(function() local sup = cls:GetSuperStruct(); if sup and sup:IsValid() then return sup end end)
            end
        end)
    end
end
local function queueHudDiag(tag, ms)
    if not CFG.HUD_DIAG or hudDiagN >= HUD_DIAG_MAX then return end
    ExecuteWithDelay(ms, function() ExecuteInGameThread(function() pcall(hudDiag, tag) end) end)
end

-- v0.31 inventory + HUD-slot diagnostic (one-shot, game thread): where does the Bullet_Nikke count live, and what does
-- the bottom quick slot WB_MainHUD_UtilItem (WB_MainHUD_ItemSlot_C) expose for an icon + count?
local invDiagDone = false
local INV_KEYS = { "item", "bucket", "inventory", "bag", "bullet", "ammo", "pocket", "consum" }
local function propList(obj, tag, filter)
    local out, cls, guard = {}, try(function() return obj:GetClass() end), 0
    while cls and guard < 25 and try(function() return cls:IsValid() end) do
        guard = guard + 1
        local cname = try(function() return cls:GetFName():ToString() end) or "?"
        pcall(function()
            cls:ForEachProperty(function(prop)
                local n = try(function() return prop:GetFName():ToString() end) or "?"
                local ln = n:lower()
                local hit = not filter
                if filter then for _, k in ipairs(INV_KEYS) do if ln:find(k, 1, true) then hit = true; break end end end
                if hit then
                    local ty = try(function() return prop:GetClass():GetFName():ToString() end) or "?"
                    local extra = ""
                    if ty == "ArrayProperty" then
                        extra = " of " .. tostring(try(function() return prop:GetInner():GetClass():GetFName():ToString() end))
                        local len = try(function() return #obj[n] end)
                        if len then extra = extra .. " len " .. tostring(len) end
                    elseif ty == "ObjectProperty" then
                        local v = try(function() local o = obj[n]; if o and o:IsValid() then return o:GetFullName() end end)
                        extra = " = " .. tostring(v)
                    elseif ty == "IntProperty" or ty == "NameProperty" or ty == "StrProperty" or ty == "BoolProperty" then
                        extra = " = " .. tostring(try(function() local v = obj[n]; if type(v) == "userdata" then return v:ToString() end; return v end))
                    end
                    out[#out + 1] = cname .. "." .. n .. " (" .. ty .. extra .. ")"
                end
            end)
        end)
        cls = try(function() local sup = cls:GetSuperStruct(); if sup and sup:IsValid() then return sup end end)
    end
    for i = 1, #out, 12 do log("inv diag " .. tag .. ": " .. table.concat(out, ", ", i, math.min(i + 11, #out))) end
    if #out == 0 then log("inv diag " .. tag .. ": (none)") end
end
local function invDiag()
    if invDiagDone then return end
    invDiagDone = true
    local p, pc = getPawn(), getPC()
    local ps = pc and try(function() return pc.PlayerState end)
    local gi = try(function() return FindFirstOf("SBGameInstance") end)
    local gs = try(function() return FindFirstOf("GameStateBase") end)
    for tag, o in pairs({ pawn = p, controller = pc, playerstate = ps, gameinstance = gi, gamestate = gs }) do
        if valid(o) then pcall(propList, o, tag, true) end
    end
    -- components owned by EVE and the controller
    for tag, a in pairs({ pawn = p, controller = pc, playerstate = ps }) do
        pcall(function()
            local comps = a:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.ActorComponent"))
            local names = {}
            for _, c in ipairs(comps) do pcall(function() names[#names + 1] = c:get():GetClass():GetFName():ToString() end) end
            log("inv diag " .. tag .. " components: " .. table.concat(names, ", "))
        end)
    end
    -- any live object whose class name mentions an item bucket / inventory
    for _, cn in ipairs({ "SBItemBucketComponent", "SBInventoryComponent", "SBItemBucketManager", "SBItemManager", "SBItemSubsystem" }) do
        local o = try(function() return FindFirstOf(cn) end)
        if valid(o) then log("inv diag found " .. cn .. ": " .. o:GetFullName()); pcall(propList, o, cn, false) end
    end
    -- the bottom quick slot widget
    local slots = try(function() return FindAllOf("WB_MainHUD_ItemSlot_C") end)
    if slots then
        for _, w in ipairs(slots) do
            pcall(function()
                local n = w:GetFName():ToString()
                if n == "WB_MainHUD_UtilItem" then
                    propList(w, "UtilItem", false)
                    local fns = {}
                    w:GetClass():ForEachFunction(function(f) fns[#fns + 1] = f:GetFName():ToString() end)
                    log("inv diag UtilItem functions: " .. table.concat(fns, ", "))
                end
            end)
        end
    end
end

-- v0.32: the bottom quick slot (WB_MainHUD_UtilItem) switches to the current bullet while TPS-aiming (Stinger 32 with
-- the drone). Gun Mode makes the current bullet Bullet_Nikke, so its ItemCount may BE the Bullet_Nikke count while aiming.
-- Cache the live slot once (one-shot FindAllOf), then read its ItemCount / CurrentItemCategory from the tick (plain
-- property reads, no object walks) and log every change together with the aim state.
local utilSlot, utilLast = nil, nil
local tpsMaster, bulletSlot = nil, nil
local function findUtilSlot()
    local ws = FindAllOf("WB_MainHUD_ItemSlot_C")
    if not ws then return end
    for _, w in ipairs(ws) do
        pcall(function()
            if w:GetFName():ToString() == "WB_MainHUD_UtilItem" and valid(w.WidgetTree) then utilSlot = w end
        end)
    end
    log("util slot: " .. (utilSlot and utilSlot:GetFullName() or "not found"))
    for _, cn in ipairs({ "WB_MainHUD_TpsMaster_C", "WB_Tps_Bullet2_Slot_C" }) do
        pcall(function()
            for _, w in ipairs(FindAllOf(cn) or {}) do
                if valid(w) and valid(w.WidgetTree) then
                    if cn == "WB_MainHUD_TpsMaster_C" then tpsMaster = w else bulletSlot = w end
                end
            end
        end)
    end
    log("tps master: " .. tostring(tpsMaster and tpsMaster:GetFName():ToString()) .. ", bullet slot: " .. tostring(bulletSlot and bulletSlot:GetFName():ToString()))
end
local function utilWatch(aimNow, shotsNow)
    if not valid(utilSlot) then return end
    local p = getPawn()
    local s = string.format("count=%s cat=%s tps=%s bslot=%s/%s aim=%s stance=%s shots=%d", tostring(try(function() return utilSlot.ItemCount end)),
        tostring(try(function() return utilSlot.CurrentItemCategory end)),
        tostring(try(function() return tpsMaster.ItemCount end)), tostring(try(function() return bulletSlot.ItemCount end)),
        tostring(try(function() return bulletSlot.BulletSlotType end)), tostring(aimNow),
        tostring(p and try(function() return p:GetCurrentStanceName():ToString() end)), shotsNow or 0)
    if s ~= utilLast then
        utilLast = s
        utilLogs = (utilLogs or 0) + 1
        if utilLogs <= 120 then log("watch: " .. s) end
    end
end
-- v0.32 library scan: every /Script class whose name looks like a function library / subsystem / manager, and its
-- item-related functions (looking for a GetItemCount-style call)
local libScanDone = false
local function libScan()
    if libScanDone then return end
    libScanDone = true
    local found = 0
    ForEachUObject(function(obj)
        pcall(function()
            local cls = obj:GetClass():GetFName():ToString()
            if cls ~= "Class" then return end
            local n = obj:GetFName():ToString()
            if not n:find("^SB") then return end
            local ln = n:lower()
            if not (ln:find("library", 1, true) or ln:find("statics", 1, true) or ln:find("subsystem", 1, true) or ln:find("manager", 1, true) or ln:find("item", 1, true) or ln:find("inven", 1, true)) then return end
            local fns = {}
            obj:ForEachFunction(function(f)
                local fnn = f:GetFName():ToString()
                local l = fnn:lower()
                if l:find("item", 1, true) or l:find("count", 1, true) or l:find("bullet", 1, true) or l:find("inven", 1, true) then fns[#fns + 1] = fnn end
            end)
            if #fns > 0 then
                found = found + 1
                if found <= 40 then log("lib scan " .. n .. ": " .. table.concat(fns, ", ", 1, math.min(#fns, 40))) end
            end
        end)
    end)
    log("lib scan done: " .. found .. " classes with item functions")
end

-- v0.33 numeric HUD snapshot: which NIKKE HUD value drops when a round is spent? (BU/BE/HP/SH bars, clip counter)
local NUM_CLASSES = { "WB_MainHUD_PlayerInfo_C", "WB_NikkeHUD_Clip_C", "WB_NikkeHUD_Reload_C", "WB_MainHUD_TpsMaster_C",
                      "WB_Tps_Bullet2_Slot_C", "WB_NikkeHUD_Main_C", "WB_NikkeHUD_C" }
local numSnaps = 0
local function numSnap(tag)
    numSnaps = numSnaps + 1
    if numSnaps > 12 then return end
    for _, cn in ipairs(NUM_CLASSES) do
        pcall(function()
            local ws = FindAllOf(cn)
            if not ws then return end
            for _, w in ipairs(ws) do
                pcall(function()
                    if not valid(w.WidgetTree) then return end
                    local vals, cls, guard = {}, w:GetClass(), 0
                    while cls and guard < 3 and cls:IsValid() do
                        guard = guard + 1
                        cls:ForEachProperty(function(prop)
                            local ty = try(function() return prop:GetClass():GetFName():ToString() end)
                            if ty == "IntProperty" or ty == "FloatProperty" or ty == "ByteProperty" or ty == "BoolProperty" then
                                local n = prop:GetFName():ToString()
                                vals[#vals + 1] = n .. "=" .. tostring(try(function() return w[n] end))
                            end
                        end)
                        cls = try(function() local sup = cls:GetSuperStruct(); if sup and sup:IsValid() and sup:GetFName():ToString():find("^WB_") then return sup end end)
                    end
                    log("num snap " .. tag .. " " .. cn .. " " .. w:GetFName():ToString() .. " vis=" .. tostring(try(function() return w:IsVisible() end)) .. ": " .. table.concat(vals, " "))
                end)
            end
        end)
    end
end

-- v0.61 posture. STANDING: the NIKKE aim stance is kept on without the aim key (the stance needs command key TPSMode
-- pressed - we tell the game it is, through ServerRequest_ActorStancePressCommandKey), no cover position.
-- CROUCHED: key released, centre cover (Position2) on = the DLC's own crouch / cover with its side rolls.
crouched = false
local pressVariant, pressLogged = nil, 0   -- v0.68: no aim-key faking - zNikkeGunStand_P drops the aim-key condition from the P_Eve_GunNikke stance; was "SkillCommandState_TPSMode"   -- v0.66: this one worked (11-17 08:49) once the NIKKE effect was on; the 0.5 s keep-alive re-presses it
local PRESS_VARIANTS = {}   -- v0.68: off (see pressVariant)
local function pressAim(on, variant)
    local pc = getPC(); local g = eveGUID or CFG.EVE_GUID_GUESS
    if not pc then return false end
    local v = variant or pressVariant or PRESS_VARIANTS[1]
    if not v then return false end   -- v0.69b: no variant = no aim-key faking (nil here broke the crouch toggle, 11-17 10:39)
    local ok, err = pcall(function() pc:ServerRequest_ActorStancePressCommandKey(g, FName(v), on) end)
    if not ok and pressLogged < 5 then pressLogged = pressLogged + 1; log("aim hold: press call failed (" .. v .. "): " .. tostring(err)) end
    return ok
end
local function aimStanceNow()
    local p = getPawn()
    return p and try(function() return p:GetCurrentStanceName():ToString() end) == "P_Eve_GunNikke"
end
-- find which stance-key argument works: try each, check the stance 0.4 s later
local function probePress(k)
    k = k or 1
    if not gunOn or crouched or not CFG.STANDING then return end
    if pressVariant then pressAim(true); return end
    local v = PRESS_VARIANTS[k]
    if not v then log("aim hold: no variant brought up the aim stance - hold Ctrl / L2 to aim for now"); return end
    pressAim(true, v)
    ExecuteWithDelay(400, function() ExecuteInGameThread(function()
        if not gunOn then return end
        if aimStanceNow() then pressVariant = v; log("aim hold: standing aim kept on via stance key '" .. v .. "'")
        else pressAim(false, v); probePress(k + 1) end
    end) end)
end
-- v0.66 experiment: SBCharacter:ActiveCustomMovingStanceData(SBCharMovingStanceData) has OverrideStanceAnim (an
-- animset name). If it overrides the locomotion animset whatever the stance, standing = override on, crouch = off.
local overrideOn, overrideLogs = false, 0
function standOverride(on, tag)
    if not CFG.STAND_OVERRIDE then return end
    local p = getPawn(); if not p then return end
    local ok, err
    -- v0.67c guard: the override names an animset row whose blend space must exist; load it first, skip if it doesn't
    if on and CFG.STAND_OVERRIDE_ASSET and not standAssetOk then
        local a = try(function() return LoadAsset(CFG.STAND_OVERRIDE_ASSET) end)
        standAssetOk = (a ~= nil and try(function() return a:IsValid() end)) and true or false
        log("stand override: " .. CFG.STAND_OVERRIDE_ASSET .. " loaded=" .. tostring(standAssetOk))
        if not standAssetOk then return end
    end
    if on then
        ok, err = pcall(function() p:ActiveCustomMovingStanceData({ ForceType = 0, OverrideStanceAnim = FName(CFG.STAND_OVERRIDE),
            NormalAnimRangeDegree = 180.0, ForceRadius = 0.0, InitialForce = 0.0, MaxForce = 0.0 }) end)
    else
        ok, err = pcall(function() p:DeactiveCustomMovingStanceData() end)
    end
    overrideOn = on and ok
    if overrideLogs < 12 then overrideLogs = overrideLogs + 1
        ExecuteWithDelay(300, function() ExecuteInGameThread(function()
            local p2 = getPawn()
            log("stand override " .. (on and ("ON '" .. CFG.STAND_OVERRIDE .. "'") or "OFF") .. " (" .. tostring(tag) .. "): call ok=" .. tostring(ok)
                .. (err and (" err=" .. tostring(err)) or "") .. " active=" .. tostring(p2 and try(function() return p2:IsActiveCustomMovingStanceData() end))
                .. " stance=" .. tostring(p2 and try(function() return p2:GetCurrentStanceName():ToString() end)))
        end) end)
    end
end
-- v0.68b: bring the aim stance up without the aim key (the stance table no longer requires it). Tries, in order:
-- 1 ServerRequest_ActorStancePressCommandKey(guid, "P_Eve_GunNikke", true) - the 2nd argument is the STANCE alias
-- 2 ClientBroadcast_ActorSetStance(turn 0, guid, "P_Eve_GunNikke", true)
-- and logs the stance 1.2 s after each. The method that works is kept (aimMethod) and re-used by the keep-alive.
aimMethod = nil
local AIM_METHODS = {
    { "press stance alias", function(pc, g) pc:ServerRequest_ActorStancePressCommandKey(g, FName("P_Eve_GunNikke"), true) end },
    { "set stance", function(pc, g) pc:ClientBroadcast_ActorSetStance(0, g, FName("P_Eve_GunNikke"), true) end },
    { "press current stance alias (Hide)", function(pc, g) pc:ServerRequest_ActorStancePressCommandKey(g, FName("P_Eve_GunNikkeHide"), true) end },
    { "tap P_Eve_GunNikke (true, false 300 ms)", function(pc, g)
        pc:ServerRequest_ActorStancePressCommandKey(g, FName("P_Eve_GunNikke"), true)
        ExecuteWithDelay(300, function() ExecuteInGameThread(function() pcall(function() pc:ServerRequest_ActorStancePressCommandKey(g, FName("P_Eve_GunNikke"), false) end) end) end)
    end },
    { "tap Hide alias (true, false 300 ms)", function(pc, g)
        pc:ServerRequest_ActorStancePressCommandKey(g, FName("P_Eve_GunNikkeHide"), true)
        ExecuteWithDelay(300, function() ExecuteInGameThread(function() pcall(function() pc:ServerRequest_ActorStancePressCommandKey(g, FName("P_Eve_GunNikkeHide"), false) end) end) end)
    end },
    { "tap SkillCommandState_TPSMode", function(pc, g)
        pc:ServerRequest_ActorStancePressCommandKey(g, FName("SkillCommandState_TPSMode"), true)
        ExecuteWithDelay(300, function() ExecuteInGameThread(function() pcall(function() pc:ServerRequest_ActorStancePressCommandKey(g, FName("SkillCommandState_TPSMode"), false) end) end) end)
    end },
    { "console SBPlayerChangeStance", function(pc, g)
        local lib = StaticFindObject("/Script/SB.Default__SBBlueprintLibrary")
        local r = lib:ConsoleCommand("SBPlayerChangeStance P_Eve_GunNikke", true)
        log("aim up: ConsoleCommand returned " .. tostring(r))
    end },
    { "cheat manager SBPlayerChangeStance", function(pc, g)
        local cm = pc.CheatManager
        if not (cm and cm:IsValid()) then
            local cls = StaticFindObject("/Script/SB.SBCheatManager")
            cm = StaticConstructObject(cls, pc)
            pc.CheatManager = cm
            log("aim up: cheat manager constructed: " .. tostring(cm and cm:IsValid()))
        end
        cm:SBPlayerChangeStance("P_Eve_GunNikke")
    end },
}
function aimUp(k, tag)
    if not gunOn or crouched then return end
    local pc = getPC(); local g = eveGUID or CFG.EVE_GUID_GUESS
    if not pc then return end
    if aimMethod then pcall(AIM_METHODS[aimMethod][2], pc, g); return end
    k = k or 1
    local m = AIM_METHODS[k]
    if not m then log("aim up: no method brought up P_Eve_GunNikke (" .. tostring(tag) .. ")"); return end
    local ok, err = pcall(m[2], pc, g)
    if k == 1 then log("aim up: guid " .. tostring(g) .. " (eveGUID " .. tostring(eveGUID) .. ")") end
    ExecuteWithDelay(1200, function() ExecuteInGameThread(function()
        if not gunOn then return end
        local st = aimStanceNow()
        log("aim up [" .. m[1] .. "] call ok=" .. tostring(ok) .. (err and (" err=" .. tostring(err)) or "") .. " -> aim stance " .. tostring(st))
        if st then aimMethod = k else aimUp(k + 1, tag) end
    end) end)
end
-- v0.69: zNikkeGunStand_P makes the cover stance P_Eve_GunNikkeHide the STANDING stance (gun out, stand anims), so
-- CROUCHED puts the NIKKE kneel back with the animset override (ActiveCustomMovingStanceData, proven 11-17 09:20)
function crouchOverride(on, tag)
    if not CFG.CROUCH_OVERRIDE then return end
    local p = getPawn(); if not p then return end
    local ok, err
    if on then ok, err = pcall(function() p:ActiveCustomMovingStanceData({ ForceType = 0, OverrideStanceAnim = FName(CFG.CROUCH_OVERRIDE), NormalAnimRangeDegree = 180.0 }) end)
    else ok, err = pcall(function() p:DeactiveCustomMovingStanceData() end) end
    log("crouch override " .. (on and "ON" or "OFF") .. " (" .. tostring(tag) .. "): ok=" .. tostring(ok) .. (err and (" " .. tostring(err)) or ""))
end
local function applyPosture(tag)
    if crouched then
        pressAim(false)
        pcall(fireRow, {2, "NGM_AE_Pos2"})
        pcall(standOverride, false, tag)
        pcall(crouchOverride, true, tag)
        log("posture: CROUCHED (" .. tag .. ") - NIKKE cover, Shift/Circle + direction rolls, Ctrl/L2 to aim")
    else
        pcall(fireRow, {2, "NGM_AE_PosOff"})
        if CFG.AIM_UP_PROBE then ExecuteWithDelay(800, function() ExecuteInGameThread(function() pcall(aimUp, 1, tag) end) end) end
        pcall(standOverride, true, tag)
        pcall(crouchOverride, false, tag)
        log("posture: STANDING (" .. tag .. ")")
    end
end
-- v0.61 HUD keep: the root widgets on screen before Gun Mode; anything of those the NIKKE mode hides is shown again
local hudSnap, hudLogged = {}, {}
-- v0.62: the 5 roots stay visible (v0.61 log) - the NIKKE mode hides widgets INSIDE WB_MainHUD_Master. Walk the trees.
local function hudWalk(w, depth, out, path)
    if #out > 1500 or depth > 12 then return end
    local nm = try(function() return w:GetFName():ToString() end) or "?"
    local vis = try(function() return w:GetVisibility() end)
    local op = try(function() return w:GetRenderOpacity() end)
    if vis ~= nil then out[#out + 1] = { w = w, vis = vis, op = op or 1.0, name = path .. "/" .. nm } end
    local n = try(function() return w:GetChildrenCount() end)
    if n and n > 0 then
        for i = 0, n - 1 do
            local c = try(function() return w:GetChildAt(i) end)
            if c and valid(c) then hudWalk(c, depth + 1, out, path .. "/" .. nm) end
        end
    end
    local root = try(function() local t = w.WidgetTree; if t and valid(t) then return t.RootWidget end end)
    if root and valid(root) then hudWalk(root, depth + 1, out, path .. "/" .. nm) end
end
local function hudSnapshot()
    hudSnap = {}
    local all = FindAllOf("UserWidget")
    if not all then return end
    local roots = 0
    for _, w in ipairs(all) do
        pcall(function()
            if w:IsInViewport() and w:IsVisible() then
                roots = roots + 1
                local out = {}
                hudWalk(w, 0, out, "")
                for _, e in ipairs(out) do
                    -- remember only widgets that are showing now (Visible 0 / HitTestInvisible 3 / SelfHitTestInvisible 4)
                    if (e.vis == 0 or e.vis == 3 or e.vis == 4) and e.op > 0.05 then hudSnap[#hudSnap + 1] = e end
                end
            end
        end)
    end
    log("hud: " .. roots .. " roots, " .. #hudSnap .. " visible widgets inside them before Gun Mode")
end
local function hudRestore(tag)
    if not CFG.KEEP_HUD then return end
    local n = 0
    for _, e in ipairs(hudSnap) do
        pcall(function()
            if not valid(e.w) then return end
            local vis, op = e.w:GetVisibility(), e.w:GetRenderOpacity()
            local inv = true
            if e.name:find("Tps", 1, true) or e.name:find("Nikke", 1, true) or e.name:find("Aim", 1, true) then return end
            if (vis == 1 or vis == 2) or op < e.op * 0.5 then
                if not hudLogged[e.name] then
                    hudLogged[e.name] = true
                    log(string.format("hud (%s): %s was hidden by Gun Mode (vis %s -> %s, opacity %.2f -> %.2f, in viewport %s) - shown again",
                        tag, e.name, tostring(e.vis), tostring(vis), e.op, op, tostring(inv)))
                end
                e.w:SetVisibility(e.vis)
                if op < e.op then e.w:SetRenderOpacity(e.op) end
                n = n + 1
            end
        end)
    end
    if n > 0 and hudRestoreLogs < 6 then hudRestoreLogs = hudRestoreLogs + 1; log("hud (" .. tag .. "): " .. n .. " widget(s) shown again") end
    return n
end
hudRestoreLogs = 0
rollLogs = 0
hudNextAt = 0

local function enable()
    if not getPawn() then log("no player yet"); return end
    -- v0.60: the bag ran dry last time - don't flash in and out (desktop 11-16: 4 entries in 20 s, each dropped by
    -- EmptyExit). Buy NIKKE Rounds at a camp shop, or Ctrl+F12 (test build) for +60.
    if CFG.REAL_AMMO and bagEmpty then
        log("Gun Mode not started: out of NIKKE Rounds (buy them at a camp shop, or Ctrl+F12 = +60 in this test build)")
        return
    end
    queueHudDiag("gun-entry+1.5s", 1500)
    if CFG.AMMO_WATCH and not CFG.HUD_DIAG then
        ExecuteWithDelay(2000, function() ExecuteInGameThread(function() pcall(findUtilSlot) end) end)
    end
    if CFG.HUD_DIAG then
        ExecuteWithDelay(2500, function() ExecuteInGameThread(function() pcall(fnDiag) end) end)
        ExecuteWithDelay(2000, function() ExecuteInGameThread(function() pcall(findUtilSlot) end) end)
        ExecuteWithDelay(3000, function() ExecuteInGameThread(function() pcall(numSnap, "entry") end) end)
        ExecuteWithDelay(5000, function() ExecuteInGameThread(function() pcall(libScan) end) end)
    end
    hudLogged = {}
    if CFG.KEEP_HUD then pcall(hudSnapshot) end
    for _, r in ipairs(ON_ROWS) do fireRow(r) end
    do local b = curBullet(); if b ~= "Bullet_Nikke" or not prevBullet then prevBullet = b end end
    gunOn = true
    if CFG.FORCE_BULLET and setBullet("Bullet_Nikke") then startKeeper() end
    startHold()
    pcall(hookTick)
    crouched = not CFG.STANDING
    ExecuteWithDelay(700, function() ExecuteInGameThread(function() if gunOn then applyPosture("entry") end end) end)
    for _, ms in ipairs({1000, 2500}) do
        ExecuteWithDelay(ms, function() ExecuteInGameThread(function() if gunOn then pcall(hudRestore, "entry+" .. ms) end end) end)
    end
    hudNextAt = os.clock() + 4.0
    ExecuteWithDelay(1500, function() ExecuteInGameThread(function() if gunOn then pcall(laserSwap, "1.5s") end end) end)
    ExecuteWithDelay(4000, function() ExecuteInGameThread(function() if gunOn then pcall(laserSwap, "4s") end end) end)
    if CFG.RETICLE_SCALE and CFG.RETICLE_SCALE ~= 1.0 then
        ExecuteWithDelay(800, function() ExecuteInGameThread(function() if gunOn then setReticle(CFG.RETICLE_SCALE) end end) end)
    end
    if CFG.AMMO_HUD then
        for _, ms in ipairs({1200, 2500}) do
            ExecuteWithDelay(ms, function() ExecuteInGameThread(function() if gunOn then pcall(ammoHud, "entry+" .. ms) end end) end)
        end
    end
    if CFG.SLOT_DIAG then
        ExecuteWithDelay(3000, function() ExecuteInGameThread(function() pcall(slotDiag) end) end)
    end
    if CFG.WIDE_RETICLE then
        ExecuteWithDelay(900, function() ExecuteInGameThread(function() if gunOn then pcall(wideReticle, true) end end) end)
    end
    pcall(hookBattle)
    if CFG.FACE_AIM then pcall(hookAim) end
    -- v0.9b/v0.24: ammo. With REAL_AMMO the count comes from the item broadcasts; a starter stack is granted once per
    -- session while she has none (or the count isn't known yet).
    pcall(hookAmmo)
    -- v0.40: ammo moves through item-action rows (zone event type 13), which need no actor GUID:
    -- NGM_ItemA_Ammo = +60 Bullet_Nikke (the one-time starter), NGM_ItemA_Spend = -1 per shot.
    if CFG.REAL_AMMO and not starterGiven then
        starterGiven = true
        local flag = (MODFOLDER or ".") .. "\\NikkeGunMode_starter_given_v8.txt"
        local f = io.open(flag, "r")
        if f then f:close(); log("ammo: starter already given on this install")
        else
            local ok = fireRow({13, "NGM_ItemA_Ammo"})
            log("ammo: starter +60 Bullet_Nikke (NGM_ItemA_Ammo) " .. (ok and "sent" or "FAILED"))
            if ok then local w = io.open(flag, "w"); if w then w:write(os.date()); w:close() end end
        end
    elseif not CFG.REAL_AMMO then
        fireRow({13, "NGM_ItemA_Ammo"})
    end
    if CFG.REAL_AMMO then
        -- v0.49: clear a stuck P_Eve_GunNikke_BulletZero (set when the gun came on with 0 rounds, e.g. before the starter
        -- landed; only the now-blocked reload cleared it). NGM_AE_ZeroOff is conditional: only with rounds in the bag.
        for _, ms in ipairs({600, 1600}) do
            ExecuteWithDelay(ms, function() ExecuteInGameThread(function() if gunOn then pcall(fireRow, {2, "NGM_AE_ZeroOff"}) end end) end)
        end
        ExecuteWithDelay(2200, function() ExecuteInGameThread(function() if gunOn then pcall(fireRow, {2, "NGM_AE_EmptyExit"}) end end) end)
    end
    if CFG.NATIVE_SWITCHES then log("native stage switches: " .. native("ngm_on")) end
    if CFG.GUID_SEARCH and not eveGUID and not scanning then eveGUID = CFG.EVE_GUID_GUESS end   -- 1501, confirmed by the search on 11-14 and 11-15
    startDiag()
    log("Gun Mode ON requested")
    ExecuteWithDelay(CFG.VERIFY_DELAY_MS, function()
        ExecuteInGameThread(function()
            local s, isTps, mtype = modeInfo()
            if isTps and tonumber(mtype) == 2 then
                log("Gun Mode engaged: " .. s .. "  bullet=" .. tostring(curBullet()) .. " (was " .. tostring(prevBullet) .. ")")
            else
                log("Gun Mode did NOT engage (" .. s .. "). Send this log line to Claude.")
            end
        end)
    end)
end

local function disable()
    if CFG.NATIVE_SWITCHES then log("native restore: " .. native("ngm_off")) end
    -- v0.50: a NIKKE reload still pending at exit went through the moment NGM_RealAmmo came off and refilled the bag to
    -- 60 (laptop 11-16: ran dry, bag showed 60 after). Cancel it first, again a little later, then lift the marker.
    if CFG.REAL_AMMO then
        pcall(fireRow, {2, "NGM_AE_ReloadCancel"})
        ExecuteWithDelay(1500, function() ExecuteInGameThread(function() if not gunOn then pcall(fireRow, {2, "NGM_AE_ReloadCancel"}) end end) end)
        ExecuteWithDelay(4000, function() ExecuteInGameThread(function()
            if not gunOn then pcall(fireRow, {2, "NGM_AE_ReloadCancel"}); pcall(fireRow, {2, "NGM_AE_RealAmmoOff"}) end
        end) end)
    end
    pcall(pressAim, false)
    pcall(standOverride, false, "exit")
    pcall(crouchOverride, false, "exit")
    if CFG.STAND_TPS_ZERO then pcall(tpsSetMode, 2, "exit") end   -- v0.70c
    pcall(laserSightOff)   -- v0.70g
    pcall(ownReticleOff)   -- v0.70j
    pcall(camOffsetOff)    -- v0.70n
    for _, r in ipairs(OFF_ROWS) do fireRow(r) end
    -- v0.60: an ON->OFF within ~2 s left the gun stance stuck on (desktop 11-16 18:58:59): the entry rows were still
    -- landing after the OFF rows. Send the OFF rows again once they have, unless Gun Mode was switched back on.
    offSerial = (offSerial or 0) + 1
    local myOff = offSerial
    for _, ms in ipairs({1200, 3000}) do
        ExecuteWithDelay(ms, function() ExecuteInGameThread(function()
            if gunOn or myOff ~= offSerial then return end
            for _, r in ipairs(OFF_ROWS) do pcall(fireRow, r) end
        end) end)
    end
    if eveGUID and prevBullet and prevBullet ~= "Bullet_Nikke" then setBullet(prevBullet) end
    gunOn = false
    outOfAmmoLogged = false
    if CFG.RETICLE_SCALE and CFG.RETICLE_SCALE ~= 1.0 then pcall(setReticle, 1.0) end
    pcall(wideReticle, false)
    pcall(ammoHud, "exit", true)
    pcall(laserRestore)
    keepRun = keepRun + 1
    holdRun = holdRun + 1
    local p = getPawn()
    if p and prevBullet and prevBullet ~= "None" then
        pcall(function() p.CurrentBulletItemAlias = FName(prevBullet) end)
        if CFG.LOOKAT then pcall(function() p.CustomLookAtActive = false end) end
    end
    log("Gun Mode OFF (bullet reverts while on: " .. reverts .. ")   (" .. (modeInfo()) .. ")")
end

local function toggle()
    if gunOn then disable() else enable() end
end

-------------------------------------------------------------------------------
-- v0.7 firing: ServerRequest_UseSkill straight from Lua
-------------------------------------------------------------------------------
local fireN, lastFire = 0, -1
local fireVia = "zone"
local fireRoute = "effect"   -- v0.11: "useskill" (aimed) or "effect" (NGM_Fire zone row); Ctrl+Shift+G switches
local function vec(v) return { X = v.X, Y = v.Y, Z = v.Z } end
local function fireOnce()
    if not gunOn then return end
    local p, pc = getPawn(), getPC()
    if not (p and pc) then return end
    local now = os.clock()
    if now - lastFire < CFG.FIRE_INTERVAL then return end
    lastFire = now
    local g = eveGUID or CFG.EVE_GUID_GUESS
    local target = try(function() return p:GetTPSLookAtWorldLocation(true) end)
    local from = try(function() return p:K2_GetActorLocation() end)
    local loc, dir = { X = 0, Y = 0, Z = 0 }, { X = 1, Y = 0, Z = 0 }
    if target and from then
        loc = vec(target)
        local dx, dy, dz = target.X - from.X, target.Y - from.Y, target.Z - from.Z
        local len = math.sqrt(dx * dx + dy * dy + dz * dz)
        if len > 0.001 then dir = { X = dx / len, Y = dy / len, Z = dz / len } end
        -- v0.10c: the NonTarget projectile flies along EVE's facing, and the game snaps her facing back to the (fixed)
        -- camera yaw within a frame (11-15 log: -132 -> -118 after 60 ms). So remember the aim yaw and re-apply it on
        -- every EVE tick while firing (aimTick below), so it is still in place when the shot's projectile spawns.
        if CFG.FACE_AIM and (dx * dx + dy * dy) > 1 then
            aimYaw = math.deg(math.atan(dy, dx))
            aimUntil = os.clock() + 0.25
            pcall(applyAimYaw, p)
        end
    end
    if CFG.REAL_AMMO and nikkeAmmo and nikkeAmmo <= 0 then
        if not outOfAmmoLogged then outOfAmmoLogged = true; log("ammo: out of Bullet_Nikke - leaving Gun Mode") end
        ExecuteWithDelay(200, function() ExecuteInGameThread(function() if gunOn then pcall(toggle) end end) end)
        return
    end
    fireN = fireN + 1
    if CFG.REAL_AMMO then
        local okR, errR = pcall(fireRow, {13, "NGM_ItemA_Spend"})   -- v0.40: row spend, no GUID
        pcall(fireRow, {2, "NGM_AE_EmptyExit"})                       -- v0.42: applies only once the bag is empty
        if CFG.AIM_DIAG and (fireN == 3 or fireN == 15) then
            local fnn = fireN
            ExecuteWithDelay(50, function() ExecuteInGameThread(function() pcall(aimDiag, "shot" .. fnn) end) end)
        end
        if nikkeAmmo then nikkeAmmo = nikkeAmmo - 1 end
        if not okR and spendErrs < 3 then spendErrs = spendErrs + 1; log("ammo: spend failed " .. tostring(errR)) end
    end
    if CFG.AMMO_TOPUP_EVERY and fireN % CFG.AMMO_TOPUP_EVERY == 0 then
        pcall(function() pc:ServerRequest_ItemBucketItemAdd(1, g, FName("Bullet_Nikke"), 60, 0, true, false, false, {}) end)
        log("ammo top-up: +60 Bullet_Nikke after " .. fireN .. " shots")
    end
    local n = fireN
    -- v0.9: start the shot skill through an effect whose action is UseSkill (StellarCoop's way, cut/chainspin.lua),
    -- skipping the stance/command checks that ignored ServerRequest_UseSkill. Route: the zone event row (default) or
    -- with Shift held, SB's cheat request SBApplyEffectMe on EVE's GUID (the call StellarCoop makes).
    -- v0.11: default route is SB's own fire request again, now that the shot's fire step no longer needs the command's
    -- bullet: ServerRequest_UseSkill carries the aim point + direction (the effect route fires along world +X = "north").
    if CFG.AIM_ROW_WRITE and target then pcall(aimRowWrite, p, target) end
    local route = fireRoute
    local ok, err = pcall(function()
        if route == "useskill" then
            pc:ServerRequest_UseSkill(g, CFG.FIRE_COMMAND, CFG.FIRE_SKILL_ID, FName(CFG.FIRE_NODE), {}, loc, dir)
        else
            -- v0.12: an effect-started shot flies along the skill's input direction, which is EVE's movement input -
            -- zero in Gun Mode, hence world +X ("north"). Feed a movement input toward the aim point first.
            if CFG.INPUT_AIM then
                local hl = math.sqrt(dir.X * dir.X + dir.Y * dir.Y)
                if hl > 0.001 then
                    pcall(function() p:AddMovementInput({ X = dir.X / hl, Y = dir.Y / hl, Z = 0 }, 1.0, true) end)
                end
            end
            fireRow({ 2, CFG.FIRE_ZONE_ROW })
        end
    end)
    local stance = try(function() return p:GetCurrentStanceName():ToString() end)
    if n > 5 and n % 20 ~= 0 then return end
    log(string.format("fire #%d [" .. route .. "]: shot(guid %s) %s  stance=%s aim=(%.0f,%.0f,%.0f)", n, tostring(g),
        ok and "sent" or ("FAILED " .. tostring(err)), tostring(stance), loc.X, loc.Y, loc.Z))
end

-- v0.10 full auto: Windows key repeat waits ~0.5 s and then stutters, so on the first Ctrl+LMB press run our own loop
-- that fires every FIRE_INTERVAL while the game reports both keys still held (PlayerController:IsInputKeyDown).
local autoRun = 0
local fireHeld
local shotsFired = 0
local aimHeld, aimSince = false, 0
local function keyDown(pc, name)
    local ok, down = pcall(function() return pc:IsInputKeyDown({ KeyName = FName(name) }) end)
    return ok and down
end
-- v0.16: mouse (Ctrl+LMB) or controller (L2 aim + R2 fire)
fireHeld = function(pc)
    if CFG.STANDING and not crouched and (keyDown(pc, "LeftMouseButton") or keyDown(pc, "Gamepad_RightTrigger")) then return true end   -- v0.61
    if keyDown(pc, "LeftMouseButton") and (keyDown(pc, "LeftControl") or keyDown(pc, "RightControl")) then return true end
    return keyDown(pc, "Gamepad_RightTrigger") and keyDown(pc, "Gamepad_LeftTrigger")
end
-- v0.18: full auto runs from the central EVE tick: firing = true, nextShot = when the next shot is due
local firing, nextShot = false, 0
local waitStart, notAimingLogs = nil, 0
local function fireStep(now)
    if not firing then return end
    if not gunOn then firing = false; return end
    if now < nextShot then return end
    local pc = getPC()
    if shotsFired > 0 and not (pc and fireHeld(pc)) then
        firing = false
        local n = shotsFired
        if CFG.HUD_DIAG then ExecuteWithDelay(800, function() ExecuteInGameThread(function() pcall(numSnap, "after " .. n .. " shots") end) end) end
        return
    end
    -- v0.29 CRASH GUARD: only fire in the AIM stance P_Eve_GunNikke. In the crouch stance P_Eve_GunNikkeHide the gun is
    -- folded away (bForceFoldingWeapon) and the shot's projectile starts at the gun's muzzle socket SC_GunShoot -> the
    -- game read a null pointer (SB-Win64-Shipping.exe+0x10e1be8, reading 0x38) and crashed, twice on the laptop (11-16),
    -- both times with stance=P_Eve_GunNikkeHide (a quick Ctrl+click never brought the aim pose up).
    local p = getPawn()
    local stance = p and try(function() return p:GetCurrentStanceName():ToString() end)
    local fireOk = stance == "P_Eve_GunNikke" or (CFG.FIRE_IN_COVER_STANCE and stance == "P_Eve_GunNikkeHide" and not crouched)
    if not fireOk then
        if not waitStart then waitStart = now end
        if now - waitStart > 1.0 then
            firing = false; waitStart = nil
            notAimingLogs = notAimingLogs + 1
            if notAimingLogs <= 5 then log("fire: not in the aim stance (" .. tostring(stance) .. ") - shot cancelled (hold Ctrl / L2 to aim)") end
        end
        return
    end
    waitStart = nil
    shotsFired = shotsFired + 1
    local ok, err = pcall(fireOnce)
    if not ok then log("fire error: " .. tostring(err)) end
    if not CFG.FULL_AUTO then firing = false end
    nextShot = now + CFG.FIRE_INTERVAL
end
local function startFiring()
    if not gunOn or firing then return end
    fireVia = "zone"
    firing, shotsFired = true, 0
    -- v0.14/v0.19: let the gun come up into the shoot pose first
    local now = os.clock()
    if not aimHeld then aimSince = now; aimHeld = true end
    nextShot = math.max(now + CFG.FIRST_SHOT_DELAY, aimSince + CFG.AIM_READY)
end
RegisterKeyBind(CFG.FIRE_KEY, { ModifierKey.CONTROL }, function()
    ExecuteInGameThread(function() pcall(startFiring) end)
end)

-------------------------------------------------------------------------------
-- v0.7f snapshot: write every simple property of EVE, the controller, the player state and the game state to
-- NikkeGunMode_snap_<n>.txt, so a real NIKKE stage can be diffed against our Gun Mode (Ctrl+Shift+G).
-------------------------------------------------------------------------------
local snapN = 0
local function fmtVal(v)
    local t = type(v)
    if t == "number" or t == "boolean" or t == "string" then return tostring(v) end
    if t == "userdata" then
        local s = try(function() return v:ToString() end)
        if s ~= nil then return "\"" .. tostring(s) .. "\"" end
        local fn = try(function() if v.IsValid and v:IsValid() then return v:GetFullName() end end)
        if fn then return "<" .. fn .. ">" end
        local n = try(function() return #v end)
        if n then return "[len " .. tostring(n) .. "]" end
    end
    return nil
end
local function dumpObj(f, tag, obj)
    if not valid(obj) then f:write("== " .. tag .. ": none\n"); return end
    f:write("== " .. tag .. ": " .. tostring(try(function() return obj:GetFullName() end)) .. "\n")
    local cls = try(function() return obj:GetClass() end)
    local guard = 0
    while cls and guard < 20 and try(function() return cls:IsValid() end) do
        guard = guard + 1
        local cname = try(function() return cls:GetFName():ToString() end) or "?"
        pcall(function()
            cls:ForEachProperty(function(prop)
                local name = try(function() return prop:GetFName():ToString() end)
                if name then
                    local val = try(function() return fmtVal(obj[name]) end)
                    if val then f:write(cname .. "." .. name .. " = " .. val .. "\n") end
                end
            end)
        end)
        cls = try(function() local sup = cls:GetSuperStruct(); if sup and sup:IsValid() then return sup end end)
    end
end
local function snapshot()
    snapN = snapN + 1
    local name = string.format("%s\\NikkeGunMode_snap_%s_%d.txt", MODFOLDER or ".", os.date("%H%M%S"), snapN)
    local f = io.open(name, "w")
    if not f then log("snapshot: cannot write " .. name); return end
    local p, pc = getPawn(), getPC()
    f:write("gunOn=" .. tostring(gunOn) .. " bullet=" .. tostring(curBullet()) .. " stance=" ..
        tostring(p and try(function() return p:GetCurrentStanceName():ToString() end)) .. " native=" .. native("ngm_probe") .. "\n")
    dumpObj(f, "pawn", p)
    -- v0.8d: the NIKKE stage puts EVE inside an SBCameraVolume (EnableTPSFlag / EffectAlias / BlockSkillInVolume)
    dumpObj(f, "cameravolume", p and try(function() return p.CurrentCameraVolume end))
    pcall(function()
        local n = 0
        p.TouchTriggerMap:ForEach(function(k, v)
            n = n + 1
            f:write("TouchTriggerMap[" .. n .. "] " .. tostring(fmtVal(k:get())) .. " -> " .. tostring(fmtVal(v:get())) .. "\n")
        end)
    end)
    dumpObj(f, "controller", pc)
    dumpObj(f, "playerstate", pc and try(function() return pc.PlayerState end))
    dumpObj(f, "gamestate", try(function() return FindFirstOf("GameStateBase") end))
    dumpObj(f, "gamemode", try(function() return FindFirstOf("GameModeBase") end))
    f:close()
    log("snapshot written: " .. name)
end

-- v0.9b test keys (temporary): Ctrl+Shift+H = control effect NGM_Test (EVE drinks a potion via the same UseSkill
-- recipe) through the cheat request; Ctrl+Shift+J = P_Eve_GunNikke (10082) through the cheat request (proves the route).
local function cheatEffect(id, what)
    local pc, g = getPC(), eveGUID or CFG.EVE_GUID_GUESS
    local ok, err = pcall(function() pc:ServerRequest_Cheat(g, 0, "SBApplyEffectMe", tostring(id)) end)
    log("test: cheat SBApplyEffectMe " .. id .. " (" .. what .. ") " .. (ok and "sent" or ("FAILED " .. tostring(err))))
end
-- v0.9e: test keys removed - they clashed with other mods (J = mission menu, N = CNS menu). Only Ctrl+G and
-- Ctrl+Shift+G are ours (user's hotkey map). Ctrl+Shift+G now runs the shot test.
local function shotTest()
    local ok, err = pcall(fireRow, { 2, CFG.FIRE_ZONE_ROW })
    local p = getPawn()
    log("shot test: NGM_AE_Fire (gunOn=" .. tostring(gunOn) .. ", stance=" ..
        tostring(p and try(function() return p:GetCurrentStanceName():ToString() end)) .. ") " ..
        (ok and "fired" or ("FAILED " .. tostring(err))))
    ExecuteWithDelay(150, function() ExecuteInGameThread(function()
        local p2 = getPawn()
        if p2 then log("shot test +150ms: running skill=" .. tostring(try(function() return p2:IsRunningSkill() end))) end
    end) end)
end

-- key callbacks arrive on UE4SS's input thread: hand everything to the game thread
-- v0.16: never toggle from a menu / pause screen (G is a UI key there)
local function inMenu()
    local pc = getPC()
    if not pc then return true end
    if try(function() return pc.bShowMouseCursor end) then return true end
    local paused = try(function()
        local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
        return gs:IsGamePaused(pc)
    end)
    return paused == true
end
local lastToggle = -1
local blockedLog = 0
local function stuckInStance()
    local p = getPawn()
    if not p then return false end
    local tps = try(function() return p:IsTPSMode() end)
    local mt = tonumber(try(function() return p:GetTPSModeType() end))
    return tps == true and (mt == 2 or mt == 0)
end
local function safeToggle(src)
    -- v0.60: if Gun Mode is off but EVE is still in the NIKKE stance (stuck), G always forces the exit rows - even when
    -- inMenu() thinks a menu is up (desktop 11-16: G did nothing after the stance got stuck, no log line at all)
    if not gunOn and stuckInStance() then
        local now = os.clock()
        if now - lastToggle < 0.4 then return end
        lastToggle = now
        for _, r in ipairs(OFF_ROWS) do pcall(fireRow, r) end
        log("G (" .. src .. "): Gun Mode was off but the NIKKE stance was still on - exit rows sent again")
        return
    end
    if inMenu() then
        local now = os.clock()
        if now - blockedLog > 2 then blockedLog = now; log("toggle (" .. src .. ") ignored: menu/pause/cursor is up") end
        return
    end
    local now = os.clock()
    if now - lastToggle < 0.4 then return end      -- one press can reach both G bindings below
    lastToggle = now
    local ok, err = pcall(toggle)
    if not ok then log("toggle error (" .. src .. "): " .. tostring(err)) end
end
-- v0.53: test helper (OFF by default): Ctrl+F12 gives +60 NIKKE Rounds through NGM_ItemA_Ammo
if CFG.DEBUG_AMMO_KEY then
    RegisterKeyBind(Key.F12, { ModifierKey.CONTROL }, function()
        ExecuteInGameThread(function()
            local ok = fireRow({13, "NGM_ItemA_Ammo"})
            if ok then bagEmpty = false end
            log("debug: +60 Bullet_Nikke " .. (ok and "sent" or "FAILED"))
        end)
    end)
end
RegisterKeyBind(CFG.TOGGLE_KEY, function()
    ExecuteInGameThread(function() safeToggle("G") end)
end)
-- G while Ctrl is held (aiming) also toggles, so Gun Mode can be left mid-aim
RegisterKeyBind(CFG.TOGGLE_KEY, { ModifierKey.CONTROL }, function()
    ExecuteInGameThread(function() safeToggle("Ctrl+G") end)
end)

-- v0.16 controller: hold R1 + press L2 toggles Gun Mode; in Gun Mode L2+R2 fires (full auto while held)
local padL2, padR2, padDR = false, false, false
local padEv, evadeAt = false, nil      -- v0.28 evade re-centre
local evPressAt, evFired = nil, true    -- v0.52 standing roll
local padKM = false                    -- v0.29 Ctrl+LMB polled
local function padTick()
    local pc = getPC()
    if pc and getPawn() then
        local r1 = keyDown(pc, "Gamepad_RightShoulder")
        local l2 = keyDown(pc, "Gamepad_LeftTrigger")
        local r2 = keyDown(pc, "Gamepad_RightTrigger")
        local aim = l2 or keyDown(pc, "LeftControl") or keyDown(pc, "RightControl")
        if aim and not aimHeld then
            aimSince = os.clock()
            -- v0.25: HUD diag 1 s into an aim, both in Gun Mode and in the normal drone aim (the reference: there the
            -- quick slot shows the drone ammo). Queued one-shot, never run here in the tick hook.
            queueHudDiag(gunOn and "gun-aim+1s" or "drone-aim+1s", 1000)
            -- v0.22b: the guide laser only exists while aiming (the 1.5 s / 4 s swaps found none) - swap it 0.3 s after
            -- each aim press, from a queued one-shot game-thread call (not inside this tick hook)
            if gunOn and CFG.LASER_SWAP then
                for _, ms in ipairs({ 300, 900, 1800 }) do
                    ExecuteWithDelay(ms, function() ExecuteInGameThread(function() pcall(laserSwap, "aim+" .. ms) end) end)
                end
            end
            if gunOn and CFG.LASER_BOOST then
                for _, ms in ipairs({ 300, 900, 1800 }) do
                    ExecuteWithDelay(ms, function() ExecuteInGameThread(function() pcall(laserBoost, "aim+" .. ms) end) end)
                end
            end
        end
        aimHeld = aim
        if gunOn and not CFG.ROLL_SWAP and ((CFG.EVADE_RECENTER and crouched) or CFG.STAND_EVADE) then
            local ev = keyDown(pc, "LeftShift") or keyDown(pc, "Gamepad_FaceButton_Right")
            if ev and not padEv then
                if (CFG.LOCK_POSITION or crouched) and CFG.EVADE_RECENTER then evadeAt = os.clock() + CFG.EVADE_RECENTER end
                evPressAt, evFired = os.clock(), false
            end
            -- v0.52: standing/aiming has no evade command in the NIKKE stances - start the NIKKE side roll ourselves
            -- (sp10 NGM_AE_EvadeL/R = UseSkill P_Eve_GunNikke_Evade1_2 / 1_3). In cover the game's own roll runs.
            -- Checked while the key is held (0.4 s window) so a press just before the aim stance lands still counts.
            if CFG.STAND_EVADE and ev and evPressAt and not evFired and os.clock() - evPressAt < 0.4 then
                local left = keyDown(pc, "A") or keyDown(pc, "Gamepad_LeftStick_Left")
                local right = keyDown(pc, "D") or keyDown(pc, "Gamepad_LeftStick_Right")
                local st = try(function() return getPawn():GetCurrentStanceName():ToString() end) or "?"
                if (left or right) and st:find("GunNikke", 1, true) then   -- v0.60: aim AND hide stance (no cover any more)
                    evFired = true
                    local goLeft = left
                    if CFG.EVADE_SWAP then goLeft = not goLeft end
                    pcall(fireRow, {2, goLeft and "NGM_AE_EvadeL" or "NGM_AE_EvadeR"})
                    standEvadeN = (standEvadeN or 0) + 1
                    if standEvadeN <= 10 then log("evade (standing, " .. st .. "): " .. (left and "left" or "right")) end
                    -- v0.60 diag: did the roll skill actually start? (desktop 11-16: logged, nothing visible)
                    local n = standEvadeN
                    if n <= 10 then
                        ExecuteWithDelay(250, function() ExecuteInGameThread(function()
                            local p2 = getPawn()
                            log("evade #" .. n .. " +250ms: skill running=" .. tostring(p2 and try(function() return p2:IsRunningSkill() end))
                                .. " stance=" .. tostring(p2 and try(function() return p2:GetCurrentStanceName():ToString() end)))
                        end) end)
                    end
                end
            end
            padEv = ev
        end
        -- v0.64 roll: lift the gun, let the game's normal evade run, put the gun back (tick)
        if CFG.ROLL_SWAP then
            local evk = keyDown(pc, "LeftShift") or keyDown(pc, "Gamepad_FaceButton_Right")
            if gunOn and evk and not padRoll and not rollBackAt and os.clock() >= (rollReadyAt or 0) then
                rollBackAt = os.clock() + CFG.ROLL_TIME
                guardSince = os.clock()          -- keep the stance guard / empty-bag exit quiet during the roll
                rollN = (rollN or 0) + 1
                local n = rollN
                ExecuteWithDelay(1, function() ExecuteInGameThread(function()
                    if not gunOn then return end
                    pcall(fireRow, {2, "NGM_AE_GunOff"}); pcall(fireRow, {2, "NGM_AE_PosOff"})
                    if n <= 10 then log("roll #" .. n .. ": gun lifted for the normal evade") end
                end) end)
                if n <= 10 then
                    ExecuteWithDelay(350, function() ExecuteInGameThread(function()
                        local p2 = getPawn()
                        log("roll #" .. n .. " +350ms: skill running=" .. tostring(p2 and try(function() return p2:IsRunningSkill() end))
                            .. " stance=" .. tostring(p2 and try(function() return p2:GetCurrentStanceName():ToString() end)))
                    end) end)
                end
            end
            padRoll = evk
        end
        -- v0.61 crouch <-> stand: R3 / Caps Lock
        local ck = keyDown(pc, CFG.CROUCH_PAD) or keyDown(pc, CFG.CROUCH_KEY) or (CFG.CROUCH_KEY2 and keyDown(pc, CFG.CROUCH_KEY2))
        if ck and not padCrouch then log("crouch key pressed (R3/Caps Lock), gunOn=" .. tostring(gunOn)) end
        if gunOn and ck and not padCrouch and os.clock() - (crouchAt or 0) > 0.3 then
            crouchAt = os.clock()
            crouched = not crouched
            ExecuteWithDelay(10, function() ExecuteInGameThread(function() if gunOn then applyPosture("R3/CapsLock") end end) end)
        end
        padCrouch = ck
        if CFG.PAD_COMBO == "DPadRight" then
            local dr = keyDown(pc, "Gamepad_DPad_Right")
            if dr and not padDR and not r1 then safeToggle("DPadRight") end
            padDR = dr
        elseif CFG.PAD_COMBO == "L1+DPadRight" then
            local dr = keyDown(pc, "Gamepad_DPad_Right")
            if dr and not padDR and keyDown(pc, "Gamepad_LeftShoulder") then safeToggle("L1+DPadRight") end
            padDR = dr
        elseif l2 and not padL2 and r1 then safeToggle("R1+L2") end
        local standing = CFG.STANDING and not crouched
        if gunOn and r2 and (l2 or standing) and not padR2 then pcall(startFiring) end
        -- v0.29: Ctrl+LMB held in either order also starts firing (the keybind only sees LMB pressed while Ctrl is down)
        local km = keyDown(pc, "LeftMouseButton") and (standing or keyDown(pc, "LeftControl") or keyDown(pc, "RightControl"))
        if gunOn and km and not padKM then pcall(startFiring) end
        padKM = km
        padL2, padR2 = l2, r2
    end
end

-- v0.18 central tick. Two crashes during long full-auto bursts (11-15 20:02, 11-16 02:29) were access violations
-- inside UE4SS.dll itself, with several ExecuteWithDelay chains re-arming every 50-110 ms (fire, hold, pad, battle).
-- Everything periodic now runs from one post-hook on EVE's ReceiveTick (game thread, no timers).
local tickHooked, tPad, tHold, tBattle, tLaser = false, 0, 0, 0, 0
local evadeN = 0
local tUtil = 0
local tEmpty, emptyHits = 0, 0
local tTps, tpsHits, magReloads = 0, 0, 0
-- v0.21 laser: find the active NS_A_GuideLaser component (v0.20b diag) and scale it while in Gun Mode
local laserComp, laserLogged, laserSearchAt = nil, false, 0
local function laserStep()
    if not CFG.LASER_SCALE or CFG.LASER_SCALE == 1.0 then return end
    if not valid(laserComp) then
        laserComp = nil
        local now = os.clock()
        if now < laserSearchAt then return end
        laserSearchAt = now + 2.0          -- FindAllOf walks every object: at most every 2 s, only in Gun Mode
        local all = FindAllOf("NiagaraComponent")
        if not all then return end
        for _, c in ipairs(all) do
            local ok, name = pcall(function() return c.Asset:GetFName():ToString() end)
            if ok and name == "NS_A_GuideLaser" and try(function() return c:IsActive() end) then laserComp = c; break end
        end
        if not laserComp then return end
        laserLogged = false
    end
    local sc = CFG.LASER_SCALE
    pcall(function()
        local cur = laserComp:GetComponentScale()
        if math.abs(cur.X - sc) > 0.01 or math.abs(cur.Y - sc) > 0.01 or math.abs(cur.Z - sc) > 0.01 then
            laserComp:SetWorldScale3D({ X = sc, Y = sc, Z = sc })
            if not laserLogged then laserLogged = true; log("laser: NS_A_GuideLaser scaled x" .. sc .. " (was " .. string.format("%.2f", cur.X) .. ")") end
        end
    end)
end
-- v0.66 diag: which way does EVE's body face vs her actor rotation / the camera while moving in Gun Mode?
-- (decides how the standing blend space's LeftRight / FrontBack axes map to the walk animations)
moveDiagN = 0
function moveDiag()
    if moveDiagN >= 60 then return end
    local p, pc = getPawn(), getPC()
    if not p or not pc then return end
    local v = p:GetVelocity(); local sp = math.sqrt(v.X * v.X + v.Y * v.Y)
    if sp < 30 then return end
    local ar = p:K2_GetActorRotation(); local cr = pc:GetControlRotation()
    local vy = math.deg(math.atan(v.Y, v.X))
    local function d(a) a = (a + 540) % 360 - 180; return string.format("%.0f", a) end
    local keys = {}
    for _, k in ipairs({ "W", "A", "S", "D", "Gamepad_LeftY", "Gamepad_LeftX" }) do if keyDown(pc, k) then keys[#keys + 1] = k end end
    moveDiagN = moveDiagN + 1
    log("move diag: speed " .. string.format("%.0f", sp) .. " vel-actor " .. d(vy - ar.Yaw) .. " actor-camera " .. d(ar.Yaw - cr.Yaw)
        .. " keys " .. table.concat(keys, "+") .. " stance " .. tostring(try(function() return p:GetCurrentStanceName():ToString() end)))
end
-- v0.67 standing = third-person shooter: EVE's actor yaw follows the camera every tick (the NIKKE stances keep the
-- actor where it was, so she didn't turn with the camera and stayed 90 deg off after a roll, 11-17 09:22)
function faceCamera()
    local p, pc = getPawn(), getPC()
    if not p or not pc then return end
    local cr = pc:GetControlRotation(); local r = p:K2_GetActorRotation()
    if math.abs(((r.Yaw - cr.Yaw + 540) % 360) - 180) > 0.5 then
        p:K2_SetActorRotation({ Pitch = r.Pitch, Yaw = cr.Yaw, Roll = r.Roll }, false)
    end
end
-- v0.70c: TPS mode property probe (names/values once per Gun Mode entry) and the standing mode-0 switch
tpsProps, tpsZeroDead, tpsZeroLogs, tpsMode0 = nil, false, 0, false
function tpsProbe()
    local p = getPawn(); if not p then return end
    tpsProps = {}
    local cls = try(function() return p:GetClass() end)
    local lines = {}
    while cls and valid(cls) do
        pcall(function()
            cls:ForEachProperty(function(prop)
                local n = prop:GetFName():ToString()
                if n:find("TPS") or n:find("Nikke") then
                    local v = try(function() return p[n] end)
                    lines[#lines + 1] = n .. "=" .. tostring(v); tpsProps[n] = true
                end
            end)
        end)
        cls = try(function() return cls:GetSuperStruct() end)
    end
    log("tps probe: " .. table.concat(lines, " | "))
end
function tpsSetMode(m, why)
    local p = getPawn(); if not p then return false end
    local done = {}
    for _, n in ipairs({ "TPSModeType", "CurrentTPSModeType", "TPSMode_Type" }) do
        if tpsProps and tpsProps[n] then
            local ok = pcall(function() p[n] = m end); done[#done + 1] = n .. (ok and " ok" or " fail")
        end
    end
    for _, f in ipairs({ "SetTPSModeType", "SetTPSMode_Type" }) do
        local ok = pcall(function() p[f](p, m) end); if ok then done[#done + 1] = f .. "() ok" end
    end
    local mt = tonumber(try(function() return p:GetTPSModeType() end))
    tpsMode0 = (mt == 0)
    if tpsZeroLogs < 30 then tpsZeroLogs = tpsZeroLogs + 1; log(string.format("tps mode -> %d (%s): %s, now %s", m, why, table.concat(done, ", "), tostring(mt))) end
    return mt == m
end
function tpsZeroTick()
    if tpsZeroDead then return end
    local p = getPawn(); if not p then return end
    local mt = tonumber(try(function() return p:GetTPSModeType() end))
    local st = try(function() return p:GetCurrentStanceName():ToString() end) or "?"
    if mt == 0 and not st:find("GunNikke", 1, true) and os.clock() - (tpsZeroAt or 0) > 1.0 then
        log("tps mode 0 lost the gun stance (" .. st .. ") - back to 2, mode switch off for this session")
        tpsZeroDead = true; tpsSetMode(2, "revert"); pcall(fireRow, {2, "NGM_AE_GunOn"}); return
    end
    tpsMode0 = (mt == 0)
    if mt == 0 and CFG.STAND_AO_OFF then
        local ao = try(function() return p.bIsActiveTPSAimOffset end)
        if ao == true then
            local ok = pcall(function() p.bIsActiveTPSAimOffset = false end)
            aoLogs = (aoLogs or 0) + 1
            if aoLogs <= 5 or aoLogs % 50 == 0 then log("aim offset: bIsActiveTPSAimOffset true -> false (" .. tostring(ok) .. ", #" .. aoLogs .. ")") end
        end
    end
    if mt == 2 then tpsZeroAt = os.clock(); tpsSetMode(0, "standing") end
end
-- v0.70f: reticle widgets in standing mode (diagnostic + force visible) and the ProjectileTable row probe
function reticleTick(first)
    for _, cls in ipairs({ "WB_MainHUD_TpsMaster_C", "WB_Tps_Aim_C", "WB_NikkeHUD_Aim_C" }) do
        local ws = try(function() return FindAllOf(cls) end)
        for i, w in ipairs(ws or {}) do
            if valid(w) then
                local vis = try(function() return w:GetVisibility() end)
                local inv = try(function() return w:IsInViewport() end)
                local op = try(function() return w:GetRenderOpacity() end)
                if first then log(string.format("reticle probe: %s #%d vis=%s opacity=%s inViewport=%s name=%s", cls, i, tostring(vis), tostring(op), tostring(inv), tostring(try(function() return w:GetFullName() end)))) end
                if op and op < 0.99 and (try(function() return w:GetFullName() end) or ""):find("Transient", 1, true) then pcall(function() w:SetRenderOpacity(1.0) end) end
                -- v0.70h: the reticle lives in WB_MainHUD_TpsMaster (hidden outside drone aim); only touch live (transient) ones
                local live = (try(function() return w:GetFullName() end) or ""):find("Transient", 1, true)
                if live and vis ~= 3 and vis ~= 4 and vis ~= 0 then pcall(function() w:SetVisibility(3) end); if first then log("reticle: " .. cls .. " #" .. i .. " set visible (was " .. tostring(vis) .. ")") end end
            end
        end
    end
end
-- v0.70n: gun mount probe (which component is the rifle, on which socket/parent) + shoulder camera offset
function gunProbe()
    -- v0.70o: only EVE's own components (K2_GetComponentsByClass) - a world-wide FindAllOf over components crashed (14:51)
    local p = getPawn(); if not p then return end
    for _, cp in ipairs({ "/Script/Engine.SkeletalMeshComponent", "/Script/Engine.StaticMeshComponent" }) do
        local cls = try(function() return StaticFindObject(cp) end)
        local arr = cls and try(function() return p:K2_GetComponentsByClass(cls) end)
        for _, e in ipairs(arr or {}) do
            local c = try(function() return e:get() end) or e
            if c and valid(c) then
                local par = try(function() return c:GetAttachParent() end)
                local sock = try(function() return c:GetAttachSocketName():ToString() end)
                local mesh = try(function() return (c.SkeletalMesh or c.StaticMesh):GetFName():ToString() end)
                log(string.format("gun probe: %s mesh=%s parent=%s socket=%s visible=%s", tostring(try(function() return c:GetFName():ToString() end)),
                    tostring(mesh), tostring(par and try(function() return par:GetFName():ToString() end)), tostring(sock), tostring(try(function() return c:IsVisible() end))))
            end
        end
    end
end
camSaved = nil
function camOffsetOn()
    local p = getPawn(); if not p then return end
    local boom = try(function() return p.CameraBoom end)
    if not (boom and valid(boom)) then log("camera: no CameraBoom"); return end
    local o = CFG.CAM_CUSTOM_OFFSET
    if not camSaved then
        local c = boom.CustomOffset
        camSaved = { x = c.X, y = c.Y, z = c.Z, arm = boom.TargetArmLength }
    end
    local ok = pcall(function() local c = boom.CustomOffset; c.X = o.X; c.Y = o.Y; c.Z = o.Z end)
    log(string.format("camera: CameraBoom CustomOffset -> (%.0f,%.0f,%.0f) %s (TargetArmLength %.0f)", o.X, o.Y, o.Z, tostring(ok), boom.TargetArmLength))
end
function camOffsetOff()
    local p = getPawn(); if not (p and camSaved) then return end
    local boom = try(function() return p.CameraBoom end)
    if boom and valid(boom) then pcall(function() local c = boom.CustomOffset; c.X = camSaved.x; c.Y = camSaved.y; c.Z = camSaved.z end) end
    camSaved = nil
end
-- v0.70m: TPS aiming state held while standing
function zoomTick()
    local p = getPawn(); if not p then return end
    local z = try(function() return p.bTPSZoomIn end)
    if z == false then
        local ok = pcall(function() p.bTPSZoomIn = true end)
        zoomLogs = (zoomLogs or 0) + 1
        if zoomLogs <= 4 or zoomLogs % 100 == 0 then log("zoom: bTPSZoomIn false -> true (" .. tostring(ok) .. ", #" .. zoomLogs .. ")") end
    end
end
-- v0.70l: weapon fold probe - the NIKKE rifle stays upright ("folded") outside aim; find the switch on EVE / the gun actor
function foldProbe()
    local p = getPawn(); if not p then return end
    local objs = { p }
    pcall(function()
        local att = p:GetAttachedActors({}, true)
        for _, a in ipairs(att or {}) do local o = a:get(); if o and valid(o) then objs[#objs + 1] = o end end
    end)
    for _, o in ipairs(objs) do
        local lines = {}
        local cls = try(function() return o:GetClass() end)
        while cls and valid(cls) do
            pcall(function() cls:ForEachProperty(function(prop)
                local n = prop:GetFName():ToString()
                if n:find("Fold") or n:find("Weapon") or n:find("Aim") or n:find("Zoom") then
                    local v = try(function() return o[n] end)
                    if type(v) ~= "userdata" then lines[#lines + 1] = n .. "=" .. tostring(v) end
                end
            end) end)
            cls = try(function() return cls:GetSuperStruct() end)
        end
        log("fold probe: " .. tostring(try(function() return o:GetFullName() end)):sub(1, 140) .. " :: " .. table.concat(lines, " | "))
    end
end
-- v0.70k: camera probe - which offset/distance/FOV properties exist on EVE's camera components + the camera manager
function camProbe()
    local p, pc = getPawn(), getPC(); if not (p and pc) then return end
    local objs = {}
    for _, cls in ipairs({ "SpringArmComponent", "SBSpringArmComponent", "CameraComponent", "SBCameraComponent" }) do
        for _, c in ipairs(FindAllOf(cls) or {}) do
            local o = try(function() return c:GetOwner() end)
            if o and valid(o) and o:GetFullName() == p:GetFullName() then objs[#objs + 1] = c end
        end
    end
    local cm = try(function() return pc.PlayerCameraManager end); if cm and valid(cm) then objs[#objs + 1] = cm end
    for _, o in ipairs(objs) do
        local lines = {}
        local cls = try(function() return o:GetClass() end)
        while cls and valid(cls) do
            pcall(function() cls:ForEachProperty(function(prop)
                local n = prop:GetFName():ToString()
                if n:find("Offset") or n:find("Arm") or n:find("Distance") or n:find("FOV") or n:find("TPS") or n:find("Socket") or n:find("Lag") then
                    local v = try(function() return o[n] end)
                    if type(v) == "userdata" then
                        local okx, x = pcall(function() return string.format("(%.1f,%.1f,%.1f)", v.X, v.Y, v.Z) end)
                        if okx then v = x end
                    end
                    lines[#lines + 1] = n .. "=" .. tostring(v)
                end
            end) end)
            cls = try(function() return cls:GetSuperStruct() end)
        end
        log("cam probe: " .. tostring(try(function() return o:GetFName():ToString() end)) .. " [" .. tostring(try(function() return o:GetClass():GetFName():ToString() end)) .. "] " .. table.concat(lines, " | "))
    end
end
-- v0.70j: our own reticle: a fresh WB_Tps_Aim_C added to the viewport (one-off calls, object params only)
ownReticle = nil
function ownReticleOn()
    if ownReticle and valid(ownReticle) then pcall(function() ownReticle:SetVisibility(3) end); return end
    local pc = getPC(); if not pc then return end
    local cls = try(function() return StaticFindObject("/Game/Art/UI/Widget/TPS/WB_Tps_Aim.WB_Tps_Aim_C") end)
    local lib = try(function() return StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary") end)
    if not (cls and valid(cls) and lib and valid(lib)) then log("own reticle: class/library not found " .. tostring(cls) .. " " .. tostring(lib)); return end
    local ok, w = pcall(function() return lib:Create(pc, cls, pc) end)
    if not (ok and w and valid(w)) then log("own reticle: create failed " .. tostring(w)); return end
    pcall(function() w:AddToViewport(50) end)
    ownReticle = w
    log("own reticle: created, inViewport=" .. tostring(try(function() return w:IsInViewport() end)) .. " vis=" .. tostring(try(function() return w:GetVisibility() end)))
end
function ownReticleOff()
    if ownReticle and valid(ownReticle) then pcall(function() ownReticle:RemoveFromParent() end) end
    ownReticle = nil
end
aimRow, aimRowOk = nil, false
-- v0.70g: the NIKKE bullet's ProjectileTable row is live data (FindRow works; 13:45 crash came from a 2nd lookup variant -
-- only FindRow(string) is used now). Its Dest is switched to the drone shot's frame (MainActor, Base, RootAxis = EVE's
-- body), and before every shot DestTargetRelativeLocation = the crosshair point in that frame -> exact aim, pitch included.
function aimRowSetup()
    local dt = try(function() return StaticFindObject("/Game/Local/Data/ProjectileTable.ProjectileTable") end)
    if not (dt and valid(dt)) then log("aim row: table not found"); return end
    local ok, r = pcall(function() return dt:FindRow("P_Eve_GunNikke_ShootSlug1_Projectile1") end)
    local ok2, d = pcall(function() return dt:FindRow("P_Eve_Gun_ShootSlug1_Projectile1") end)
    if not (ok and r) then log("aim row: FindRow failed " .. tostring(r)); return end
    local function ints(row)
        return tostring(try(function() return row.DestTarget end)) .. "/" .. tostring(try(function() return row.DestTargetTransformType end))
            .. "/" .. tostring(try(function() return row.DestTargetRelativeAxisType end))
    end
    log("aim row: ours " .. ints(r) .. " | drone " .. ((ok2 and d) and ints(d) or "?"))
    local tt = (ok2 and d) and try(function() return d.DestTargetTransformType end)
    local ax = (ok2 and d) and try(function() return d.DestTargetRelativeAxisType end)
    if type(tt) ~= "number" or type(ax) ~= "number" then log("aim row: drone enum values unreadable - aim write off"); return end
    local okW = pcall(function() r.DestTargetTransformType = tt; r.DestTargetRelativeAxisType = ax end)
    aimRow = r; aimRowOk = okW
    log("aim row: ours set to TransformType " .. tostring(tt) .. " AxisType " .. tostring(ax) .. " -> " .. tostring(okW) .. ", now " .. ints(r))
end
function aimRowWrite(p, target)
    if not (aimRowOk and aimRow and target) then return end
    local loc = p:K2_GetActorLocation(); local rot = p:K2_GetActorRotation()
    local dx, dy, dz = target.X - loc.X, target.Y - loc.Y, target.Z - loc.Z
    local yr = math.rad(rot.Yaw); local c, s = math.cos(yr), math.sin(yr)
    local lx, ly = dx * c + dy * s, -dx * s + dy * c          -- world -> EVE's root frame (yaw only)
    local okW = pcall(function()
        local v = aimRow.DestTargetRelativeLocation; v.X = lx; v.Y = ly; v.Z = dz
    end)
    if (aimWriteLogs or 0) < 6 then aimWriteLogs = (aimWriteLogs or 0) + 1
        log(string.format("aim row: rel (%.0f, %.0f, %.0f) written %s", lx, ly, dz, tostring(okW))) end
end
-- v0.70g laser sight: the NIKKE guide laser (beam to User EndPos) on the gun muzzle, end on the crosshair point
laserSight = nil
function laserSpawn()
    local p = getPawn(); if not p then return end
    local path = "/Game/DLC_2/Art/FX/MiniGame/NS_A_GuideLaser.NS_A_GuideLaser"
    local sys = try(function() return StaticFindObject(path) end)
    if not (sys and valid(sys)) then pcall(function() LoadAsset(path) end); sys = try(function() return StaticFindObject(path) end) end
    local lib = try(function() return StaticFindObject("/Script/Niagara.Default__NiagaraFunctionLibrary") end)
    if not (sys and valid(sys) and lib and valid(lib)) then log("laser sight: asset/library not found (" .. tostring(sys) .. ", " .. tostring(lib) .. ")"); return end
    -- v0.70i: per-frame steering crashed (13:51; every crash today = a struct passed to the game many times a second), so
    -- the beam is attached ONCE to the camera, offset to sit by the gun: it then always runs to the screen-centre crosshair
    local parent, sock, rl = p.Mesh, FName(CFG.LASER_SOCKET or "SC_GunShoot"), { X = 0, Y = 0, Z = 0 }
    if CFG.LASER_ATTACH == "camera" then
        local cam = try(function() return p.FollowCamera end)
        if not (cam and valid(cam)) then
            for _, c in ipairs(FindAllOf("CameraComponent") or {}) do
                local o = try(function() return c:GetOwner() end)
                if o and valid(o) and o:GetFullName() == p:GetFullName() then cam = c; break end
            end
        end
        if cam and valid(cam) then parent = cam; sock = FName("None"); rl = CFG.LASER_CAM_OFFSET end
    end
    local ok, c = pcall(function()
        return lib:SpawnSystemAttached(sys, parent, sock, rl, { Pitch = CFG.LASER_PITCH_OFS or 0, Yaw = CFG.LASER_YAW_OFS or 0, Roll = 0 }, 0, false, true, 0, true)
    end)
    if ok and c and valid(c) then laserSight = c; log("laser sight: spawned on " .. tostring(try(function() return parent:GetFName():ToString() end)) .. " offset " .. string.format("(%.0f,%.0f,%.0f)", rl.X, rl.Y, rl.Z)) else log("laser sight: spawn failed " .. tostring(c)) end
end
function laserSightTick(p)
    if not (laserSight and valid(laserSight)) then return end
    local t = try(function() return p:GetTPSLookAtWorldLocation(true) end)
    if not t then return end
    local v = { X = t.X, Y = t.Y, Z = t.Z }
    for _, n in ipairs({ "User.EndPos", "EndPos" }) do pcall(function() laserSight:SetVariableVec3(FName(n), v) end) end
    -- v0.70h: EndPos isn't a user parameter here - aim the beam itself: the component's +X at the crosshair point
    local o = try(function() return laserSight:K2_GetComponentLocation() end)
    if o then
        local dx, dy, dz = t.X - o.X, t.Y - o.Y, t.Z - o.Z
        local h = math.sqrt(dx * dx + dy * dy)
        local r = { Pitch = math.deg(math.atan(dz, h)) + (CFG.LASER_PITCH_OFS or 0), Yaw = math.deg(math.atan(dy, dx)) + (CFG.LASER_YAW_OFS or 0), Roll = 0 }
        pcall(function() laserSight:K2_SetWorldRotation(r, false, {}, false) end)
        if (laserLogs or 0) < 4 then laserLogs = (laserLogs or 0) + 1; log(string.format("laser sight: aimed yaw %.1f pitch %.1f (dist %.0f)", r.Yaw, r.Pitch, math.sqrt(h * h + dz * dz))) end
    end
end
function laserSightOff()
    if laserSight and valid(laserSight) then pcall(function() laserSight:DestroyComponent(laserSight) end) end
    laserSight = nil
end
-- v0.70 standing look: read the mouse / right stick ourselves and turn the control rotation, unless the game already
-- turned it this tick (then it is handling look input and we stay out of the way)
lookLast, lookLogs, lookT, lookGameTurns = nil, 0, nil, 0
function standLook(now)
    local p, pc = getPawn(), getPC()
    if not p or not pc then return end
    local ign = try(function() return pc:IsLookInputIgnored() end)
    if ign then pcall(function() pc:ResetIgnoreLookInput() end); if lookLogs < 20 then lookLogs = lookLogs + 1; log("look: look input was ignored - reset") end end
    local function num(f) local ok, v = pcall(f); if ok and type(v) == "number" then return v end; return nil end
    local function axk(k) return num(function() return pc:GetInputAxisKeyValue({ KeyName = FName(k) }) end) end
    local function axn(o, n) return num(function() return o:GetInputAxisValue(FName(n)) end) end
    -- v0.70b: the game binds MouseX/MouseY to the axes Turn / LookUp (pad: TurnRate / LookUpRate) on the pawn
    local t1, t2, t3, t4 = axn(p, "Turn"), axn(p, "LookUp"), axn(pc, "Turn"), axn(pc, "LookUp")
    local k1, k2 = axk("MouseX"), axk("MouseY")
    local r1, r2 = axn(p, "TurnRate"), axn(p, "LookUpRate")
    local g1, g2 = axk("Gamepad_RightX"), axk("Gamepad_RightY")
    if (lookRawN or 0) < 40 and now - (lookRawT or 0) >= 0.5 then
        lookRawT = now; lookRawN = (lookRawN or 0) + 1
        log(string.format("look raw: pawn Turn %s LookUp %s | pc Turn %s LookUp %s | key MouseX %s MouseY %s | TurnRate %s LookUpRate %s | pad %s %s",
            tostring(t1), tostring(t2), tostring(t3), tostring(t4), tostring(k1), tostring(k2), tostring(r1), tostring(r2), tostring(g1), tostring(g2)))
    end
    local function nz(...) for _, v in ipairs({ ... }) do if v and v ~= 0 then return v end end; return 0 end
    local mx = nz(t1, t3, k1)
    local my = nz(t2 and -t2, t4 and -t4, k2)           -- LookUp is bound with scale -1 on MouseY
    local gx, gy = nz(r1, g1), nz(r2, g2)
    if math.abs(gx) < 0.15 then gx = 0 end
    if math.abs(gy) < 0.15 then gy = 0 end
    local dt = lookT and math.min(0.1, now - lookT) or 0; lookT = now
    local cr = pc:GetControlRotation()
    if lookLast and (math.abs(((cr.Yaw - lookLast.Yaw + 540) % 360) - 180) > 0.01 or math.abs(cr.Pitch - lookLast.Pitch) > 0.01) then
        lookGameTurns = lookGameTurns + 1   -- the game moved it (or faceCamera's actor turn fed back): don't double up
        if lookGameTurns == 30 then log("look: the game turns the camera itself here") end
    end
    local dyaw = mx * CFG.LOOK_SENS_MOUSE + gx * CFG.LOOK_SENS_PAD * dt
    local dpit = my * CFG.LOOK_SENS_MOUSE + gy * CFG.LOOK_SENS_PAD * dt
    if (dyaw ~= 0 or dpit ~= 0) and (not lookLast or (cr.Yaw == lookLast.Yaw and cr.Pitch == lookLast.Pitch)) then
        local pit = cr.Pitch; if pit > 180 then pit = pit - 360 end
        pit = math.max(CFG.LOOK_PITCH_MIN, math.min(CFG.LOOK_PITCH_MAX, pit + dpit))
        local nr = { Pitch = pit, Yaw = cr.Yaw + dyaw, Roll = 0 }
        pc:SetControlRotation(nr)
        if lookLogs < 20 then lookLogs = lookLogs + 1; log(string.format("look: mouse %.2f %.2f pad %.2f %.2f -> yaw %.1f pitch %.1f", mx, my, gx, gy, nr.Yaw, nr.Pitch)) end
        cr = pc:GetControlRotation()
    end
    lookLast = { Yaw = cr.Yaw, Pitch = cr.Pitch }
    if (lookDiagN or 0) < 15 and now - (lookDiagT or 0) >= 1.0 then   -- does the camera follow the control rotation here?
        lookDiagT = now; lookDiagN = (lookDiagN or 0) + 1
        local cm = try(function() return pc.PlayerCameraManager end)
        local camr = cm and try(function() return cm:GetCameraRotation() end)
        log(string.format("look diag: control yaw %.1f pitch %.1f | camera yaw %s pitch %s | game turns %d", cr.Yaw, cr.Pitch,
            camr and string.format("%.1f", camr.Yaw) or "?", camr and string.format("%.1f", camr.Pitch) or "?", lookGameTurns))
    end
end
local function engineTick()
    local now = os.clock()
    if now < tickPauseUntil then return end   -- v0.59: map just changed
    -- v0.70b: player objects going away (load / teardown): drop the cache and stay out for 2 s instead of calling into them
    if not valid(cachedPC) or not valid(try(function() return cachedPC.Pawn end)) then
        cachedPC = nil
        if not getPawn() then tickPauseUntil = now + 2.0; return end
    end
    if CFG.PAD_TOGGLE and now - tPad >= CFG.PAD_POLL_MS / 1000 then tPad = now; pcall(padTick) end
    if gunOn then
        fireStep(now)
        if now - tHold >= CFG.HOLD_MS / 1000 then tHold = now; pcall(holdTick, holdRun) end
        if now < battleUntil and now - tBattle >= 0.05 then tBattle = now; pcall(battleTick, battleRun) end
        if now - tLaser >= 0.5 then tLaser = now; pcall(laserStep) end
        if CFG.MOVE_DIAG and now - (tMoveDiag or 0) >= 1.0 then tMoveDiag = now; pcall(moveDiag) end
        if not tpsProps and now - guardSince > 1.0 then
            pcall(tpsProbe)
            if CFG.AIM_ROW_WRITE and not aimRowOk then local ok, e = pcall(aimRowSetup); if not ok then log("aim row: setup error " .. tostring(e)) end end
            if CFG.LASER_SIGHT and not (laserSight and valid(laserSight)) then local ok, e = pcall(laserSpawn); if not ok then log("laser sight: error " .. tostring(e)) end end
            if CFG.STAND_RETICLE then pcall(reticleTick, true) end
            if false and not gunProbed then gunProbed = true; local okg, eg = pcall(gunProbe); if not okg then log("gun probe: error " .. tostring(eg)) end end
            if false and not foldProbed then foldProbed = true; local okf, ef = pcall(foldProbe); if not okf then log("fold probe: error " .. tostring(ef)) end end
            if false and not camProbed then camProbed = true; local okc, ec = pcall(camProbe); if not okc then log("cam probe: error " .. tostring(ec)) end end
            if CFG.OWN_RETICLE then local ok, e = pcall(ownReticleOn); if not ok then log("own reticle: error " .. tostring(e)) end end
        end
        if CFG.CAM_CUSTOM_OFFSET and tpsMode0 and not crouched and now - (tCam or 0) >= 2.0 then tCam = now; pcall(camOffsetOn) end
        if CFG.FORCE_ZOOM and tpsMode0 and not crouched and now - (tZoom or 0) >= 0.25 then tZoom = now; pcall(zoomTick) end
        if CFG.STAND_TPS_ZERO and tpsProps and crouched and now - (tTpsZero or 0) >= 0.25 then   -- NIKKE cover wants mode 2
            tTpsZero = now; local p = getPawn(); if p and tonumber(try(function() return p:GetTPSModeType() end)) == 0 then pcall(tpsSetMode, 2, "crouch") end
        end
        if CFG.STAND_TPS_ZERO and tpsProps and not crouched and not rollBackAt and now - guardSince > 1.5 and now - (tTpsZero or 0) >= 1.0 then tTpsZero = now; pcall(tpsZeroTick) end
        -- v0.70d: with TPS mode 0 the game turns the camera AND her; our per-tick SetControlRotation / K2_SetActorRotation
        -- (struct params from Lua inside her own tick) are what all three 11-17 crashes have in common - fallback only
        local mode0 = CFG.STAND_TPS_ZERO and not tpsZeroDead and tpsMode0
        if not mode0 and CFG.STAND_LOOK and not crouched and not rollBackAt then local ok, e = pcall(standLook, now); if not ok and lookLogs < 20 then lookLogs = lookLogs + 1; log("look: error " .. tostring(e)) end end
        if not mode0 and CFG.STAND_FACE_CAMERA and not crouched and not rollBackAt then pcall(faceCamera) end
        if (CFG.HUD_DIAG or CFG.AMMO_WATCH) and now - tUtil >= 0.1 then tUtil = now; pcall(utilWatch, aimHeld, fireN) end
        -- v0.35 out of ammo: with Bullet_Nikke at 0 the game applies P_Eve_GunNikke_BulletZero, the NIKKE aim stance can't
        -- start, and holding aim lands on the drone's aim stance P_Eve_Gun instead (laptop 11-16: after 3 shots). The
        -- count itself isn't readable from Lua, so this is how Gun Mode knows it's empty.
        if CFG.EXIT_WHEN_EMPTY and aimHeld and now - guardSince > 2.0 and now - tEmpty >= 0.2 then
            tEmpty = now
            local p = getPawn()
            local st = p and try(function() return p:GetCurrentStanceName():ToString() end)
            if st == "P_Eve_Gun" then
                emptyHits = emptyHits + 1
                if emptyHits == 3 then           -- ~0.6 s steady, not a transition frame
                    -- v0.42: that's the gun's own 60-round magazine. Reload it; if the BAG is empty too, EmptyExit drops
                    -- the gun stance and the TPS check below ends Gun Mode.
                    magReloads = (magReloads or 0) + 1
                    log("ammo: no rounds (BulletZero) #" .. magReloads .. " - EmptyExit")
                    pcall(fireRow, {2, "NGM_AE_EmptyExit"})   -- v0.45: no reload (it refilled the bag)
                elseif emptyHits >= 12 then       -- still stuck ~1.8 s later: leave as before
                    emptyHits = 0
                    log("ammo: still no NIKKE aim after reload - leaving Gun Mode")
                    ExecuteWithDelay(100, function() ExecuteInGameThread(function() if gunOn then pcall(toggle) end end) end)
                end
            else
                emptyHits = 0
            end
        end
        -- v0.42: bag empty -> NGM_AE_EmptyExit (conditional zone row) removed the NIKKE gun; finish the exit in Lua
        if CFG.REAL_AMMO and now - guardSince > 1.5 and now - tTps >= 0.2 then
            tTps = now
            local p = getPawn()
            local isTps = p and try(function() return p:IsTPSMode() end)
            local mt = p and tonumber(try(function() return p:GetTPSModeType() end))
            if p and (isTps == false or (mt and mt ~= 2 and not (mt == 0 and CFG.STAND_TPS_ZERO and not tpsZeroDead))) then
                tpsHits = tpsHits + 1
                if tpsHits >= 3 then
                    tpsHits = 0
                    log("ammo: out of NIKKE Rounds (gun stance dropped by NGM_AE_EmptyExit) - leaving Gun Mode")
                    bagEmpty = true
                    ExecuteWithDelay(100, function() ExecuteInGameThread(function() if gunOn then pcall(toggle) end end) end)
                end
            else
                tpsHits = 0
            end
        end
        -- v0.61: standing - keep the aim stance up (a real Ctrl/L2 release also sends 'released'); HUD re-check
        if CFG.STANDING and not crouched and now - (tAimHold or 0) >= 0.5 then
            tAimHold = now
            local p = getPawn()
            local st = p and try(function() return p:GetCurrentStanceName():ToString() end)
            if st and st ~= "P_Eve_GunNikke" and st:find("GunNikke", 1, true) and not rollBackAt and aimMethod then
                ExecuteWithDelay(10, function() ExecuteInGameThread(function() pcall(aimUp) end) end)
            end
            if false and st and st ~= "P_Eve_GunNikke" and st:find("GunNikke", 1, true) and not rollBackAt then
                -- v0.67: release, then press (11-17 08:49 the stance came up on a false->true edge; repeated 'true' did nothing)
                aimKeepN = (aimKeepN or 0) + 1
                local k = aimKeepN
                ExecuteWithDelay(10, function() ExecuteInGameThread(function() if gunOn and not crouched then pressAim(false) end end) end)
                ExecuteWithDelay(80, function() ExecuteInGameThread(function() if gunOn and not crouched then pressAim(true) end end) end)
                if k <= 8 or k % 20 == 0 then
                    ExecuteWithDelay(450, function() ExecuteInGameThread(function()
                        local p2 = getPawn()
                        log("aim keep #" .. k .. ": stance was " .. st .. ", now " .. tostring(p2 and try(function() return p2:GetCurrentStanceName():ToString() end)))
                    end) end)
                end
            end
        end
        if CFG.KEEP_HUD and now >= hudNextAt then
            hudNextAt = now + 1.5
            ExecuteWithDelay(10, function() ExecuteInGameThread(function() if gunOn then pcall(hudRestore, "tick") end end) end)
        end
        if rollBackAt and now >= rollBackAt then
            rollBackAt = nil
            guardSince = now
            rollReadyAt = now + (CFG.ROLL_COOLDOWN or 1.2)   -- v0.66: a roll started while the gun was being put back crashed the game (11-17 log: roll #3 0.3 s after roll back)
            ExecuteWithDelay(1, function() ExecuteInGameThread(function()
                if not gunOn then return end
                -- v0.65: the full entry rows (GunOn alone left IsTPSMode false -> the empty-bag check ended Gun Mode)
                for _, r in ipairs(ON_ROWS) do pcall(fireRow, r) end
                if CFG.REAL_AMMO then pcall(fireRow, {2, "NGM_AE_ZeroOff"}) end
                if crouched then pcall(fireRow, {2, "NGM_AE_Pos2"}) else pcall(standOverride, true, "roll back") end
                ExecuteWithDelay(700, function() ExecuteInGameThread(function()
                    local p2 = getPawn()
                    if gunOn and p2 and rollLogs < 10 then rollLogs = rollLogs + 1
                        log("roll back: stance=" .. tostring(try(function() return p2:GetCurrentStanceName():ToString() end)) .. " IsTPSMode=" .. tostring(try(function() return p2:IsTPSMode() end))) end
                end) end)
            end) end)
        end
        if evadeAt and now >= evadeAt then
            evadeAt = nil
            pcall(fireRow, {2, "NGM_AE_PosOff"}); pcall(fireRow, {2, "NGM_AE_Pos2"})
            evadeN = (evadeN or 0) + 1
            if evadeN <= 10 then log("evade #" .. evadeN .. ": back to centre cover (Pos2)") end
        end
    end
end
hookTick = function()
    if tickHooked then return true end
    local ok, err = pcall(function()
        RegisterHook("/Game/Art/Character/PC/CH_P_EVE_01/Blueprints/CH_P_EVE_01_Blueprint.CH_P_EVE_01_Blueprint_C:ReceiveTick",
            function() engineTick() end)
    end)
    tickHooked = ok
    log("central tick: EVE ReceiveTick hook " .. (ok and "registered" or ("not yet (" .. tostring(err) .. ")")))
    return ok
end
-- v0.16: Ctrl+Shift+G (fire-route switch, a test key) removed - G is the only Gun Mode key now.


-- a new player pawn (map load, death, camp warp) starts out of gun mode
NotifyOnNewObject("/Script/SB.SBPlayerController", function(newPC)
    -- v0.59: cache the NEW controller directly. FindFirstOf could hand back the previous world's controller (still
    -- "valid" until GC ~2 s later) and the per-frame key reads then touched freed memory - the recurring crash ~2 s
    -- after a map load. Also pause the tick work while the new world settles.
    cachedPC = nil
    pcall(function() if newPC and newPC:IsValid() then cachedPC = newPC end end)
    tickPauseUntil = os.clock() + 4.0
    bagEmpty = false
    gunOn = false
    eveGUID = nil
    prevBullet = nil
    -- v0.8c: repair saves where v0.8b left the drone dismissed/locked: unlock and re-summon it once after loading
    ExecuteWithDelay(8000, function() ExecuteInGameThread(function()
        pcall(hookTick)
        if gunOn or not getPawn() then return end
        -- v0.39: the v0.8b save repair is opt-in now; zone events while a story map is still streaming crashed the
        -- laptop (11-16, 17 ms after these rows + the HUD check)
        if CFG.DRONE_FIX then
            for _, r in ipairs(DRONE_FIX_ROWS) do pcall(fireRow, r) end
            log("drone repair rows fired (unlock + summon)")
        end
        -- v0.36: find EVE's actor GUID on THIS machine/map. Ammo grant/spend (ItemBucketItemAdd/Remove) go to that GUID;
        -- the hard-coded 1501 came from the PC (11-14) and on the laptop the 60 starter rounds never arrived (she ran dry
        -- after 3 shots). Search = the v0.4c bullet-request probe, once per load, outside Gun Mode; her bullet is put back.
        if CFG.GUID_SEARCH and not eveGUID then
            local tries = 0
            local function gate()
                ExecuteInGameThread(function()
                    if eveGUID or scanning or gunOn or not getPawn() then return end
                    tries = tries + 1
                    if not inGameplay() and tries < 24 then ExecuteWithDelay(5000, gate); return end
                    if tries >= 24 then log("GUID search: main HUD never seen, searching anyway") end
                    scanForGUID("Bullet_Nikke", function(start)
                        if start ~= "Bullet_Nikke" then
                            start = start or "None"
                            prevBullet = start
                            ExecuteWithDelay(300, function() ExecuteInGameThread(function()
                                if not gunOn then setBullet(start); log("GUID search: bullet put back to " .. tostring(start)) end
                            end) end)
                        end
                    end)
                end)
            end
            ExecuteWithDelay(10000, gate)   -- v0.39: let the map finish streaming first
        end
    end) end)
end)

log("v0.70p loaded - G (or D-pad Right) toggles Gun Mode (standing); R3 / Caps Lock / Y = crouch (NIKKE cover + roll); LMB / R2 fires while standing")
