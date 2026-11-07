extends RefCounted
## ShockDisembark11e — the "shock disembark move" (11e codex datasheets).
##
## The 11e core rules (docs/rules/40k_11th_edition_core_rules.txt, 18.04) define
## no shock disembark move. The project rules it as the RAPID disembark mode
## (3" set-up; not eligible to declare a charge until the end of the turn) with
## 18.04's "the TRANSPORT has not made an advance move this phase" bar lifted
## (RULINGS.md WP-M4b Rapid Disembarkation, WP-G2 Assault Vehicle).
##
## Grants (each a codex module answers for its own datasheets):
##   Codex: Space Marines   Impulsor            RAPID DISEMBARKATION (SMAbilitiesB, WP-M4b)
##   Codex: Adeptus Custodes Coronus Grav-Carrier / Anathema Psykana Rhino
##                                              ASSAULT VEHICLE (CustodesAbilities, WP-G2)
##
## The engine asks this file only (TransportManager.can_disembark,
## DisembarkMove.eligible / select_mode, DisembarkDialog) — one hook per site.
## Loaded at call time: the codex modules reach autoloads late-bound and the
## move-type templates compile before autoloads exist in `--script` runs.

const SM_ABILITIES_B := "res://scripts/codex/space_marines/SMAbilitiesB.gd"
const CUS_ABILITIES := "res://scripts/codex/custodes/CustodesAbilities.gd"


## True when the units embarked in `transport` can make a shock disembark move
## now (its advance move has ended this Movement phase and a datasheet grants it).
static func transport_allows(transport: Dictionary) -> bool:
	return source(transport) != ""


## The granting ability's name ("Rapid Disembarkation" / "Assault Vehicle"), or "".
static func source(transport: Dictionary) -> String:
	if int(GameConstants.edition) < 11 or transport.is_empty():
		return ""
	if load(SM_ABILITIES_B).transport_allows_shock_disembark(transport):
		return "Rapid Disembarkation"
	if load(CUS_ABILITIES).transport_allows_shock_disembark(transport):
		return "Assault Vehicle"
	return ""
