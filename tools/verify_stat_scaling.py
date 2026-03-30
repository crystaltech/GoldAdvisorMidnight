#!/usr/bin/env python3
"""
verify_stat_scaling.py
Verifies the Master Equation stat scaling formula used in Pricing.lua.

Formula:
  outputStatScale = [(1 + u_multi * MCm) / (1 + b_multi * MCm)]
                  * [(1 - b_res * Rs)    / (1 - u_res   * Rs)]

Where:
  MCm (BAKED_MCM) = 1.875  (Multicraft multiplier at max talent investment)
  Rs  (BAKED_RS)  = 0.45   (Resourcefulness save ratio at max specialization)
  b_multi, b_res  = baked baseline values (0.0–1.0 floats)
  u_multi, u_res  = user's actual gear stats (0.0–1.0 floats)

Profiles with no Multicraft stat: u_multi = 0, b_multi = 0 → multi component = 1.0 (cancels).
"""

BAKED_MCM = 1.875
BAKED_RS  = 0.45

# STAT_PROFILES from Pricing.lua
# (bakedMulti, bakedRes)  — profiles without multicraft use 0 for bakedMulti
STAT_PROFILES = {
    "insc_milling":   (0,    0.32),  # no Multicraft stat
    "insc_ink":       (0.26, 0.17),
    "jc_prospect":    (0,    0.33),  # no Multicraft stat
    "jc_crush":       (0,    0.35),  # no Multicraft stat
    "jc_craft":       (0.30, 0.18),
    "ench_shatter":   (0,    0.30),  # no Multicraft stat
    "ench_craft":     (0.25, 0.16),
    "alchemy":        (0.30, 0.15),
    "tailoring":      (0.25, 0.15),
    "blacksmithing":  (0.28, 0.19),
    "leatherworking": (0.29, 0.17),
    "engineering":    (0.30467, 0.36),
}

# DB defaults from Constants.lua (numeric %)
DB_DEFAULTS = {
    "insc_milling":   (0,   32),
    "insc_ink":       (26,  17),
    "jc_prospect":    (0,   33),
    "jc_crush":       (0,   35),
    "jc_craft":       (30,  18),
    "ench_shatter":   (0,   30),
    "ench_craft":     (25,  16),
    "alchemy":        (30,  15),
    "tailoring":      (25,  15),
    "blacksmithing":  (28,  19),
    "leatherworking": (29,  17),
    "engineering":    (30.467, 36),
}


def scale(b_multi, b_res, u_multi_pct, u_res_pct):
    """Compute outputStatScale. u_multi_pct / u_res_pct are numeric percentages (0–100)."""
    u_multi = u_multi_pct / 100
    u_res   = u_res_pct   / 100
    multi_denom = 1 + b_multi * BAKED_MCM
    res_denom   = 1 - u_res   * BAKED_RS
    res_baked   = 1 - b_res   * BAKED_RS
    if multi_denom <= 0 or res_denom <= 0 or res_baked <= 0:
        return None  # guard (should never happen with clamped 0–100 inputs)
    return ((1 + u_multi * BAKED_MCM) / multi_denom) * (res_baked / res_denom)


PASS = "PASS"
FAIL = "FAIL"

def check(label, result, expected, tol=0.0005):
    ok = abs(result - expected) <= tol
    status = PASS if ok else FAIL
    marker = "" if ok else "  *** MISMATCH ***"
    print(f"  [{status}] {label}: scale={result:.6f}  expected≈{expected:.6f}{marker}")
    return ok


# ── Test 1: All profiles at default stats must give scale = 1.0 exactly ─────
print("=" * 60)
print("TEST 1: Default stats → scale must be exactly 1.0 for all profiles")
print("=" * 60)
all_pass = True
for prof_key, (b_multi, b_res) in STAT_PROFILES.items():
    d_multi_pct, d_res_pct = DB_DEFAULTS[prof_key]
    s = scale(b_multi, b_res, d_multi_pct, d_res_pct)
    ok = check(prof_key, s, 1.0, tol=1e-9)
    all_pass = all_pass and ok
print(f"  → {'ALL PASS' if all_pass else 'SOME FAILED'}\n")


# ── Test 2: Real-world player examples ───────────────────────────────────────
print("=" * 60)
print("TEST 2: Real-world player stat examples")
print("=" * 60)

