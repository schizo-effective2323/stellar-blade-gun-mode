# ngm_build_stand3.py - (11-17, desktop) zNikkeGunStand_P take 3: standing = the NIKKE AIM stance, always on.
#  stance : CharacterStanceTable row P_Eve_GunNikke loses its aim-key condition (Condition_PressCommandKey1 /
#           bActiveCheck_PressCommandKey1 -> zero): unversioned row, so the zero-mask bits are set and the 2 value bytes
#           removed; export SerialSize and BulkDataStartOffset in the .uasset -2. Read back with UAssetGUI as the gate.
#  bs     : the stand anims go into P_Eve_GunNikke_BS at the vanilla path (take 1 proved that path loads; the new-path
#           NGM_Stand_BS did not load in game, 11-17 09:38). No CharacterAnimSetTable patch.
# (take 2 notes follow)
# ngm_build_stand2.py - (11-17, desktop) zNikkeGunStand_P take 2: the standing animations go into their OWN blend space
#  NGM_Stand_BS and their OWN animset row NGM_Stand (CharacterAnimSetTable, written with UAssetGUI); vanilla
#  P_Eve_GunNikke_BS is no longer touched, so the crouched NIKKE aim keeps its kneel. Main.lua switches the standing
#  posture to the NGM_Stand animset at runtime. Rest as ngm_build_stand.py:
#  export : Blender 5.2 ngm_bl_export_stand.py           -> NikkeGunBuild\fbx\NGM_Stand_*.fbx (30 fps, in place)
#  import : UE 4.26 ngm_ue_stand.py (SBOutfitProject)     -> /Game/OutfitMods/NikkeGunMode/Anim/NGM_Stand_*
#  cook   : SBOutfitProject -CookAll -unversioned          -> OutfitWork\cook_ngm_<stamp>
#  patch  : the stand-in CH_P_EVE_01_Skeleton has 324 bones in its own order, the game's has ~3267: every cooked anim's
#           bone indices (TrackToSkeletonMapTable property + the compressed track table) are remapped by bone NAME to the
#           game skeleton, and the stand-in skeleton GUID is replaced by the game's (UAssetGUI json + Extras bytes).
#  bs     : vanilla P_Eve_Gun_BS (17 samples on LeftRight/FrontBack, the same axes as P_Eve_GunNikke_BS) renamed to
#           P_Eve_GunNikke_BS with its walks/idle pointed at the NGM_Stand_* anims
#  gate   : cue_loose reads every staged package back; every track must name a game bone
#  pak    : retoc to-zen -> NikkeGunBuild\standpak\zNikkeGunStand_P.* ; install copies into ~mods (game must be closed)
# args after the script path: steps (default all). Report: NikkeGunBuild\standpak_report.txt
import os, sys, json, glob, shutil, subprocess, time, struct, base64, re
HOME = os.path.expanduser("~")
T = os.path.join(HOME, r"Downloads\Modding Tools")
OW = os.path.join(T, "OutfitWork"); B = os.path.join(T, "NikkeGunBuild")
UE = r"C:\Program Files\Epic Games\UE_4.26\Engine\Binaries\Win64\UE4Editor-Cmd.exe"
UP = os.path.join(T, "SBOutfitProject", "SB.uproject")
B52 = r"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe"
RETOC = os.path.join(T, r"retoc_cli-x86_64-pc-windows-msvc\retoc.exe")
OODLE = os.path.join(T, r"retoc_cli-x86_64-pc-windows-msvc\oo2core_9_win64.dll")
USMAP = os.path.join(os.path.dirname(T), "StellarBlade_1.1.0.usmap")
UG = os.path.join(T, "UAssetGUI.exe"); UGMAP = "StellarBlade_1.1.0 (1)"
PAKS = r"C:\Program Files (x86)\Steam\steamapps\common\StellarBlade\SB\Content\Paks"
MODS = PAKS + r"\~mods"
NAME = "zNikkeGunStand_P"
ANIMSET = "NGM_Stand"
BSNAME = "P_Eve_GunNikke_BS"
EXTRA_ANIMS = ["DLC_2/Art/Character/PC/CH_P_EVE_01/Animation/P_Eve_GunNikke_Shoot"]
ANIM_REL = r"SB\Content\OutfitMods\NikkeGunMode\Anim"
BS_REL = r"SB\Content\Art\Character\PC\CH_P_EVE_01\Animation\BlendSpace"
BS_MAP = {  # vanilla P_Eve_Gun_BS sample -> our anim
    "P_Eve_Gun_WalkFw": "NGM_Stand_WalkF", "P_Eve_Gun_WalkBw": "NGM_Stand_WalkB", "P_Eve_Gun_WalkLw": "NGM_Stand_WalkL",
    "P_Eve_Gun_WalkRw": "NGM_Stand_WalkR", "P_Eve_Gun_WalkFRw": "NGM_Stand_WalkFR", "P_Eve_Gun_WalkBLw": "NGM_Stand_WalkBL",
    "P_Eve_Gun_Normal_Idle": "NGM_Stand_Idle"}
