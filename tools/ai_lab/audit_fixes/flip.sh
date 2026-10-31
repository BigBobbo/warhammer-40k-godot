#!/usr/bin/env bash
# flip.sh - V2-4 rules-audit bundle: turn ON the named FIX_<NAME> consts
# (0.0 -> 1.0) in 40k/scripts/AIDecisionMaker.gd, then verify each reads 1.0.
# Usage (repo root): bash tools/ai_lab/audit_fixes/flip.sh [PARAM ...]
#   no arguments  = the 11 fixes that passed the V2-1 fix gate (bench arm AUD)
#   --all         = all 13 rules-audit fixes
# Exit 0 = every named const reads 1.0; exit 1 otherwise. Never commit the result.
set -u

F="40k/scripts/AIDecisionMaker.gd"
GATE_PASSED=(
  FIX_OBJ_AREA_REACH
  FIX_OBJ_AREA_ON_OBJ
  FIX_OBJ_AREA_HOLD
  FIX_EOG_TIMING
  FIX_MOVE_TERRAIN_11E
  FIX_CHARGE_OW_11E
  FIX_HI_CHARGE_ODDS
  FIX_CHARGE_REROLL_ODDS
  FIX_PILEIN_TARGETS_11E
  FIX_ADV_ENGINE_PREDICATES
  FIX_WAAAGH_ADV_REROLL
)
PARKED=(
  FIX_SECURED_AWARE
  FIX_CO_NEXT_PICK
)

if [ "$#" -eq 0 ]; then
  PARAMS=("${GATE_PASSED[@]}")
elif [ "$1" = "--all" ]; then
  PARAMS=("${GATE_PASSED[@]}" "${PARKED[@]}")
else
  PARAMS=("$@")
fi

if [ ! -f "$F" ]; then
  echo "flip.sh: $F not found - run from the repo root" >&2
  exit 1
fi

for p in "${PARAMS[@]}"; do
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
echo "flip.sh: ${#PARAMS[@]} FIX_ consts read 1.0"
exit 0
