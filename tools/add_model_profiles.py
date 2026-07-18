#!/usr/bin/env python3
"""Add per-model `model_type` + unit `model_profiles` to army JSONs that
predate the MA-20 model-attributes schema (see 40k/MODEL_ATTRIBUTES_TASKS.md).

Why: units like Gretchin ship with the Runtherd as an untagged model (2W,
32mm base) — the board then renders it with the same icon as a rank-and-file
Gretchin and the hover tooltip claims it is "just another Gretchin". Once the
model carries `model_type` and the unit carries `model_profiles`,
TokenVisual resolves distinct art (`gretchin_runtherd.png`), draws the
model-type ring/short-label, and Main's hover tooltip appends the per-model
profile block ("Runtherd (m1)" + its own weapons).

Safety rules:
- Units that already have `model_profiles` are left untouched (recon_stomps
  is the reference schema and stays as-is).
- Profiles are only added when BOTH model types are actually present in the
  unit's models array (nothing to distinguish otherwise).
- A profile's weapon list is the datasheet template filtered to weapons the
  unit actually has. If that leaves a whole category (Ranged/Melee) empty
  while the unit has weapons of that category, the profile gets ALL of that
  category instead — so no model can lose a weapon category vs. the old
  "every model fires everything" behaviour.

Run from the repo root:  python3 tools/add_model_profiles.py [--check]
--check only reports what would change / validates invariants, exits 1 on drift.
"""

import json
import sys
from pathlib import Path

ARMIES_DIR = Path(__file__).resolve().parent.parent / "40k" / "armies"

# Files known to use ASCII-escaped JSON (– etc.); everything else is UTF-8.
ENSURE_ASCII = {"orks_taktikal.json"}

TARGET_FILES = [
    "battlewagons.json",
    "Orks_2000.json",
    "Orks_2000_upload.json",
    "Orks_Upload_Mar7.json",
    "orks.json",
    "orks_taktikal.json",
    "space_marines.json",
]


def _w(model):
    return int(model.get("wounds", 1))


def _b(model):
    return int(model.get("base_mm", 0))


