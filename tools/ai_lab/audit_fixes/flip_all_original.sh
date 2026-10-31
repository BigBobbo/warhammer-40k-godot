#!/usr/bin/env bash
# flip.sh - V2-4 rules-audit bundle: turn ON every new FIX_<NAME> const
# (0.0 -> 1.0) in 40k/scripts/AIDecisionMaker.gd, then verify each reads 1.0.
# Run from the repo root, on a tree that has bundle.patch applied.
# Exit 0 = all 13 consts read 1.0; exit 1 otherwise.
set -u

F="40k/scripts/AIDecisionMaker.gd"
PARAMS=(
  FIX_OBJ_AREA_REACH
  FIX_OBJ_AREA_ON_OBJ
  FIX_OBJ_AREA_HOLD
  FIX_EOG_TIMING
  FIX_MOVE_TERRAIN_11E
  FIX_SECURED_AWARE
  FIX_CHARGE_OW_11E
  FIX_HI_CHARGE_ODDS
  FIX_CHARGE_REROLL_ODDS
  FIX_CO_NEXT_PICK
  FIX_PILEIN_TARGETS_11E
  FIX_ADV_ENGINE_PREDICATES
  FIX_WAAAGH_ADV_REROLL
)

if [ ! -f "$F" ]; then
  echo "flip.sh: $F not found - run from the repo root" >&2
  exit 1
fi

for p in "${PARAMS[@]}"; do
  # -i.bak + rm: works with GNU and BSD sed
  sed -i.bak -E "s/^const ${p}: float = [0-9.]+$/const ${p}: float = 1.0/" "$F" && rm -f "$F.bak"
done

fail=0
for p in "${PARAMS[@]}"; do
  n=$(grep -cE "^const ${p}: float = 1\.0$" "$F")
  if [ "$n" = "1" ]; then
    echo "flip.sh: OK   $p = 1.0"
  else
    echo "flip.sh: FAIL $p does not read 1.0 (matching lines: $n)" >&2
    grep -nE "^const ${p}:" "$F" >&2
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "flip.sh: all ${#PARAMS[@]} FIX_ consts read 1.0"
exit 0