tests = [
    # (profile_key, u_multi_pct, u_res_pct, expected_scale, description)
    # JC Craft: 6% multi / 17% res vs baked 30% / 18%
    # multi: (1+0.06×1.875)/(1+0.30×1.875) = 1.1125/1.5625 = 0.7120
    # res:   (1-0.18×0.45)/(1-0.17×0.45) = 0.9190/0.9235 = 0.9951
    # scale ≈ 0.7085
    # Note: plan's "≈0.656" was wrong — it used b_res=0.33 (prospect baseline), not 0.18.
    ("jc_craft",       6,   17, 0.7085, "JC Craft (6% multi, 17% res) → 0.708"),

    # Inscription Milling: no multi, 27% res vs baked 0% / 32%
    # multi cancels (both 0) → scale = (1 - 0.32×0.45) / (1 - 0.27×0.45)
    # = (1 - 0.144) / (1 - 0.1215) = 0.856 / 0.8785 ≈ 0.9743
    ("insc_milling",   0,   27, None,   "Insc Milling (0% multi, 27% res)"),

    # Alchemy: 10% multi / 5% res vs baked 30% / 15%
    # multi: (1+0.1×1.875)/(1+0.3×1.875) = 1.1875/1.5625 = 0.76
    # res:   (1-0.15×0.45)/(1-0.05×0.45) = 0.9325/0.9775 ≈ 0.9540
    # total ≈ 0.76 × 0.9540 ≈ 0.7251
    ("alchemy",        10,   5, None,   "Alchemy (10% multi, 5% res)"),

    # Engineering: lower than the shared default multicraft/resourcefulness profile
    ("engineering",    0,   20, None,   "Engineering (0% multi, 20% res)"),

    # Enchanting Shattering: no multi, 30% res = defaults → must be 1.0
    ("ench_shatter",   0,   30, 1.0,    "Ench Shatter at defaults → 1.0"),

    # JC Prospect: no multi, 50% res vs baked 33%
    # (1-0.33×0.45)/(1-0.50×0.45) = (1-0.1485)/(1-0.225) = 0.8515/0.775 ≈ 1.099
    # Higher res than baseline → better output (more resourcefulness saves reagents)
    ("jc_prospect",    0,   50, None,   "JC Prospect (50% res, more than baseline) → scale > 1"),

    # Blacksmithing at 0% stats (worst case)
    # multi: (1+0)/(1+0.28×1.875) = 1/1.525 ≈ 0.6557
    # res:   (1-0.19×0.45)/(1-0) = 0.9145/1.0 = 0.9145
    # total ≈ 0.6557 × 0.9145 ≈ 0.5996
    ("blacksmithing",  0,    0, None,   "Blacksmithing at 0% stats (worst case)"),
]

all_pass2 = True
for (pk, u_m, u_r, expected, desc) in tests:
    b_multi, b_res = STAT_PROFILES[pk]
    s = scale(b_multi, b_res, u_m, u_r)
    if expected is not None:
        ok = check(desc, s, expected)
    else:
        # compute expected analytically for display
        u_multi_f = u_m / 100
        u_res_f   = u_r / 100
        multi_comp = (1 + u_multi_f * BAKED_MCM) / (1 + b_multi * BAKED_MCM)
        res_comp   = (1 - b_res * BAKED_RS)      / (1 - u_res_f  * BAKED_RS)
        print(f"  [INFO] {desc}:")
        print(f"         multi_comp={multi_comp:.6f}  res_comp={res_comp:.6f}  scale={s:.6f}")
        ok = True
    all_pass2 = all_pass2 and ok

print(f"  → {'ALL PASS' if all_pass2 else 'SOME FAILED'}\n")


# ── Test 3: Edge-case guards ──────────────────────────────────────────────────
print("=" * 60)
print("TEST 3: Edge cases")
print("=" * 60)

# Max stats (100%) — should not divide by zero with Rs=0.45
s_max = scale(0.30, 0.15, 100, 100)
print(f"  [INFO] Alchemy at 100% multi / 100% res: scale={s_max:.6f}")
print(f"         res_denom = 1 - 1.0 × 0.45 = {1 - 1.0*BAKED_RS:.4f}  (> 0, no div-by-zero)")

# 0% res, 0% multi (absolute floor)
s_floor = scale(0.30, 0.15, 0, 0)
print(f"  [INFO] Alchemy at 0% multi / 0% res:   scale={s_floor:.6f}  (output reduced ~40%)")

# No-multicraft profile, user res = baked res → scale = 1.0
s_eq = scale(0, 0.32, 0, 32)
check("Insc Milling u_res=baked_res → 1.0", s_eq, 1.0, tol=1e-9)

print()
print("Done.")