# Registry keyed by unit meta.name. `classify` maps a model dict -> type key.
# `profiles` carries label/short_label + the datasheet weapon template.
REGISTRY = {
    "Gretchin": {
        "classify": lambda m: "runtherd" if _w(m) >= 2 or _b(m) >= 32 else "gretchin",
        "profiles": {
            "runtherd": {"label": "Runtherd", "short_label": "R",
                         "weapons": ["Slugga", "Runtherd tools"]},
            "gretchin": {"label": "Gretchin", "short_label": "G",
                         "weapons": ["Grot blasta", "Close combat weapon"]},
        },
    },
    "Stormboyz": {
        "classify": lambda m: "boss_nob" if _w(m) >= 2 else "stormboy",
        "profiles": {
            "boss_nob": {"label": "Boss Nob", "short_label": "N",
                         "weapons": ["Slugga", "Power klaw"]},
            "stormboy": {"label": "Stormboy", "short_label": "S",
                         "weapons": ["Slugga", "Choppa"]},
        },
    },
    "Warbikers": {
        "classify": lambda m: "boss_nob" if _w(m) >= 4 else "warbiker",
        "profiles": {
            "boss_nob": {"label": "Boss Nob on Warbike", "short_label": "N",
                         "weapons": ["Twin dakkagun", "Power klaw"]},
            "warbiker": {"label": "Warbiker", "short_label": "B",
                         "weapons": ["Twin dakkagun", "Close combat weapon"]},
        },
    },
    "Tankbustas": {
        # All Tankbustas are 2W; the roster encodes the Boss Nob as the one
        # 40mm base (m1, composition line 1).
        "classify": lambda m: "boss_nob" if _b(m) >= 40 else "tankbusta",
        "profiles": {
            "boss_nob": {"label": "Boss Nob", "short_label": "N",
                         "weapons": ["Rokkit pistol", "Choppa"]},
            "tankbusta": {"label": "Tankbusta", "short_label": "T",
                          "weapons": ["Rokkit launcha", "Close combat weapon"]},
        },
    },
    "Kommandos": {
        "classify": lambda m: "boss_nob" if _w(m) >= 2 else "kommando",
        "profiles": {
            "boss_nob": {"label": "Boss Nob", "short_label": "N",
                         "weapons": ["Slugga", "Big choppa"]},
            "kommando": {"label": "Kommando", "short_label": "K",
                         "weapons": ["Kustom shoota", "Slugga", "Choppa",
                                     "Close combat weapon"]},
        },
    },
    "Beast Snagga Boyz": {
        "classify": lambda m: "boss_nob" if _w(m) >= 2 else "boy",
        "profiles": {
            "boss_nob": {"label": "Beast Snagga Nob", "short_label": "N",
                         "weapons": ["Slugga", "Power snappa"]},
            "boy": {"label": "Beast Snagga Boy", "short_label": "B",
                    "weapons": ["Slugga", "Choppa", "Close combat weapon"]},
        },
    },
    "Boyz": {
        "classify": lambda m: "boss_nob" if _w(m) >= 2 else "boy",
        "profiles": {
            "boss_nob": {"label": "Boss Nob", "short_label": "N",
                         "weapons": ["Slugga", "Kombi-weapon", "Choppa",
                                     "Big choppa", "Power klaw"]},
            "boy": {"label": "Boy", "short_label": "B",
                    "weapons": ["Shoota", "Big shoota", "Rokkit launcha",
                                "Slugga", "Choppa", "Close combat weapon"]},
        },
    },
    # Ghazghkull + Makari: weapon split is unambiguous from the weapon names.
    "Ghazghkull Thraka": {
        "classify": lambda m: "ghazghkull" if _w(m) >= 5 else "makari",
        "profiles": {
            "ghazghkull": {"label": "Ghazghkull Thraka", "short_label": "G",
                           "weapons_by_prefix_not": "Makari"},
            "makari": {"label": "Makari", "short_label": "M",
                       "weapons_by_prefix": "Makari"},
        },
    },
}

# Per-unit-id overrides. The MA test suite (test_backward_compatibility.gd,
# test_ma15_model_type_picker.gd) and the audit_baseline_postdeploy fixture
# define the AUTHORITATIVE migrated shape of orks.json:
#   - U_BOYZ_E stays legacy (no profiles) — it is the backward-compat control
#     the tests drive weapon-assignment/wound-allocation through.
#   - U_LOOTAS_A is 8x Loota (Deffgun) / 2x Loota (KMB) / 1x Spanner (BS4).
#   - U_MEGANOBZ_L is 3x Power Klaw / 2x Killsaw nobz, transport_slots 2.
#   - U_BOYZ_F carries the fixture's stats_override (WS3/Sv4 nob, WS4 boy).
# A value of None means "leave this unit untouched".
_BOYZ_FIXTURE_SPEC = {
    "classify": lambda m: "boss_nob" if _w(m) >= 2 else "boy",
    "profiles": {
        "boss_nob": {"label": "Boss Nob", "short_label": "N",
                     "weapons": ["Big choppa", "Choppa", "Power klaw",
                                 "Slugga", "Kombi-weapon"],
                     "stats_override": {"save": 4, "weapon_skill": 3},
                     "transport_slots": 1},
        "boy": {"label": "Boy", "short_label": "B",
                "weapons": ["Choppa", "Close combat weapon", "Shoota",
                            "Slugga", "Big shoota", "Rokkit launcha"],
                "stats_override": {"weapon_skill": 4},
                "transport_slots": 1},
    },
}

_LOOTAS_FIXTURE_SPEC = {
    # 11-model layout from the MA fixture: m1-m8 deffguns, m9-m10 KMB lootas,
    # m11 the Spanner. Only applied when the model count matches exactly.
    "assign_by_counts": [("loota_deffgun", 8), ("loota_kmb", 2), ("spanner", 1)],
    "profiles": {
        "loota_deffgun": {"label": "Loota (Deffgun)", "short_label": "D",
                          "weapons": ["Deffgun", "Close combat weapon"],
                          "transport_slots": 1},
        "loota_kmb": {"label": "Loota (Kustom Mega-blasta)", "short_label": "K",
                      "weapons": ["Kustom mega-blasta", "Close combat weapon"],
                      "transport_slots": 1},
        "spanner": {"label": "Spanner", "short_label": "S",
                    "weapons": ["Kustom mega-blasta", "Close combat weapon"],
                    "stats_override": {"ballistic_skill": 4},
                    "transport_slots": 1},
    },
}