W = os.path.join(B, "standwork"); os.makedirs(W, exist_ok=True)
steps = [a for a in sys.argv[1:] if not a.endswith(".py")] or ["export", "import", "cook", "patch", "bs", "animset", "gate", "pak", "install"]
rep = open(os.path.join(B, "standpak_report.txt"), "w")
def P(s): rep.write(time.strftime("%H:%M:%S ") + str(s) + "\n"); rep.flush()
class Stop(Exception): pass
def stop(s): raise Stop(s)
def run(a, name, timeout=7200, cwd=None):
    lf = os.path.join(W, name + "_out.txt")
    with open(lf, "w", encoding="utf-8", errors="replace") as f:
        r = subprocess.run(a, stdout=f, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL, timeout=timeout, cwd=cwd, creationflags=0x08000000)
    P("> %s rc=%s (log %s)" % (name, r.returncode, os.path.basename(lf))); return r.returncode
def tool(pat):
    g = glob.glob(os.path.join(OW, pat, "bin", "Release", "*", pat + ".exe")); return g[0] if g else None
CL, CJ = tool("cue_loose"), tool("cue_json")
def cue_loose(root, tails, out):
    os.makedirs(out, exist_ok=True); run([CL, root, USMAP, OODLE, out, ";".join(tails)], "cue_loose_" + os.path.basename(out), timeout=1800)
def jl(p): return json.load(open(p, encoding="utf-8-sig"))
def guid_bytes(s):
    h = s.replace("-", ""); return struct.pack("<4I", *[int(h[i:i + 8], 16) for i in range(0, 32, 8)])
