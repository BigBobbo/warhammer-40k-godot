#!/bin/bash
# WP-M2b: run the Codex: Space Marines (11e) group-B detachment / enhancement
# windowed scenarios (sm11e_det_* / sm11e_enh_* of SMDetachmentsB) in one
# batch, under the shared window lock, on the WP-M2b MCP port.
# Usage: bash 40k/tests/run_sm11e_m2b_scenarios.sh [scenario-id ...]
cd "$(dirname "$0")/.."
export PATH="$HOME/bin:$PATH"
export GODOT_MCP_PORT="${GODOT_MCP_PORT:-9882}"
IDS=("$@")
if [ ${#IDS[@]} -eq 0 ]; then
    IDS=(sm11e_det_death_blow sm11e_det_assault_mastery sm11e_det_walking_fortress sm11e_det_indomitable_defence
        sm11e_det_enduring_vengeance sm11e_det_codex_fire_patterns sm11e_enh_champion_first_company
        sm11e_enh_corporeum_reliquary sm11e_enh_furious_assault sm11e_enh_indefatigable_fortitude
        sm11e_enh_master_forged_firearms sm11e_enh_honour_of_vigilance sm11e_enh_narthecis_gauntlet
        sm11e_enh_laurels_of_vigilance sm11e_enh_tactical_insight sm11e_enh_artificer_sarcophagus
        sm11e_enh_tempered_in_battle sm11e_enh_immovable_conquerors)
fi
FILES=()
for id in "${IDS[@]}"; do
    FILES+=("tests/scenarios/sp/${id}.json")
done
exec flock /tmp/codex11e_godot_window.lock bash tests/run_scenarios.sh "${FILES[@]}"