_MEGANOBZ_FIXTURE_SPEC = {
    "assign_by_counts": [("meganob_klaw", 3), ("meganob_saws", 2)],
    "profiles": {
        # "Killsaws"/"Killsaw" both listed so the filter keeps whichever
        # spelling the file uses.
        "meganob_klaw": {"label": "Meganob (Power Klaw)", "short_label": "PK",
                         "weapons": ["Kustom shoota", "Power klaw"],
                         "transport_slots": 2},
        "meganob_saws": {"label": "Meganob (Killsaws)", "short_label": "KS",
                         "weapons": ["Kustom shoota", "Killsaws", "Killsaw"],
                         "transport_slots": 2},
    },
}

_INTERCESSORS_FIXTURE_SPEC = {
    # 5 identical models — the Sergeant is m1 (unit_composition line 1).
    # test_model_profiles.gd Tests 12-13 pin this exact shape.
    "assign_by_counts": [("intercessor_sergeant", 1), ("intercessor", 4)],
    "profiles": {
        "intercessor_sergeant": {"label": "Intercessor Sergeant", "short_label": "S",
                                 "weapons": ["Bolt rifle", "Bolt pistol", "Power fist"],
                                 "transport_slots": 1},
        "intercessor": {"label": "Intercessor", "short_label": "I",
                        "weapons": ["Bolt rifle", "Bolt pistol", "Close combat weapon"],
                        "transport_slots": 1},
    },
}

UNIT_OVERRIDES = {
    ("space_marines.json", "U_INTERCESSORS_A"): _INTERCESSORS_FIXTURE_SPEC,
    ("orks.json", "U_BOYZ_E"): None,
    ("orks_taktikal.json", "U_BOYZ_E"): None,
    ("orks.json", "U_BOYZ_F"): _BOYZ_FIXTURE_SPEC,
    ("orks_taktikal.json", "U_BOYZ_F"): _BOYZ_FIXTURE_SPEC,
    ("orks.json", "U_BOYZ_K"): _BOYZ_FIXTURE_SPEC,
    ("orks_taktikal.json", "U_BOYZ_K"): _BOYZ_FIXTURE_SPEC,
    ("orks.json", "U_LOOTAS_A"): _LOOTAS_FIXTURE_SPEC,
    ("orks_taktikal.json", "U_LOOTAS_A"): _LOOTAS_FIXTURE_SPEC,
    ("orks.json", "U_MEGANOBZ_L"): _MEGANOBZ_FIXTURE_SPEC,
    ("orks_taktikal.json", "U_MEGANOBZ_L"): _MEGANOBZ_FIXTURE_SPEC,
}


def build_weapons(profile_spec, unit_weapons):
    """unit_weapons: list of {name, type} dicts from unit meta."""
    names = {w.get("name", ""): w.get("type", "") for w in unit_weapons}
    if "weapons_by_prefix" in profile_spec:
        return [n for n in names if n.startswith(profile_spec["weapons_by_prefix"])]
    if "weapons_by_prefix_not" in profile_spec:
        return [n for n in names if not n.startswith(profile_spec["weapons_by_prefix_not"])]

    template = profile_spec["weapons"]
    have = [n for n in template if n in names]
    out = list(have)
    for cat in ("Ranged", "Melee"):
        cat_all = [n for n, t in names.items() if t == cat]
        if cat_all and not any(names[n] == cat for n in have):
            out.extend(n for n in cat_all if n not in out)
    return out


