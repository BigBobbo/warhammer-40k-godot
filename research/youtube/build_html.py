#!/usr/bin/env python3
"""Render ai_learnings.json into a self-contained, filterable HTML page.

No external CSS, JS, fonts or images — everything is inlined so the file works
from disk with no network. Light and dark themes follow the OS by default with a
manual toggle. Written for a player who wants to learn how strong 40k players
think; the AI-engineering notes are present but secondary and collapsed.
"""

from __future__ import annotations

import html
import json
import os
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "ai_learnings.json")
OUT = os.path.join(HERE, "ai_learnings.html")

# Player-facing names for the decision axis. The JSON keeps the machine keys.
DECISION_LABEL = {
    "positioning_and_concealment": "Where to stand",
    "screening_and_zoning": "Screening and denying space",
    "target_selection": "What to shoot",
    "objective_trade": "Objectives and scoring",
    "attrition_and_trades": "When to accept a bad trade",
    "reserves_and_arrival": "Reserves and arrival",
    "melee_commitment": "When to charge",
    "disengage_and_lock": "Staying in combat, or getting out",
    "ability_timing": "When to spend your big ability",
    "action_economy": "Who performs the actions",
    "tempo_and_commitment": "Turn order and commitment",
    "deployment": "Deployment",
}

DECISION_ORDER = [
    "positioning_and_concealment", "screening_and_zoning", "target_selection",
    "objective_trade", "attrition_and_trades", "melee_commitment",
    "disengage_and_lock", "reserves_and_arrival", "ability_timing",
    "action_economy", "tempo_and_commitment", "deployment",
]

