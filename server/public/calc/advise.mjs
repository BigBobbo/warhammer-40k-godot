// "Ask for a plan": what the Board sends to the server's /api/calc-advise (server/calc-advise.js), which passes
// it to Claude. Two parts, so the server can have the first cached for the whole game:
//   static  - both armies: each unit's keywords and ability text, the stratagems each side can use
//   dynamic - the game now: round, phase, CP, score, cards, where every unit is, and what the Board cards computed
// Pure module (no DOM): the Board gathers the data, this shapes it. Tests: tests/calc-advisepayload.test.mjs.

const pc = (v) => Math.round((v ?? 0) * 100);
const r2 = (v) => Math.round((v ?? 0) * 100) / 100;
const clean = (s, n) => String(s ?? '').replace(/\s+/g, ' ').trim().slice(0, n);

/** One army for the static part. units: [{ name, points, models, keywords, abilities: [{ name, text }] }] */
function armyPart(a, stratFilter = () => true) {
  return {
    faction: a.faction,
    units: a.units.map(u => ({ name: u.name, points: u.points ?? 0, models: u.models, keywords: (u.keywords ?? []).slice(0, 8), abilities: (u.abilities ?? []).slice(0, 6).map(x => `${x.name}: ${clean(x.text, 260)}`) })),
    stratagems: (a.stratagems ?? []).filter((s, i, all) => all.findIndex(x => x.name === s.name) === i).filter(stratFilter)
      .map(s => ({ name: s.name, cp: s.cp, phase: s.phase, turn: s.turn, when: clean(s.when, 220), target: clean(s.target, 200), effect: clean(s.effect, 420), ...(s.restrictions ? { restrictions: clean(s.restrictions, 200) } : {}) })),
  };
}

/**
 * in: { armies: { me, them } (as armyPart takes), game: { round, mine (is it my turn), phase, myMission, theirMission,
 *       myCP, theirCP, myVP, theirVP }, hands: { me: [{ name, text }], them }, unitsNow: { me: [{ name, modelsLeft,
 *       at: [x, y] | null, status? }], them }, res (nextturn.nextTurn), my (nextturn.myTurn),
 *       moves: { base: { win }, best: [...], kept: { moves, win } } | null (the forecast, when it has run) }
 * -> { static, dynamic }
 */
export function advisePayload(d) {
  const VERDICT = { theirs: 'they control it', lose: 'they can take it', contest: 'they can tie it', advance: 'they reach it only with an Advance', safe: 'yours unless its holders are destroyed', take: 'empty and they can take it', open: 'out of their reach' };
  const MINE = { theirs: 'you control it', lose: 'you can take it from them', contest: 'you can tie it', advance: 'you reach it only with an Advance', safe: 'theirs: you cannot take it by moving', take: 'empty and you can take it', open: 'out of your reach' };
  const mover = (m) => `${m.name} (OC ${m.oc}, ${m.via === 'advance' ? `Advance ${m.need}+` : 'normal move'})`;
  const mineBy = new Map((d.my?.swing ?? []).map(o => [o.id, o]));
  const now = (u) => ({ name: u.name, modelsLeft: u.modelsLeft, ...(u.at ? { at: [Math.round(u.at[0]), Math.round(u.at[1])] } : { status: u.status ?? 'not on the table' }) });
  const attackOf = (u) => {
    if (!u.attack) return {};
    const b = d.my.kills.find(k => k.key === u.attack.key)?.by.find(x => x.key === u.key);
    return { target: `${u.attack.how} ${u.attack.name}`, targetDestroyedPct: pc(u.attack.p), unitsSentAtIt: u.attack.with,
      ...(b ? { chargeOddsPct: b.engaged ? 'already in combat' : b.charge ? pc(b.charge) : null, canShootWithoutMoving: b.shoot ? !!b.shoot.now : null } : {}) };
  };
  const cards = (list) => (list ?? []).map(c => ({ card: c.name, verdict: c.verdict, vp: c.vp, ...(c.p != null ? { oddsPct: pc(c.p) } : {}), why: c.why }));
  const mv = d.moves;
  return {
    static: { me: armyPart(d.armies.me), them: armyPart(d.armies.them, (s) => /opponent|either/i.test(String(s.turn ?? ''))) },
    dynamic: {
      game: { round: d.game.round, turn: d.game.mine ? 'mine' : 'theirs', phase: d.game.phase, board: '44 x 60 inches; positions are [x across, y down]',
        myMission: d.game.myMission, theirMission: d.game.theirMission, myCP: d.game.myCP, theirCP: d.game.theirCP, myVP: d.game.myVP, theirVP: d.game.theirVP },
      myCards: (d.hands.me ?? []).map(c => ({ name: c.name, text: c.text })),
      theirCards: (d.hands.them ?? []).map(c => ({ name: c.name, text: c.text })),
      myUnits: d.unitsNow.me.map(now), theirUnits: d.unitsNow.them.map(now),
      computed: {
        note: 'Worked out by the app from positions, datasheets and dice maths. Kill odds are an upper bound (straight-line moves, every model attacking, no stratagems). A base in the terrain area an objective is in counts as in range of it.',
        objectives: d.res.swing.map(o => { const m = mineBy.get(o.id); return { name: o.label, myOC: o.mine, theirOC: o.theirs, inTheirTurn: VERDICT[o.verdict] ?? o.verdict, theirUnitsThatCanReachIt: o.movers.slice(0, 4).map(mover),
          ...(m ? { inMyTurn: MINE[m.verdict] ?? m.verdict, myUnitsThatCanReachIt: m.movers.slice(0, 4).map(mover) } : {}) }; }),
        myUnitsAtRiskInTheirTurn: d.res.threats.filter(t => t.by.length).map(t => ({ unit: t.name, likelyDestroyedPct: pc(t.likely), ifFocusedPct: pc(t.focus), by: t.by.slice(0, 4).map(b => b.name) })),
        theirCardsOutlook: cards(d.res.cards),
        myUnitSuggestions: d.my.units.map(u => ({ unit: u.name, job: u.job.kind === 'none' ? null : `${u.job.kind} ${u.job.label}`, ...attackOf(u), riskInTheirTurnPct: pc(u.risk) })),
        targets: d.my.kills.map(k => ({ target: k.name, points: k.points, destroyedPct: pc(k.p), by: k.by.map(b => b.name) })),
        myCardsOutlook: cards(d.my.cards),
        forecast: mv?.base ? { winPctAsItStands: pc(mv.base.win), note: 'the table as it stands counts for this battle round; later rounds are forecast from the mission plan',
          movesWorth3vpOrMore: (mv.best ?? []).map(b => ({ unit: b.name, move: `${r2(b.dist)}" ${b.kind === 'back' ? 'back towards home' : `onto ${b.label}`}`, vpGainAlone: r2(b.dVp), ...(b.riskThere != null ? { riskInTheirTurnAfterTheMovePct: pc(b.riskThere), riskWhereItStandsPct: pc(b.riskHere) } : {}) })),
          keptTogether: (mv.kept?.moves ?? []).map(b => `${b.name} -> ${b.kind === 'back' ? 'back towards home' : b.label}`), winPctWithThem: pc(mv.kept?.moves?.length ? mv.kept.win : mv.base.win) }
          : { note: 'the move forecast has not run' },
      },
    },
  };
}

/** How big the request is (the server refuses over 80,000 / 40,000 characters). */
export function payloadSize(p) { return { static: JSON.stringify(p.static).length, dynamic: JSON.stringify(p.dynamic).length }; }
