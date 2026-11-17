# ngm_build_cmdpak2.py - (11-15, NikkeGunMode) as ngm_build_cmdpak.py, plus SkillActiveStepTable: the NIKKE shot's
# fire step P_Eve_GunNikke_ShootSlug1_1_Hit1 changed from SkillActiveStepType_Item (spends the bullet the fire command
# picked - there is none when the NGM_Fire effect starts the skill) to the plain step type its Cast1 uses, so the step
# just fires its projectile P_Eve_GunNikke_ShootSlug1_Projectile1. (Real stages then don't spend NIKKE ammo.)
# Original header: build zNikkeGunMode_P: vanilla SkillCommandTable with the two
# NIKKE fire commands (P_Eve_GunNikke_ShootSlug1_1/_2) switched from RangedFireItem (fires only while the
# equipped bullet is Bullet_Nikke) to RangedFireSkill (no bullet check, like the burst shot ShootSlug2).
# Survival Protocol's pak doesn't carry SkillCommandTable, so this is its own pak. Report: NikkeGunBuild\cmdpak_report.txt
import os, subprocess, shutil, json, hashlib
HOME = os.path.expanduser("~")
T = os.path.join(HOME, r"Downloads\Modding Tools")
B = os.path.join(T, "NikkeGunBuild")
RETOC = os.path.join(T, r"retoc_cli-x86_64-pc-windows-msvc\retoc.exe")
UAG = os.path.join(T, "UAssetGUI.exe")
MODS = r"C:\Program Files (x86)\Steam\steamapps\common\StellarBlade\SB\Content\Paks\~mods"
NAME = "zNikkeGunMode_P"
rep = open(os.path.join(B, "cmdpak2_report.txt"), "w")
def P(s): rep.write(s + "\n"); rep.flush()
try:
    src = os.path.join(B, "json", "SkillCommandTable.json")
    text = open(src, encoding="utf-8-sig", newline="").read()
    patch = json.load(open(os.path.join(B, "SkillCommandTable.ngm.patch"), encoding="utf-8"))
    for n, e in enumerate(patch["edits"], 1):
        c = text.count(e["find"])
        if c != 1: raise Exception("edit %d: found %d times" % (n, c))
        text = text.replace(e["find"], e["replace"], 1); P("edit %d applied" % n)
    work = os.path.join(B, "work2"); stage = os.path.join(B, "stage2"); out = os.path.join(B, "out2")
    for d in (work, stage, out):
        if os.path.exists(d): shutil.rmtree(d)
        os.makedirs(d)
    wj = os.path.join(work, "SkillCommandTable.json")
    open(wj, "w", encoding="utf-8", newline="").write(text)
    data = os.path.join(stage, r"SB\Content\Local\Data"); os.makedirs(data)
    dst = os.path.join(data, "SkillCommandTable.uasset")
    r = subprocess.run([UAG, "fromjson", wj, dst, "StellarBlade"], capture_output=True, text=True, timeout=900, creationflags=0x08000000)
    P("fromjson: exists=%s %s" % (os.path.exists(dst), (r.stdout + r.stderr).strip()[-300:]))
    if not os.path.exists(dst): raise Exception("fromjson failed")
    # --- SkillActiveStepTable: Hit1 Item -> plain ---
    import re
    st = open(os.path.join(B, "json", "SkillActiveStepTable.json"), encoding="utf-8-sig", newline="").read()
    def row_span(t, name):
        m = re.search(r'"Name": "%s",' % re.escape(name), t)
        s = t.rindex('{', 0, t.rindex('"$type": "UAssetAPI.PropertyTypes.Structs.StructPropertyData', 0, m.start()))
        d = 0
        for j in range(s, len(t)):
            if t[j] == '{': d += 1
            elif t[j] == '}':
                d -= 1
                if d == 0: return s, j + 1
    def type_value(block):
        m = re.search(r'"Name": "Type",.*?"Value": "([^"]+)"', block, re.S)
        return m.group(1) if m else None
    cs, ce = row_span(st, "P_Eve_GunNikke_ShootSlug1_1_Cast1")
    plain = type_value(st[cs:ce])
    hs, he = row_span(st, "P_Eve_GunNikke_ShootSlug1_1_Hit1")
    hit = st[hs:he]
    P("Cast1 Type = %s, Hit1 Type = %s" % (plain, type_value(hit)))
    if not plain or plain == "SkillActiveStepType_Item": raise Exception("no plain step type found")
    if hit.count('"SkillActiveStepType_Item"') != 1: raise Exception("Hit1 Item type not found once")
    hit = hit.replace('"SkillActiveStepType_Item"', '"%s"' % plain)
    # v2 (11-15 16:58): with no target the shot's MainTarget projectile goes nowhere (sound + muzzle flash only, no
    # damage). Fire it straight ahead like EVE's Sword Aura steps: UsableNonTargetProjectileTargetType -> NonTarget.
    m = re.search(r'("Name": "UsableNonTargetProjectileTargetType",.*?"Value": )"SkillProjectileTargetType_MainTarget"', hit, re.S)
    if not m: raise Exception("Hit1 non-target projectile type not found")
    hit = hit[:m.start()] + m.group(1) + '"SkillProjectileTargetType_NonTarget"' + hit[m.end():]
    P("Hit1: UsableNonTargetProjectileTargetType -> NonTarget")
    # v3 (11-15 17:25): the effect-started shot carries no direction (flies world +X). Detect targets inside the aim
    # reticle like EVE's drone missile (P_Eve_Gun_ShootMissile1_1_Hit1): AimLockOnBounds, max 1 target, overlap 8.
    def setval(block, prop, old_v, new_v):
        m = re.search(r'("Name": "%s",.*?"Value": )%s' % (prop, re.escape(old_v)), block, re.S)
        if not m: raise Exception("%s = %s not found" % (prop, old_v))
        return block[:m.start()] + m.group(1) + new_v + block[m.end():]
    hit = setval(hit, "TargetDetectionType", '"SkillTargetDetectionType_TargetFilter"', '"SkillTargetDetectionType_AimLockOnBounds"')
    hit = setval(hit, "AimLockOnTargetMaxCount", "0", "1")
    hit = setval(hit, "AimLockOnTargetOverlapCount", "0", "8")
    P("Hit1: TargetDetectionType -> AimLockOnBounds, AimLockOnTargetMaxCount 1, overlap 8")
    st = st[:hs] + hit + st[he:]
    wj2 = os.path.join(work, "SkillActiveStepTable.json")
    open(wj2, "w", encoding="utf-8", newline="").write(st)
    del st
    dst2 = os.path.join(data, "SkillActiveStepTable.uasset")
    r = subprocess.run([UAG, "fromjson", wj2, dst2, "StellarBlade"], capture_output=True, text=True, timeout=1800, creationflags=0x08000000)
    P("fromjson steps: exists=%s %s" % (os.path.exists(dst2), (r.stdout + r.stderr).strip()[-300:]))
    if not os.path.exists(dst2): raise Exception("fromjson steps failed")
    # --- v4 (11-15 17:35) ProjectileTable: the NIKKE bullet starts at the gun socket SC_GunShoot with its rotation,
    # but StartTargetRelativeAxisType World turns it to world +X ("north"). ParentAxis = follow the muzzle socket.
    pt = open(os.path.join(B, "json", "ProjectileTable.json"), encoding="utf-8-sig", newline="").read()
    ps, pe = row_span(pt, "P_Eve_GunNikke_ShootSlug1_Projectile1")
    prow = pt[ps:pe]
    # v6 (11-15 17:55): the axis types made no difference - the shot simply has no direction when an effect starts it.
    # So give it a destination on EVE herself: 50000 units out along the muzzle socket SC_GunShoot's own forward axis.
    def pset(block, prop, old_v, new_v, nth_value=False):
        m = re.search(r'("Name": "%s",.*?"Value": )%s' % (prop, re.escape(old_v)), block, re.S)
        if not m: raise Exception("projectile %s = %s not found" % (prop, old_v))
        return block[:m.start()] + m.group(1) + new_v + block[m.end():]
    prow = pset(prow, "DestTarget", '"StartToDestDirection"', '"MainActor"')
    # v8 (11-15 18:40): on the muzzle socket (v6) the shots tracked the gun and did damage, but always flew ~90 deg to
    # the right of the reticle whichever way EVE faced -> the socket's +X is sideways to the barrel. Keep the socket
    # and put the destination on its -Y axis (90 deg to the left of +X).
    prow = pset(prow, "DestTargetTransformType", '"ESBTargetLocationTransformType_Base"', '"ESBTargetLocationTransformType_Socket"')
    prow = pset(prow, "DestTargetTransformName", 'null', '"SC_GunShoot"')
    prow = pset(prow, "DestTargetRelativeAxisType", '"MovementTargetRelativeAxisType_RootAxis"', '"MovementTargetRelativeAxisType_ParentAxis"')
    # DestTargetRelativeLocation is empty in this row (no FVector inside): replace the whole property object with the
    # drone shotgun's VectorPropertyData shape (P_Eve_Gun_ShootScatterSlug1_Projectile1) carrying X = 50000.
    # v9 (11-15 18:50): +X was too far right, -Y too far left -> try 45 deg between them.
    # v10 (11-15 19:15): 45 deg landed a little high and left of the reticle -> 35 deg and a small -Z tilt (~4.6 deg).
    # v11 (11-15 19:30): 35 deg + Z -4000 landed high and RIGHT (45 deg was high and left) -> 40 deg, stronger down tilt.
    # v12 (11-15 19:43): 40 deg / Z -10000 landed low and LEFT, close -> split both brackets: 37.5 deg, Z -7000.
    # v13 (11-15 19:50): 37.5 deg / Z -7000 "just a little bit high", left-right good -> Z -8500.
    # v14 (11-15 20:02): Z -8500 "a hair too low" (-7000 was a little high) -> Z -8000.
    DEST_X, DEST_Y, DEST_Z = "39668.0", "-30438.0", "-8000.0"
    def obj_span(t, inside):
        st = t.rindex('{', 0, t.rindex('"$type"', 0, inside))
        d, instr, esc = 0, False, False
        for j in range(st, len(t)):
            c = t[j]
            if instr:
                if esc: esc = False
                elif c == '\\': esc = True
                elif c == '"': instr = False
            elif c == '"': instr = True
            elif c == '{': d += 1
            elif c == '}':
                d -= 1
                if d == 0: return st, j + 1
    k = prow.index('"Name": "DestTargetRelativeLocation"')
    os_, oe = obj_span(prow, k)
    P("old DestTargetRelativeLocation: " + re.sub(r"\s+", " ", prow[os_:oe])[:400])
    vec = ('{"$type": "UAssetAPI.PropertyTypes.Structs.VectorPropertyData, UAssetAPI", "Name": "DestTargetRelativeLocation", '
           '"ArrayIndex": 0, "PropertyGuid": null, "IsZero": false, "PropertyTagFlags": "None", "PropertyTypeName": null, '
           '"PropertyTagExtensions": "NoExtension", "Value": {"$type": "UAssetAPI.UnrealTypes.FVector, UAssetAPI", '
           f'"X": {DEST_X}, "Y": {DEST_Y}, "Z": {DEST_Z}}}}}')
    obj = prow[os_:oe]
    if '"Value": []' not in obj: raise Exception("DestTargetRelativeLocation: expected an empty struct Value")
    obj = obj.replace('"Value": []', '"Value": [' + vec + ']', 1).replace('"IsZero": true', '"IsZero": false', 1)
    prow = prow[:os_] + obj + prow[oe:]
    P("ProjectileTable: Dest = MainActor socket SC_GunShoot, ParentAxis, relative (%s, %s, %s)" % (DEST_X, DEST_Y, DEST_Z))
    pt = pt[:ps] + prow + pt[pe:]
    for nmv in ("MovementTargetRelativeAxisType_ParentAxis", "ESBTargetLocationTransformType_Socket", "SC_GunShoot", "MainActor"):
        if '"%s"' % nmv not in pt[pt.index('"NameMap"'):pt.index(']', pt.index('"NameMap"'))]:
            i = pt.index('"NameMap": [') + len('"NameMap": [')
            nl = "\r\n" if "\r\n" in pt[:2000] else "\n"
            pt = pt[:i] + nl + '    "%s",' % nmv + pt[i:]
            P("ProjectileTable NameMap += " + nmv)
    wj3 = os.path.join(work, "ProjectileTable.json")
    open(wj3, "w", encoding="utf-8", newline="").write(pt)
    dst3 = os.path.join(data, "ProjectileTable.uasset")
    r = subprocess.run([UAG, "fromjson", wj3, dst3, "StellarBlade"], capture_output=True, text=True, timeout=1800, creationflags=0x08000000)
    P("ProjectileTable: fromjson exists=%s %s" % (os.path.exists(dst3), (r.stdout + r.stderr).strip()[-300:]))
    if not os.path.exists(dst3): raise Exception("fromjson projectile failed")
    # --- v11 (11-16): brighter NIKKE guide laser. NS_A_GuideLaser has no width/colour user param (width is baked into
    # the compiled VM), so boost the emitters' "Scale Color" curves: their cooked ShaderLUT is RGBA per sample (all 1.0
    # = white); multiplying RGB by LASER_GAIN makes the beam HDR-bright (bloom) without touching shape or alpha.
    LASER_GAIN = 6.0
    lj = json.loads(open(os.path.join(B, "json", "NS_A_GuideLaser.json"), encoding="utf-8-sig").read())
    nlut = 0
    for e in lj["Exports"]:
        if not e.get("ObjectName", "").startswith("NiagaraDataInterfaceColorCurve"): continue
        for prop in e.get("Data", []):
            if prop.get("Name") != "ShaderLUT": continue
            for k, it in enumerate(prop["Value"]):
                if k % 4 != 3:
                    it["Value"] = float(it["Value"]) * LASER_GAIN
                    nlut += 1
    P("laser: %d colour LUT entries x%.1f" % (nlut, LASER_GAIN))
    if nlut == 0: raise Exception("laser LUT not found")
    fx = os.path.join(stage, r"SB\Content\DLC_2\Art\FX\Minigame"); os.makedirs(fx)
    wj4 = os.path.join(work, "NS_A_GuideLaser.json")
    open(wj4, "w", encoding="utf-8").write(json.dumps(lj, indent=2))
    dst4 = os.path.join(fx, "NS_A_GuideLaser.uasset")
    r = subprocess.run([UAG, "fromjson", wj4, dst4, "StellarBlade"], capture_output=True, text=True, timeout=900, creationflags=0x08000000)
    P("laser: fromjson exists=%s %s" % (os.path.exists(dst4), (r.stdout + r.stderr).strip()[-300:]))
    if not os.path.exists(dst4): raise Exception("fromjson laser failed")
    r = subprocess.run([RETOC, "to-zen", stage, os.path.join(out, NAME + ".utoc"), "--version", "UE4_26"], capture_output=True, text=True, timeout=900, creationflags=0x08000000)
    P("retoc: " + (r.stdout + r.stderr).strip()[-400:])
    for f in sorted(os.listdir(out)):
        shutil.copyfile(os.path.join(out, f), os.path.join(MODS, f))
        P("installed %s %d" % (f, os.path.getsize(os.path.join(MODS, f))))
    P("BUILD OK")
except Exception:
    import traceback; P("ERROR " + traceback.format_exc())
P("FINISHED")
rep.close()