CSS = """
:root{
  --bg:#fbfaf8; --panel:#ffffff; --ink:#1c1a17; --muted:#6a6560; --line:#e4e0da;
  --accent:#8a2f24; --accent-soft:#f3e6e3; --chip:#f1eee9;
  --hi:#2f6b4f; --hi-soft:#e6f0ea; --mid:#8a6a1f; --mid-soft:#f6efdd;
  --lo:#6a6560; --lo-soft:#efedea;
}
@media (prefers-color-scheme:dark){
  :root{
    --bg:#16151a; --panel:#1e1d23; --ink:#eceaf0; --muted:#9a95a3; --line:#302e38;
    --accent:#e0857a; --accent-soft:#33232a; --chip:#282730;
    --hi:#7fd0a5; --hi-soft:#1b2f26; --mid:#e3c274; --mid-soft:#332c1c;
    --lo:#9a95a3; --lo-soft:#26252c;
  }
}
:root[data-theme=light]{
  --bg:#fbfaf8; --panel:#ffffff; --ink:#1c1a17; --muted:#6a6560; --line:#e4e0da;
  --accent:#8a2f24; --accent-soft:#f3e6e3; --chip:#f1eee9;
  --hi:#2f6b4f; --hi-soft:#e6f0ea; --mid:#8a6a1f; --mid-soft:#f6efdd;
  --lo:#6a6560; --lo-soft:#efedea;
}
:root[data-theme=dark]{
  --bg:#16151a; --panel:#1e1d23; --ink:#eceaf0; --muted:#9a95a3; --line:#302e38;
  --accent:#e0857a; --accent-soft:#33232a; --chip:#282730;
  --hi:#7fd0a5; --hi-soft:#1b2f26; --mid:#e3c274; --mid-soft:#332c1c;
  --lo:#9a95a3; --lo-soft:#26252c;
}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);
  font:16px/1.6 ui-serif,Georgia,'Iowan Old Style','Times New Roman',serif;
  -webkit-text-size-adjust:100%}
.wrap{max-width:920px;margin:0 auto;padding:0 20px 96px}
header{padding:56px 0 8px;border-bottom:1px solid var(--line);margin-bottom:28px}
h1{font-size:2.1rem;line-height:1.15;margin:0 0 10px;letter-spacing:-.01em}
.sub{color:var(--muted);margin:0;max-width:62ch}
.meta{color:var(--muted);font-size:.85rem;margin-top:14px}
.sans{font-family:ui-sans-serif,system-ui,-apple-system,'Segoe UI',Roboto,sans-serif}
h2{font-size:1.32rem;margin:44px 0 4px;letter-spacing:-.01em;scroll-margin-top:16px}
h2 .n{color:var(--muted);font-size:.8rem;font-weight:400;margin-left:8px;
  font-family:ui-sans-serif,system-ui,sans-serif}
.dfn{color:var(--muted);font-size:.92rem;margin:0 0 18px;max-width:64ch}
.controls{position:sticky;top:0;z-index:5;background:var(--bg);
  border-bottom:1px solid var(--line);padding:12px 0 12px;margin-bottom:6px}
.row{display:flex;flex-wrap:wrap;gap:6px;align-items:center;margin-bottom:7px}
.row:last-child{margin-bottom:0}
.lbl{font-size:.72rem;text-transform:uppercase;letter-spacing:.09em;color:var(--muted);
  font-family:ui-sans-serif,system-ui,sans-serif;margin-right:6px;min-width:66px}
button{font:inherit;font-family:ui-sans-serif,system-ui,sans-serif;font-size:.8rem;
  background:var(--chip);color:var(--ink);border:1px solid transparent;
  border-radius:999px;padding:4px 11px;cursor:pointer;line-height:1.4}
button:hover{border-color:var(--line)}
button[aria-pressed=true]{background:var(--accent-soft);border-color:var(--accent);
  color:var(--accent);font-weight:600}
.theme{margin-left:auto}
article{background:var(--panel);border:1px solid var(--line);border-radius:12px;
  padding:20px 22px;margin:0 0 14px}
.claim{font-size:1.06rem;font-weight:600;margin:0 0 10px;line-height:1.45}
.tags{display:flex;flex-wrap:wrap;gap:6px;margin:0 0 12px}
.tag{font-family:ui-sans-serif,system-ui,sans-serif;font-size:.7rem;
  letter-spacing:.03em;padding:2px 9px;border-radius:999px;background:var(--chip);
  color:var(--muted);white-space:nowrap}
.tag.fac{background:var(--accent-soft);color:var(--accent);font-weight:600}
.tag.high{background:var(--hi-soft);color:var(--hi)}
.tag.medium{background:var(--mid-soft);color:var(--mid)}
.tag.low{background:var(--lo-soft);color:var(--lo)}
.tag.warn{background:var(--accent-soft);color:var(--accent);font-weight:600}
p.detail{margin:0 0 12px}
.diff{margin:0 0 12px;padding:10px 14px;border-left:3px solid var(--accent);
  background:var(--accent-soft);border-radius:0 8px 8px 0;font-size:.94rem}
.diff b{font-family:ui-sans-serif,system-ui,sans-serif;font-size:.7rem;
  text-transform:uppercase;letter-spacing:.08em;display:block;margin-bottom:3px;
  color:var(--accent)}
.src{font-family:ui-sans-serif,system-ui,sans-serif;font-size:.85rem;
  color:var(--muted);margin-top:12px}
.src li{margin-bottom:5px}
.src ul{margin:6px 0 0;padding-left:18px}
.src a{color:var(--accent);text-decoration:none;border-bottom:1px solid transparent}
.src a:hover{border-bottom-color:var(--accent)}
.q{color:var(--ink);opacity:.85}
details{margin-top:14px;border-top:1px dashed var(--line);padding-top:10px}
summary{cursor:pointer;font-family:ui-sans-serif,system-ui,sans-serif;
  font-size:.78rem;color:var(--muted);letter-spacing:.03em;list-style:none}
summary::-webkit-details-marker{display:none}
summary::before{content:"▸ ";color:var(--accent)}
details[open] summary::before{content:"▾ "}
details .body{font-family:ui-sans-serif,system-ui,sans-serif;font-size:.85rem;
  color:var(--muted);margin-top:10px}
details .body div{margin-bottom:7px}
details .body b{color:var(--ink);font-weight:600}
code{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:.85em;
  background:var(--chip);padding:1px 5px;border-radius:4px}
.tblwrap{overflow-x:auto;border:1px solid var(--line);border-radius:12px;
  background:var(--panel)}
table{border-collapse:collapse;font-family:ui-sans-serif,system-ui,sans-serif;
  font-size:.8rem;width:100%}
th,td{padding:7px 10px;text-align:left;border-bottom:1px solid var(--line);
  white-space:nowrap}
th{color:var(--muted);font-weight:600;font-size:.72rem;text-transform:uppercase;
  letter-spacing:.05em}
td.n{text-align:center;color:var(--muted)}
td.n.has{color:var(--accent);font-weight:700}
tr:last-child td{border-bottom:none}
.note{background:var(--panel);border:1px solid var(--line);border-radius:12px;
  padding:18px 22px;margin-bottom:14px}
.note h3{margin:0 0 8px;font-size:1rem}
.note ul{margin:0;padding-left:20px;font-size:.94rem}
.note li{margin-bottom:7px}
.empty{color:var(--muted);font-style:italic;padding:26px 0}
footer{margin-top:56px;padding-top:20px;border-top:1px solid var(--line);
  color:var(--muted);font-size:.82rem;font-family:ui-sans-serif,system-ui,sans-serif}
@media(max-width:620px){
  h1{font-size:1.6rem} .wrap{padding:0 14px 64px} header{padding-top:32px}
  article{padding:16px 15px} .lbl{min-width:100%;margin-bottom:2px}
}
"""