try:
    for f in glob.glob(os.path.join(MODS, NAME + ".*")):
        if os.path.getsize(f) == 0: os.remove(f); P("removed empty %s" % f)
    if "export" in steps:
        os.environ["NGM_INPLACE"] = "1"; os.environ["NGM_STAND_BLEND"] = os.environ.get("NGM_STAND_BLEND_SRC", os.path.join(B, "blend", "stand3", "NGM_Stand3.blend"))
        run([B52, "-b", "--factory-startup", "--python", os.path.join(OW, "ngm_bl_export_stand2.py")], "blender_export", timeout=3600)
        el = open(os.path.join(B, "fbx", "export_log.txt"), errors="replace").read()
        if "EXPORT DONE" not in el: stop("blender export failed - see fbx\\export_log.txt")
        P("export: %s" % [l for l in el.splitlines() if l.startswith(("armature", "exported"))])
    if "import" in steps:
        run([UE, UP, "-run=pythonscript", "-script=exec(open('" + os.path.join(OW, "ngm_ue_stand6.py").replace("\\", "/") + "').read())",
             "-unattended", "-nopause", "-nosplash", "-stdout", "-NoSound", "-AllowStdOutLogVerbosity"], "ue_import")
        il = open(os.path.join(B, "ue_stand_log.txt"), errors="replace").read()
        for l in il.splitlines(): P("   " + l[:500])
        if "ALL DONE" not in il or "IMPORT FAILED" in il: stop("UE import failed")
        hx = [float(m) for m in re.findall(r"\| Bip001 t=\(([-0-9.]+),", il)]
        if not hx or not all(80 < abs(x) < 120 for x in hx): stop("UE import: Bip001 height is %s, expected ~99 cm - unit scale wrong" % hx)
    if "cook" in steps:
        CK = os.path.join(OW, "cook_ngm_" + time.strftime("%m%d_%H%M%S"))
        run([UE, UP, "-run=cook", "-targetplatform=WindowsNoEditor", "-unversioned", "-unattended", "-nopause", "-stdout", "-NoSound",
             "-CookAll", "-OutputDir=" + CK], "cook")
        time.sleep(5)
    stage = os.path.join(W, "stage")
    if "patch" in steps:
        ck = sorted(glob.glob(os.path.join(OW, "cook_ngm_*")), key=os.path.getmtime)[-1]
        src = next((r for r, d, f in os.walk(ck) if r.replace("\\", "/").endswith("Content/OutfitMods/NikkeGunMode/Anim")), None)
        if not src: stop("our anims are not in the cook output " + ck)
        if os.path.exists(stage): shutil.rmtree(stage)
        dst0 = os.path.join(stage, ANIM_REL); shutil.copytree(src, dst0)
        ITEMS = [(dst0, f[:-7], "Content/OutfitMods/NikkeGunMode/Anim/") for f in sorted(os.listdir(dst0)) if f.endswith(".uasset")]
        # v5: replacements at game paths (the standing shot: P_Eve_GunNikke_Shoot, played full-body by the ShootSlug shows)
        for rel in EXTRA_ANIMS:
            hit = [r for r, d_, f_ in os.walk(ck) if r.replace("\\", "/").endswith("Content/" + os.path.dirname(rel)) and os.path.basename(rel) + ".uasset" in f_]
            if not hit: stop("cooked %s not found in %s" % (rel, ck))
            dd = os.path.join(stage, "SB", "Content", *os.path.dirname(rel).split("/")); os.makedirs(dd, exist_ok=True)
            for ext in (".uasset", ".uexp"): shutil.copyfile(os.path.join(hit[0], os.path.basename(rel) + ext), os.path.join(dd, os.path.basename(rel) + ext))
            ITEMS.append((dd, os.path.basename(rel), "Content/" + os.path.dirname(rel) + "/"))
        names = [it[1] for it in ITEMS]
        P("cook %s -> staged %s" % (os.path.basename(ck), names))
        # skeletons: stand-in from this cook, game from the paks
        cue_loose(ck, ["Content/Art/Character/PC/CH_P_EVE_01/CH_P_EVE_01_Skeleton"], os.path.join(W, "skel_standin"))
        run([CJ, os.path.join(W, "skel_game"), "SB/Content/Art/Character/PC/CH_P_EVE_01/CH_P_EVE_01_Skeleton"], "cue_json_skel", timeout=1800)
        def skel(p):
            e = [x for x in jl(p) if x.get("Type") == "Skeleton"][0]
            return [b["Name"] for b in e["ReferenceSkeleton"]["FinalRefBoneInfo"]], e["Guid"]
        sn, sg = skel(os.path.join(W, "skel_standin", "CH_P_EVE_01_Skeleton.json"))
        gn, gg = skel(os.path.join(W, "skel_game", "CH_P_EVE_01_Skeleton.json"))
        gi = {n: i for i, n in enumerate(gn)}
        P("skeletons: stand-in %d bones guid %s | game %d bones guid %s" % (len(sn), sg, len(gn), gg))
        cue_loose(stage, [t + n for d_, n, t in ITEMS], os.path.join(W, "anim_pre"))
        old_g, new_g = guid_bytes(sg), guid_bytes(gg)
        for dst, n, _t in ITEMS:
            e = [x for x in jl(os.path.join(W, "anim_pre", n + ".json")) if x.get("Type") == "AnimSequence"][0]
            tbl = e["CompressedTrackToSkeletonMapTable"]
            if e.get("CompressedCurveNames"): stop("%s has curves %s - curve UIDs would need remapping" % (n, e["CompressedCurveNames"]))
            if e["SkeletonGuid"] != sg: P("  note: %s SkeletonGuid %s is not the stand-in's" % (n, e["SkeletonGuid"]))
            miss = [sn[i] for i in tbl if sn[i] not in gi]
            if miss: stop("%s: tracks for bones the game skeleton lacks: %s" % (n, miss))
            new = [gi[sn[i]] for i in tbl]
            up = os.path.join(dst, n + ".uasset"); js = os.path.join(W, n + "_pre.json")
            run([UG, "tojson", up, js, "VER_UE4_26", UGMAP], "tojson_" + n, timeout=600)
            d = jl(js)
            ex = [x for x in d["Exports"] if x.get("ObjectName") == n or str(x.get("ObjectName", "")).startswith(n)]
            if len(ex) != 1: stop("%s: export not found in json" % n)
            ex = ex[0]
            # 1) TrackToSkeletonMapTable property (raw-track map), by element order = same tracks as the compressed table
            prop = next((p for p in ex["Data"] if p.get("Name") == "TrackToSkeletonMapTable"), None)
            if prop is not None:
                vals = prop["Value"]; tmpl = next((v["Value"][0] for v in vals if v.get("Value")), None)
                # v7: remap each raw entry by its OWN stand-in index (additive anims compress only the changed tracks, so the
                # raw table (all tracks) and the compressed table (11 for an aim pose) differ in length)
                for v in vals:
                    oi = v["Value"][0]["Value"] if v.get("Value") else 0
                    if sn[oi] not in gi: stop("%s: raw track bone %s not in the game skeleton" % (n, sn[oi]))
                    ni = gi[sn[oi]]
                    if v.get("Value"): v["Value"][0]["Value"] = ni
                    elif ni != 0:
                        it = json.loads(json.dumps(tmpl)); it["Value"] = ni; v["Value"] = [it]
                if len(vals) != len(tbl): P("  note: %s raw %d tracks, compressed %d (additive)" % (n, len(vals), len(tbl)))
            else: P("  note: %s has no TrackToSkeletonMapTable property" % n)
            # 2) native data: skeleton GUID + compressed track table
            raw = bytearray(base64.b64decode(ex["Extras"]))
            c = raw.count(old_g)
            if c < 1: stop("%s: stand-in GUID not found in the native data" % n)
            raw = raw.replace(old_g, new_g)
            pat = struct.pack("<%di" % (len(tbl) + 1), len(tbl), *tbl)
            if raw.count(pat) != 1: stop("%s: compressed track table found %d times" % (n, raw.count(pat)))
            at = raw.find(pat); raw[at:at + len(pat)] = struct.pack("<%di" % (len(new) + 1), len(new), *new)
            ex["Extras"] = base64.b64encode(bytes(raw)).decode()
            pj = os.path.join(W, n + "_patched.json")
            json.dump(d, open(pj, "w", encoding="utf-8"))
            os.remove(up); os.remove(up[:-7] + ".uexp")
            run([UG, "fromjson", pj, up, UGMAP], "fromjson_" + n, timeout=600)
            if not os.path.exists(up): stop("%s: fromjson wrote nothing" % n)
            P("  %s: %d tracks remapped (e.g. %s), guid x%d, prop %s" % (n, len(tbl), list(zip(tbl[24:30], new[24:30])), c, prop is not None))
        json.dump({"stand_in": sn, "game_guid": gg}, open(os.path.join(W, "skel_map.json"), "w"))
    if "bs" in steps:
        leg = os.path.join(W, "legacy_bs")
        if os.path.exists(leg): shutil.rmtree(leg)
        run([RETOC, "to-legacy", PAKS, leg, "-f", "Art/Character/PC/CH_P_EVE_01/Animation/BlendSpace/P_Eve_Gun_BS.uasset"], "retoc_legacy_bs", timeout=1800)
        vb = os.path.join(leg, BS_REL, "P_Eve_Gun_BS.uasset")
        if not os.path.exists(vb): stop("vanilla P_Eve_Gun_BS not extracted")
        js = os.path.join(W, "bs_pre.json"); run([UG, "tojson", vb, js, "VER_UE4_26", UGMAP], "tojson_bs", timeout=600)
        txt = open(js, encoding="utf-8-sig").read()
        paths = sorted(set(re.findall(r'"(/Game/[^"]*/(P_Eve_Gun_[A-Za-z_]+))"', txt)))
        P("bs: vanilla references %s" % paths)
        done = set()
        for full, short in paths:
            if short in BS_MAP:
                txt = txt.replace('"%s"' % full, '"/Game/OutfitMods/NikkeGunMode/Anim/%s"' % BS_MAP[short]); done.add(short)
        for short, ours in BS_MAP.items():
            txt = txt.replace('"%s"' % short, '"%s"' % ours)
        if done != set(BS_MAP): stop("bs: not every sample path found: %s" % (set(BS_MAP) - done))
        # the vanilla BS also imports each walk's footstep notify objects (preload deps); ours don't have them: drop those
        # imports (they are the tail of the import table, so no other index moves) and their dependency entries
        dj = json.loads(txt); ims = dj["Imports"]
        drop = [-(i + 1) for i, im in enumerate(ims) if "AnimNotify" in str(im.get("ClassName"))]
        if drop and sorted(drop) != list(range(-len(ims), -len(ims) + len(drop))): stop("bs: notify imports are not the tail of the import table: %s" % drop)
        dj["Imports"] = ims[:len(ims) - len(drop)]
        for ex_ in dj["Exports"]:
            for k_ in ("SerializationBeforeSerializationDependencies", "CreateBeforeSerializationDependencies", "SerializationBeforeCreateDependencies", "CreateBeforeCreateDependencies"):
                if isinstance(ex_.get(k_), list): ex_[k_] = [x for x in ex_[k_] if x not in drop]
        if any(str(x) in json.dumps(dj["Exports"][0]["Data"]) for x in []): pass
        P("bs: dropped %d notify imports %s" % (len(drop), drop))
        txt = json.dumps(dj)
        txt = txt.replace('"/Game/Art/Character/PC/CH_P_EVE_01/Animation/BlendSpace/P_Eve_Gun_BS"',
                          '"/Game/Art/Character/PC/CH_P_EVE_01/Animation/BlendSpace/' + BSNAME + '"').replace('"P_Eve_Gun_BS"', '"' + BSNAME + '"')
        left = re.findall(r'P_Eve_Gun_(?:Walk|Normal)[A-Za-z_]*', txt)
        if left: stop("bs: vanilla anim names left: %s" % sorted(set(left)))
        pj = os.path.join(W, "bs_patched.json"); open(pj, "w", encoding="utf-8").write(txt)
        od = os.path.join(stage, BS_REL); os.makedirs(od, exist_ok=True)
        out = os.path.join(od, BSNAME + ".uasset")
        for f in glob.glob(out[:-7] + ".*"): os.remove(f)
        run([UG, "fromjson", pj, out, UGMAP], "fromjson_bs", timeout=600)
        if not os.path.exists(out): stop("bs: fromjson wrote nothing")
        P("bs: written %s (%d + %d bytes)" % (out, os.path.getsize(out), os.path.getsize(out[:-7] + ".uexp")))
    if "aimbs" in steps:   # v7: Aim_BS (aim offset of P_Eve_GunNikke / GunNikkeHide / Gun_Battle) -> our rifle aim poses
        AIM_REL = r"SB\Content\Art\Character\PC\CH_P_EVE_01\Animation\Additive"
        leg = os.path.join(W, "legacy_aimbs")
        if os.path.exists(leg): shutil.rmtree(leg)
        run([RETOC, "to-legacy", PAKS, leg, "-f", "Art/Character/PC/CH_P_EVE_01/Animation/Additive/Aim_BS.uasset"], "retoc_legacy_aimbs", timeout=1800)
        va = os.path.join(leg, AIM_REL, "Aim_BS.uasset")
        if not os.path.exists(va): stop("vanilla Aim_BS not extracted")
        js = os.path.join(W, "aimbs_pre.json"); run([UG, "tojson", va, js, "VER_UE4_26", UGMAP], "tojson_aimbs", timeout=600)
        txt = open(js, encoding="utf-8-sig").read()
        n = 0
        for a in ("UpLeft", "UpRight", "DownLeft", "DownRight", "Up", "Down", "Left", "Right"):
            full = "/Game/Art/Character/PC/CH_P_EVE_01/Animation/Aim/TPSCommon/Aim_" + a
            if '"%s"' % full in txt: n += 1
            txt = txt.replace('"%s"' % full, '"/Game/OutfitMods/NikkeGunMode/Anim/NGM_Stand_Aim_%s"' % a).replace('"Aim_%s"' % a, '"NGM_Stand_Aim_%s"' % a)
        if n != 8: stop("aimbs: %d of 8 sample paths found" % n)
        left = re.findall(r'TPSCommon/Aim_[A-Za-z]+', txt)
        if left: stop("aimbs: vanilla samples left %s" % left)
        dj = json.loads(txt); ims = dj["Imports"]
        drop = [-(i + 1) for i, im in enumerate(ims) if "AnimNotify" in str(im.get("ClassName"))]
        if drop:
            if sorted(drop) != list(range(-len(ims), -len(ims) + len(drop))): stop("aimbs: notify imports not at the tail")
            dj["Imports"] = ims[:len(ims) - len(drop)]
            for ex_ in dj["Exports"]:
                for k_ in ("SerializationBeforeSerializationDependencies", "CreateBeforeSerializationDependencies", "SerializationBeforeCreateDependencies", "CreateBeforeCreateDependencies"):
                    if isinstance(ex_.get(k_), list): ex_[k_] = [x for x in ex_[k_] if x not in drop]
        pj = os.path.join(W, "aimbs_patched.json"); open(pj, "w", encoding="utf-8").write(json.dumps(dj))
        od = os.path.join(stage, AIM_REL); os.makedirs(od, exist_ok=True)
        out = os.path.join(od, "Aim_BS.uasset")
        for f in glob.glob(out[:-7] + ".*"): os.remove(f)
        run([UG, "fromjson", pj, out, UGMAP], "fromjson_aimbs", timeout=600)
        if not os.path.exists(out): stop("aimbs: fromjson wrote nothing")
        P("aimbs: written %s (%d samples -> NGM_Stand_Aim_*, dropped %d notify imports)" % (out, n, len(drop)))
    if "animset" in steps:
        leg = os.path.join(W, "legacy_animset")
        if os.path.exists(leg): shutil.rmtree(leg)
        run([RETOC, "to-legacy", PAKS, leg, "-f", "Local/Data/CharacterAnimSetTable.uasset"], "retoc_legacy_animset", timeout=1800)
        va = os.path.join(leg, r"SB\Content\Local\Data\CharacterAnimSetTable.uasset")
        if not os.path.exists(va): stop("vanilla CharacterAnimSetTable not extracted")
        js = os.path.join(W, "animset_pre.json"); run([UG, "tojson", va, js, "VER_UE4_26", UGMAP], "tojson_animset", timeout=900)
        d = jl(js); rows = d["Exports"][0]["Table"]["Data"]
        if any(r["Name"] == ANIMSET for r in rows): stop("animset row %s already in the vanilla table?" % ANIMSET)
        src = [r for r in rows if r["Name"] == "P_Eve_GunNikke"]
        if len(src) != 1: stop("P_Eve_GunNikke animset row not found")
        new = json.loads(json.dumps(src[0])); new["Name"] = ANIMSET
        ids = [p["Value"] for r in rows for p in r["Value"] if p.get("Name") == "ID"]
        # v2b: the ID stays in EVE's block (3000-3029); max(ids)+1 = 596102 sat in Scarlet's block and G crashed (11-17 09:31)
        nid = max(i for i in ids if 3000 <= i < 4000) + 1; ch = []
        if nid in ids or nid >= 4000: stop("no free ID in EVE's animset block")
        for p in new["Value"]:
            if p.get("Name") == "ID": p["Value"] = nid
            if isinstance(p.get("Value"), str) and p["Value"] == "Animation/BlendSpace/P_Eve_GunNikke_BS":
                p["Value"] = "Animation/BlendSpace/NGM_Stand_BS"; ch.append(p["Name"])
        if len(ch) < 2: stop("animset: blend-space fields not found in the cloned row: %s" % ch)
        rows.append(new)
        if ANIMSET not in d["NameMap"]: d["NameMap"].append(ANIMSET)
        pj = os.path.join(W, "animset_patched.json"); json.dump(d, open(pj, "w", encoding="utf-8"))
        od = os.path.join(stage, r"SB\Content\Local\Data"); os.makedirs(od, exist_ok=True)
        out = os.path.join(od, "CharacterAnimSetTable.uasset")
        for f in glob.glob(out[:-7] + ".*"): os.remove(f)
        run([UG, "fromjson", pj, out, UGMAP], "fromjson_animset", timeout=900)
        if not os.path.exists(out): stop("animset: fromjson wrote nothing")
        rb = os.path.join(W, "animset_readback.json"); run([UG, "tojson", out, rb, "VER_UE4_26", UGMAP], "tojson_animset_rb", timeout=900)
        rrows = jl(rb)["Exports"][0]["Table"]["Data"]
        got = [r for r in rrows if r["Name"] == ANIMSET]
        if len(rrows) != len(rows) or not got: stop("animset readback: %d rows (want %d), new row %s" % (len(rrows), len(rows), bool(got)))
        P("animset: row %s (ID %d) added, fields %s -> NGM_Stand_BS; %d rows, readback ok" % (ANIMSET, nid, ch, len(rrows)))
    if "stance" in steps:
        leg = os.path.join(W, "legacy_stance")
        if os.path.exists(leg): shutil.rmtree(leg)
        run([RETOC, "to-legacy", PAKS, leg, "-f", "Local/Data/CharacterStanceTable.uasset"], "retoc_legacy_stance", timeout=1800)
        va = os.path.join(leg, r"SB\Content\Local\Data\CharacterStanceTable")
        if not os.path.exists(va + ".uexp"): stop("vanilla CharacterStanceTable not extracted")
        js = os.path.join(W, "stance_pre.json"); run([UG, "tojson", va + ".uasset", js, "VER_UE4_26", UGMAP], "tojson_stance", timeout=900)
        d = jl(js); nm = d["NameMap"]; ix = {n: i for i, n in enumerate(nm)}
        rows = d["Exports"][0]["Table"]["Data"]; ser = d["Exports"][0]["SerialSize"]
        MODE = os.environ.get("NGM_STANCE_MODE", "both")
        if MODE == "hide":
            # take 4: the cover stance P_Eve_GunNikkeHide (the one G lands in, no aim key) becomes standing: gun NOT folded
            # (bForceFoldingWeapon -> zero: mask bit + 1 byte out) and its animsets -> P_Eve_GunNikke (= the stand blend space)
            row = [r for r in rows if r["Name"] == "P_Eve_GunNikkeHide"][0]
            names = [p["Name"] for p in row["Value"]]; zero = [bool(p.get("IsZero")) for p in row["Value"]]
            ifold = names.index("bForceFoldingWeapon")
            if zero[ifold]: stop("stance[hide]: bForceFoldingWeapon already zero?")
            ue = bytearray(open(va + ".uexp", "rb").read()); ua = bytearray(open(va + ".uasset", "rb").read())
            hdr = struct.pack("<ii", ix["P_Eve_GunNikkeHide"], 0); frag = 0x80 | 0x100 | (len(names) << 9)
            key = hdr + struct.pack("<H", frag)
            if bytes(ue).count(key) != 1: stop("stance[hide]: row header found %d times" % bytes(ue).count(key))
            at = bytes(ue).find(key); mpos = at + 10; nwords = (len(names) + 31) // 32
            mask = int.from_bytes(ue[mpos:mpos + 4 * nwords], "little")
            if any(bool(mask >> k & 1) != zero[k] for k in range(len(names))): stop("stance[hide]: zero mask does not match the json")
            pos = mpos + 4 * nwords
            for k in range(ifold):
                if zero[k]: continue
                t = row["Value"][k]["$type"]
                if "UInt32" in t or "IntProperty" in t: pos += 4
                elif "BoolProperty" in t or "EnumProperty" in t: pos += 1
                elif "ArrayProperty" in t: pos += 4 + 8 * struct.unpack_from("<i", ue, pos)[0]
                else: stop("stance[hide]: unexpected type before bForceFoldingWeapon: %s %s" % (names[k], t))
            if ue[pos] != 1: stop("stance[hide]: expected bForceFoldingWeapon=1 at %d, got %d" % (pos, ue[pos]))
            mask |= 1 << ifold; ue[mpos:mpos + 4 * nwords] = mask.to_bytes(4 * nwords, "little"); del ue[pos:pos + 1]; dn = 1
            run4 = struct.pack("<8i", *([ix["P_Eve_GunNikkeHide"], 0] * 4)); new4 = struct.pack("<8i", *([ix["P_Eve_GunNikke"], 0] * 4))
            j = bytes(ue).find(run4, pos)
            if j < 0 or j - pos > 400: stop("stance[hide]: animset run not found right after the row's fold flag (%d)" % j)
            ue[j:j + 32] = new4
            # bDisableMovingTransit -> true (the aim stance has it): the P_Eve_GunNikke animset has no start/stop/turn
            # transition anims, and the cover stance moving with them froze and crashed the game (11-17 10:24)
            itr = names.index("bDisableMovingTransit")
            last = max(k for k in range(len(names)) if not zero[k] and k != ifold)
            if not zero[itr] or last != itr - 1 or names[last] != "AnimSet_Airborne_LowerBody": stop("stance[hide]: unexpected layout around bDisableMovingTransit")
            ins = j + 32 + 8 * 8            # after AnimSet 65-68 (j) and the 8 names 69-76
            mask &= ~(1 << itr); ue[mpos:mpos + 4 * nwords] = mask.to_bytes(4 * nwords, "little")
            ue[ins:ins] = b"\x01"; dn -= 1
            ser = d["Exports"][0]["SerialSize"]
            so = bytes(ua).find(struct.pack("<q", ser)); bo = bytes(ua).find(struct.pack("<q", len(ua) + ser))
            if so < 0 or bo < 0: stop("stance[hide]: SerialSize/BulkDataStartOffset not found")
            ua[so:so + 8] = struct.pack("<q", ser - dn); ua[bo:bo + 8] = struct.pack("<q", len(ua) + ser - dn)
            od = os.path.join(stage, r"SB\Content\Local\Data"); os.makedirs(od, exist_ok=True)
            for f in glob.glob(os.path.join(od, "CharacterStanceTable.*")): os.remove(f)
            out = os.path.join(od, "CharacterStanceTable")
            open(out + ".uasset", "wb").write(ua); open(out + ".uexp", "wb").write(ue)
            rb = os.path.join(W, "stance_readback.json"); run([UG, "tojson", out + ".uasset", rb, "VER_UE4_26", UGMAP], "tojson_stance_rb", timeout=900)
            r2 = jl(rb)["Exports"][0]["Table"]["Data"]
            g = {p["Name"]: p for p in [r for r in r2 if r["Name"] == "P_Eve_GunNikkeHide"][0]["Value"]}
            same = [r["Name"] for r in r2] == [r["Name"] for r in rows]
            ok = same and g["bForceFoldingWeapon"].get("IsZero") and g["AnimSet_Battle_LowerBody"]["Value"] == "P_Eve_GunNikke" and \
                 g["AnimSet_Groggy_UpperBody"]["Value"] == "Groggy" and g["WalkSpeed"]["Value"] == 150.0 and json.dumps(r2[-1]) == json.dumps(rows[-1]) and \
                 g["bDisableMovingTransit"]["Value"] is True and g["AnimSet_Airborne_LowerBody"]["Value"] == "Airborne"
            P("stance [hide]: P_Eve_GunNikkeHide gun unfolded + animsets -> P_Eve_GunNikke; readback rows same %s, ok %s" % (same, bool(ok)))
            if not ok: stop("stance[hide] readback gate failed - see " + rb)
        if MODE != "hide":   # aim row patch (takes 3b/3c)
            row = [r for r in rows if r["Name"] == "P_Eve_GunNikke"][0]
            names = [p["Name"] for p in row["Value"]]; zero = [bool(p.get("IsZero")) for p in row["Value"]]
            i22, i23 = names.index("Condition_PressCommandKey1"), names.index("bActiveCheck_PressCommandKey1")
            if zero[i22] or zero[i23]: stop("stance: the aim-key condition is already zero?")
            ue = bytearray(open(va + ".uexp", "rb").read()); ua = bytearray(open(va + ".uasset", "rb").read())
            hdr = struct.pack("<ii", ix["P_Eve_GunNikke"], 0)
            frag = 0 | 0x80 | 0x100 | (len(names) << 9)            # skip 0, has zeroes, last, all values in one fragment
            at = bytes(ue).find(hdr + struct.pack("<H", frag))
            if at < 0 or bytes(ue).count(hdr + struct.pack("<H", frag)) != 1: stop("stance: row header not found once")
            mpos = at + 8 + 2; nwords = (len(names) + 31) // 32; mask = int.from_bytes(ue[mpos:mpos + 4 * nwords], "little")
            if any(bool(mask >> k & 1) != zero[k] for k in range(len(names))): stop("stance: zero mask does not match the json")
            # value offsets: walk the non-zero values up to i22 (ID u32, Priority i32, enums 1 byte, name arrays 4 + 8n)
            pos = mpos + 4 * nwords
            for k in range(i22):
                if zero[k]: continue
                t = row["Value"][k]["$type"]
                if "UInt32" in t or "IntProperty" in t: pos += 4
                elif "EnumProperty" in t: pos += 1
                elif "ArrayProperty" in t: pos += 4 + 8 * struct.unpack_from("<i", ue, pos)[0]
                else: stop("stance: unexpected property type before the key condition: %s %s" % (names[k], t))
            if ue[pos] != 43 or ue[pos + 1] != 1: stop("stance: expected TPSMode(43), true(1) at %d, got %s" % (pos, ue[pos:pos + 2].hex()))
            MODE = os.environ.get("NGM_STANCE_MODE", "both")   # both = key + check zeroed (3b: aim never came up); bool = only bActiveCheck zeroed
            if MODE == "bool":
                mask |= (1 << i23); ue[mpos:mpos + 4 * nwords] = mask.to_bytes(4 * nwords, "little"); del ue[pos + 1:pos + 2]; dn = 1
            else:
                mask |= (1 << i22) | (1 << i23); ue[mpos:mpos + 4 * nwords] = mask.to_bytes(4 * nwords, "little"); del ue[pos:pos + 2]; dn = 2
            so = bytes(ua).find(struct.pack("<q", ser)); bo = bytes(ua).find(struct.pack("<q", len(ua) + ser))
            if so < 0 or bo < 0 or bytes(ua).count(struct.pack("<q", ser)) != 1: stop("stance: SerialSize/BulkDataStartOffset not found in the uasset")
            ua[so:so + 8] = struct.pack("<q", ser - dn); ua[bo:bo + 8] = struct.pack("<q", len(ua) + ser - dn)
            od = os.path.join(stage, r"SB\Content\Local\Data"); os.makedirs(od, exist_ok=True)
            for f in glob.glob(os.path.join(od, "CharacterStanceTable.*")): os.remove(f)
            out = os.path.join(od, "CharacterStanceTable")
            open(out + ".uasset", "wb").write(ua); open(out + ".uexp", "wb").write(ue)
            rb = os.path.join(W, "stance_readback.json"); run([UG, "tojson", out + ".uasset", rb, "VER_UE4_26", UGMAP], "tojson_stance_rb", timeout=900)
            d2 = jl(rb); r2 = d2["Exports"][0]["Table"]["Data"]
            g = {p["Name"]: p for p in [r for r in r2 if r["Name"] == "P_Eve_GunNikke"][0]["Value"]}
            same = [r["Name"] for r in r2] == [r["Name"] for r in rows]
            ok = same and (MODE == "bool" or g["Condition_PressCommandKey1"].get("IsZero")) and g["bActiveCheck_PressCommandKey1"].get("IsZero") and \
                 g["CommandArray"]["Value"] and [x["Value"] for x in g["CommandArray"]["Value"]][:2] == ["P_Eve_GunNikke_Evade1_1", "P_Eve_GunNikke_Evade1_2"] and \
                 json.dumps(r2[-1]) == json.dumps(rows[-1])
            P("stance [" + MODE + "]: P_Eve_GunNikke aim-key condition changed (mask bits %d,%d; bytes at %d); readback rows same %s, ok %s" % (i22, i23, pos, same, bool(ok)))
            if not ok: stop("stance readback gate failed - see " + rb)
    if "gate" in steps:
        sm = jl(os.path.join(W, "skel_map.json"))
        run([CJ, os.path.join(W, "skel_game"), "SB/Content/Art/Character/PC/CH_P_EVE_01/CH_P_EVE_01_Skeleton"], "cue_json_skel2", timeout=1800)
        gn = [b["Name"] for b in [x for x in jl(os.path.join(W, "skel_game", "CH_P_EVE_01_Skeleton.json")) if x.get("Type") == "Skeleton"][0]["ReferenceSkeleton"]["FinalRefBoneInfo"]]
        tails = ["Content/OutfitMods/NikkeGunMode/Anim/" + f[:-7] for f in sorted(os.listdir(os.path.join(stage, ANIM_REL))) if f.endswith(".uasset")] + ["Content/" + r for r in EXTRA_ANIMS]
        names = [t.rsplit("/", 1)[-1] for t in tails]
        cue_loose(stage, tails + ["Content/Art/Character/PC/CH_P_EVE_01/Animation/BlendSpace/" + BSNAME], os.path.join(W, "post"))
        pre_dir = os.path.join(W, "anim_pre")
        for n in names:
            pf = os.path.join(W, "post", n + ".json")
            if not os.path.exists(pf): stop("gate: %s could not be read back" % n)
            e = [x for x in jl(pf) if x.get("Type") == "AnimSequence"][0]
            e0 = [x for x in jl(os.path.join(pre_dir, n + ".json")) if x.get("Type") == "AnimSequence"][0]
            okn = [sm["stand_in"][a] == gn[b] for a, b in zip(e0["CompressedTrackToSkeletonMapTable"], e["CompressedTrackToSkeletonMapTable"])]
            same = e0.get("CompressedRawDataSize") == e.get("CompressedRawDataSize") and e0.get("CompressedDataStructure") == e.get("CompressedDataStructure")
            P("gate %s: %d tracks, names ok %s, guid %s, compressed data unchanged %s, len %s" % (n, len(okn), all(okn), e["SkeletonGuid"] == sm["game_guid"], same, e["Properties"].get("SequenceLength")))
            if not all(okn) or not same: stop("gate failed for " + n)
        bf = os.path.join(W, "post", BSNAME + ".json")
        if not os.path.exists(bf): stop("gate: BS could not be read back")
        bp = [x for x in jl(bf) if x.get("Type", "").startswith("BlendSpace")][0]["Properties"]
        sd = [(s["Animation"]["ObjectPath"].rsplit("/", 1)[-1], s["SampleValue"]["X"], s["SampleValue"]["Y"]) for s in bp["SampleData"]]
        P("gate BS: %s params %s / %s" % (sd, bp["BlendParameters"]["DisplayName"], bp["BlendParameters[1]"]["DisplayName"]))
        if any(not a.startswith("NGM_Stand_") for a, x, y in sd): stop("gate: BS sample not ours")
    if "pak" in steps:
        pk = os.path.join(B, "standpak"); os.makedirs(pk, exist_ok=True)
        for f in glob.glob(os.path.join(pk, "*")): os.remove(f)
        subprocess.run(["taskkill", "/F", "/IM", "SB-Win64-Shipping.exe"], capture_output=True, creationflags=0x08000000); time.sleep(6)
        for f in glob.glob(os.path.join(MODS, NAME + ".*")): os.remove(f); P("removed old %s" % f)
        rc = run([RETOC, "to-zen", stage, os.path.join(pk, NAME + ".utoc"), "--version", "UE4_26"], "retoc_zen", timeout=1800)
        outs = sorted(os.listdir(pk))
        if rc != 0 or not any(f.endswith(".utoc") for f in outs) or any(os.path.getsize(os.path.join(pk, f)) == 0 for f in outs):
            stop("to-zen failed: " + open(os.path.join(W, "retoc_zen_out.txt"), errors="replace").read()[-600:])
        P("pak: %s" % {f: os.path.getsize(os.path.join(pk, f)) for f in outs})
    if "install" in steps:
        tl = subprocess.run(["tasklist"], capture_output=True, text=True, creationflags=0x08000000).stdout.lower()
        if "sb-win64-shipping" in tl:
            subprocess.run(["taskkill", "/F", "/IM", "SB-Win64-Shipping.exe"], capture_output=True, creationflags=0x08000000); time.sleep(6)
        pk = os.path.join(B, "standpak")
        for f in sorted(os.listdir(pk)):
            shutil.copyfile(os.path.join(pk, f), os.path.join(MODS, f)); P("installed %s" % f)
    P("BUILD OK")
except Stop as e: P("STOP: %s" % e)
except Exception:
    import traceback; P("ERROR " + traceback.format_exc())
P("FINISHED"); rep.close()