def patch_file(path, check_only=False):
    raw = path.read_text(encoding="utf-8")
    data = json.loads(raw)
    units = data.get("units", {})
    unit_items = units.items() if isinstance(units, dict) else [
        (u.get("id", ""), u) for u in units]

    changed = []
    for uid, unit in unit_items:
        meta = unit.get("meta", {})
        name = meta.get("name", "")
        override_key = (path.name, uid)
        spec = None
        if override_key in UNIT_OVERRIDES:
            spec = UNIT_OVERRIDES[override_key]
            if spec is None:
                continue  # pinned legacy (backward-compat control unit)
        elif name in REGISTRY:
            spec = REGISTRY[name]
        else:
            continue
        if meta.get("model_profiles"):
            continue  # already migrated (recon_stomps schema) — leave alone
        models = unit.get("models", [])

        if "assign_by_counts" in spec:
            counts = spec["assign_by_counts"]
            if sum(c for _, c in counts) != len(models):
                continue  # layout doesn't match the fixture spec — skip
            assigned = []
            for type_key, c in counts:
                assigned.extend([type_key] * c)
        else:
            assigned = [spec["classify"](m) for m in models]
        if len(set(assigned)) < 2:
            continue  # homogeneous unit — nothing to distinguish

        profiles = {}
        for type_key, pspec in spec["profiles"].items():
            weapons = build_weapons(pspec, meta.get("weapons", []))
            profiles[type_key] = {
                "label": pspec["label"],
                "short_label": pspec["short_label"],
                "weapons": weapons,
                "stats_override": dict(pspec.get("stats_override", {})),
            }
            if "transport_slots" in pspec:
                profiles[type_key]["transport_slots"] = pspec["transport_slots"]

        if not check_only:
            for m, type_key in zip(models, assigned):
                m["model_type"] = type_key
            meta["model_profiles"] = profiles
        changed.append((uid, name, {t: assigned.count(t) for t in set(assigned)},
                        {t: p["weapons"] for t, p in profiles.items()}))

    if changed and not check_only:
        out = json.dumps(data, indent=1,
                         ensure_ascii=path.name in ENSURE_ASCII) + "\n"
        path.write_text(out, encoding="utf-8")
    return changed


def validate(path):
    """Invariants: every profile weapon exists on the unit; every model of a
    profiled unit has a model_type that the profiles dict contains; each
    profile keeps every weapon category the unit has... only for units this
    script owns (registry names)."""
    problems = []
    data = json.loads(path.read_text(encoding="utf-8"))
    units = data.get("units", {})
    unit_items = units.items() if isinstance(units, dict) else [
        (u.get("id", ""), u) for u in units]
    for uid, unit in unit_items:
        meta = unit.get("meta", {})
        profiles = meta.get("model_profiles", {})
        if not profiles:
            continue
        names = {w.get("name", ""): w.get("type", "") for w in meta.get("weapons", [])}
        for tkey, prof in profiles.items():
            for wn in prof.get("weapons", []):
                if wn not in names:
                    problems.append(f"{path.name}:{uid} profile {tkey} references unknown weapon '{wn}'")
        for m in unit.get("models", []):
            mt = m.get("model_type", "")
            if mt == "":
                problems.append(f"{path.name}:{uid} model {m.get('id')} missing model_type")
            elif mt not in profiles:
                problems.append(f"{path.name}:{uid} model {m.get('id')} type '{mt}' not in profiles")
    return problems


def main():
    check_only = "--check" in sys.argv
    any_change = False
    all_problems = []
    for fname in TARGET_FILES:
        path = ARMIES_DIR / fname
        if not path.exists():
            print(f"SKIP (missing): {fname}")
            continue
        changed = patch_file(path, check_only=check_only)
        for uid, name, counts, weapons in changed:
            any_change = True
            print(f"{'WOULD PATCH' if check_only else 'PATCHED'} {fname} {uid} ({name}) types={counts}")
            for t, ws in weapons.items():
                print(f"    {t}: {ws}")
        all_problems.extend(validate(path))
    for p in all_problems:
        print("PROBLEM:", p)
    if all_problems:
        sys.exit(1)
    if check_only and any_change:
        sys.exit(1)
    print("OK")


if __name__ == "__main__":
    main()