JS = """
(function(){
  var D='all', F='all';
  function apply(){
    var shown={};
    document.querySelectorAll('article[data-d]').forEach(function(a){
      var ok=(D==='all'||a.dataset.d===D)&&(F==='all'||a.dataset.f===F);
      a.hidden=!ok; if(ok){shown[a.dataset.d]=(shown[a.dataset.d]||0)+1;}
    });
    var any=false;
    document.querySelectorAll('section[data-d]').forEach(function(s){
      var n=shown[s.dataset.d]||0; s.hidden=!n; if(n)any=true;
      var c=s.querySelector('.n'); if(c)c.textContent=n===1?'1 finding':n+' findings';
    });
    document.getElementById('empty').hidden=any;
  }
  document.addEventListener('click',function(e){
    var b=e.target.closest('button[data-k]'); if(!b)return;
    var k=b.dataset.k, v=b.dataset.v;
    if(k==='d'){D=v;} else if(k==='f'){F=v;} else if(k==='theme'){
      var r=document.documentElement;
      var cur=r.dataset.theme||(matchMedia('(prefers-color-scheme:dark)').matches?'dark':'light');
      r.dataset.theme=cur==='dark'?'light':'dark'; return;
    }
    document.querySelectorAll('button[data-k="'+k+'"]').forEach(function(o){
      o.setAttribute('aria-pressed', o.dataset.v===v?'true':'false');
    });
    apply();
  });
  apply();
})();
"""


def esc(s):
    return html.escape(str(s), quote=True)


def build():
    doc = json.load(open(SRC))
    findings = doc["findings"]
    by_decision = defaultdict(list)
    for f in findings:
        by_decision[f["decision"]].append(f)
    defs = {d["name"]: d["definition"] for d in doc["taxonomy"]["decisions"]}
    order = [d for d in DECISION_ORDER if by_decision.get(d)]
    order += [d for d in by_decision if d not in order]

    factions = sorted({f["faction"] for f in findings if f["faction"] != "general"})
    fcount = {f["name"]: f["finding_count"] for f in doc["taxonomy"]["factions"]}
    tcount = {f["name"]: f["transcript_count"] for f in doc["taxonomy"]["factions"]}

    P = []
    a = P.append
    a('<title>How good 40k players think — mined from 1,029 YouTube transcripts</title>')
    a('<meta name="viewport" content="width=device-width,initial-scale=1">')
    a('<style>%s</style>' % CSS)
    a('<div class="wrap">')

    # ---- header
    c = doc["corpus"]
    a('<header>')
    a('<h1>How good 40k players actually think</h1>')
    a('<p class="sub">%d decision patterns pulled out of roughly %s hours of '
      '11th-edition Warhammer 40,000 talk — tournament coverage, battle reports and '
      'list reviews — organised by the decision you are making, not by the video it '
      'came from. Every claim links to the moment somebody said it.</p>'
      % (len(findings), "{:,}".format(int(round(c["words"] / 9000, -2)))))
    a('<p class="meta sans">%s transcripts · %s channels · %s · generated %s</p>'
      % (esc(c["transcripts"]), esc(c["channels"]), esc(c["date_range"]), esc(doc["generated"])))
    a('</header>')

    # ---- controls
    a('<div class="controls sans">')
    a('<div class="row"><span class="lbl">Decision</span>')
    a('<button data-k="d" data-v="all" aria-pressed="true">Everything</button>')
    for d in order:
        a('<button data-k="d" data-v="%s" aria-pressed="false">%s</button>'
          % (esc(d), esc(DECISION_LABEL.get(d, d))))
    a('</div>')
    a('<div class="row"><span class="lbl">Army</span>')
    a('<button data-k="f" data-v="all" aria-pressed="true">All armies</button>')
    a('<button data-k="f" data-v="general" aria-pressed="false">Holds for everyone</button>')
    for fa in factions:
        a('<button data-k="f" data-v="%s" aria-pressed="false">%s</button>' % (esc(fa), esc(fa)))
    a('<button class="theme" data-k="theme" data-v="t">Light / dark</button>')
    a('</div></div>')

    # ---- findings
    for d in order:
        a('<section data-d="%s">' % esc(d))
        a('<h2>%s<span class="n"></span></h2>' % esc(DECISION_LABEL.get(d, d)))
        a('<p class="dfn">%s</p>' % esc(defs.get(d, "")))
        for f in by_decision[d]:
            a('<article data-d="%s" data-f="%s">' % (esc(d), esc(f["faction"])))
            a('<p class="claim">%s</p>' % esc(f["claim"]))
            a('<div class="tags">')
            if f["faction"] != "general":
                a('<span class="tag fac">%s</span>' % esc(f["faction"]))
            else:
                a('<span class="tag">every army</span>')
            a('<span class="tag %s">%s confidence</span>' % (esc(f["confidence"]), esc(f["confidence"])))
            a('<span class="tag">%d channel%s agree</span>'
              % (f["corroborating_channels"], "" if f["corroborating_channels"] == 1 else "s"))
            rs = f["rules_status"]
            label = {"confirmed": "matches the rules", "player_opinion": "player judgement",
                     "contradicts_rules": "CONTRADICTS THE RULES",
                     "unverified": "unverified against the rules"}.get(rs, rs)
            a('<span class="tag%s">%s</span>'
              % (" warn" if rs == "contradicts_rules" else "", esc(label)))
            a('</div>')
            a('<p class="detail">%s</p>' % esc(f["detail"]))
            if f.get("differs_from_general"):
                a('<div class="diff"><b>Why this army is different</b>%s</div>'
                  % esc(f["differs_from_general"]))
            a('<div class="src"><ul>')
            for e in f["evidence"]:
                a('<li><a href="%s" target="_blank" rel="noopener">%s @ %s</a> — '
                  '<span class="q">&ldquo;%s&rdquo;</span></li>'
                  % (esc(e["url"]), esc(e["channel"]), esc(e["timestamp"]), esc(e["quote"])))
            a('</ul></div>')
            im = f["ai_impact"]
            a('<details><summary>What this means for the game&rsquo;s AI</summary>'
              '<div class="body">')
            a('<div><b>Today:</b> %s</div>' % esc(im["current_behaviour"]))
            a('<div><b>Change:</b> %s</div>' % esc(im["suggested_change"]))
            a('<div><b>Risk:</b> %s</div>' % esc(im["risk"]))
            a('<div><b>Where:</b> <code>%s</code> &middot; %s &middot; %s priority</div>'
              % (esc(im.get("target") or "n/a"), esc(im["seam"]), esc(f["priority"])))
            a('</div></details>')
            a('</article>')
        a('</section>')
    a('<p class="empty" id="empty" hidden>Nothing matches those two filters — '
      'that combination is a coverage gap, listed at the bottom of the page.</p>')

    # ---- coverage matrix
    a('<h2>Where the evidence actually is</h2>')
    a('<p class="dfn">Findings per decision and army. Blank cells are honest gaps, '
      'not zero-importance: several armies have plenty of transcripts and still '
      'produced nothing decision-shaped.</p>')
    a('<div class="tblwrap"><table><thead><tr><th>Army</th><th>Transcripts</th>')
    for d in order:
        a('<th>%s</th>' % esc(DECISION_LABEL.get(d, d).split()[0]))
    a('<th>Total</th></tr></thead><tbody>')
    matrix = doc["taxonomy"]["matrix"]
    rows = ["general"] + [f for f in factions]
    for fa in rows:
        a('<tr><td>%s</td><td class="n">%s</td>'
          % (esc("Holds for everyone" if fa == "general" else fa), esc(tcount.get(fa, "—"))))
        for d in order:
            n = matrix.get(d, {}).get(fa, 0)
            a('<td class="n%s">%s</td>' % (" has" if n else "", n or "·"))
        a('<td class="n%s">%d</td>' % (" has" if fcount.get(fa) else "", fcount.get(fa, 0)))
        a('</tr>')
    a('</tbody></table></div>')

    # ---- disagreements
    a('<h2>Where good players disagree</h2>')
    a('<p class="dfn">Recorded rather than smoothed over. Where a disagreement has a '
      'resolving variable, it is named.</p>')
    for dis in doc["disagreements"]:
        a('<div class="note"><h3>%s</h3><ul>' % esc(dis["topic"]))
        for pos in dis["positions"]:
            a('<li>%s</li>' % esc(pos))
        a('</ul><p class="dfn" style="margin:12px 0 0">%s</p></div>' % esc(dis["note"]))

    # ---- gaps
    a('<h2>What this corpus does not tell you</h2>')
    a('<div class="note"><ul>')
    for g in doc["gaps"]:
        a('<li>%s</li>' % esc(g))
    a('</ul></div>')

    a('<footer>Mined from auto-generated captions, so unit and army names are '
      'frequently mangled — no finding is assigned to an army on a single '
      'mis-hearable mention. Quotes are verbatim from the captions, including their '
      'errors. Rules claims were checked against the 11th-edition core rules; claims '
      'that are players&rsquo; judgement rather than rules are labelled as such. '
      'The corpus skews competitive and is a broad sweep, not a census.</footer>')
    a('</div>')
    a('<script>%s</script>' % JS)

    with open(OUT, "w") as fh:
        fh.write("\n".join(P))
    print("wrote %s (%d KB, %d findings)"
          % (OUT, os.path.getsize(OUT) // 1024, len(findings)))


if __name__ == "__main__":
    build()
