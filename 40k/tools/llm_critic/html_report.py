"""REPORT.html — one self-contained page per critic run for manual validation.

Every reviewed decision gets a card: the two screenshots (whole board + close-up,
with the AI's own suggestion overlay drawn), what the AI suggested, the options
it weighed with their score terms, its reasoning, line of sight, and the LLM
reviewer's verdict + proposed fix. Under each card the human records two calls:
was the AI's decision good or bad, and was the reviewer right or wrong. Those
are kept in the browser (localStorage) and exported as verdicts JSON, which
`critic.py promote <run> --from-verdicts <file>` turns into AI test cases and
which scores the reviewer's accuracy.

Images are embedded as JPEG data URIs so the page is a single shareable file.
"""
import base64
import html
import io
import json
import os
import re


def _img_uri(path, max_w):
    from PIL import Image
    img = Image.open(path).convert("RGB")
    if img.width > max_w:
        img = img.resize((max_w, round(img.height * max_w / img.width)), Image.LANCZOS)
    buf = io.BytesIO()
    img.save(buf, "JPEG", quality=80, optimize=True)
    return "data:image/jpeg;base64," + base64.b64encode(buf.getvalue()).decode()


def _md(text):
    """Just enough Markdown for proposals.md: ### headings, - bullets,
    **bold**, `code`, paragraphs."""
    out, in_list = [], False
    for line in text.splitlines():
        s = html.escape(line.rstrip())
        s = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", s)
        s = re.sub(r"`([^`]+)`", r"<code>\1</code>", s)
        m = re.match(r"^\s*[-*] (.*)", s)
        if m:
            if not in_list:
                out.append("<ul>")
                in_list = True
            out.append(f"<li>{m.group(1)}</li>")
            continue
        if in_list:
            out.append("</ul>")
            in_list = False
        h = re.match(r"^(#{1,4}) (.*)", s)
        if h:
            out.append(f"<h3>{h.group(2)}</h3>")
        elif s.strip():
            out.append(f"<p>{s}</p>")
    if in_list:
        out.append("</ul>")
    return "\n".join(out)


def _e(s):
    return html.escape(str(s if s is not None else ""))


def _options_table(options):
    rows = []
    for o in options:
        terms = o.get("score_terms", {})
        nums = {k: v for k, v in terms.items() if isinstance(v, (int, float)) and v != 0}
        top = sorted(nums.items(), key=lambda kv: -abs(kv[1]))
        chips = " ".join(f'<span class="term {"neg" if v < 0 else "pos"}">{_e(k)} {v:+g}</span>' for k, v in top)
        rows.append(f'<tr class="{"chosen" if o.get("chosen") else ""}"><td>{"&#10003;" if o.get("chosen") else ""}</td>'
                    f'<td>{_e(o.get("option"))}</td><td class="num">{_e(o.get("score"))}</td>'
                    f'<td class="terms">{chips}</td></tr>')
    return ('<table class="opts"><thead><tr><th></th><th>Option</th><th>Score</th><th>Score terms (largest first)</th>'
            '</tr></thead><tbody>' + "".join(rows) + "</tbody></table>")


def _same(v):
    """verify.json value: bool (older runs) or {"same", "now", "now_options"}."""
    return v.get("same") if isinstance(v, dict) else bool(v)


def _consistency_block(runs):
    """Every review of this same captured state, side by side."""
    verdicts = [r.get("verdict", "error") for r in runs]
    agree = len(set(verdicts)) == 1
    head = (f'<p class="cons {"ok" if agree else "bad"}"><span class="label">Reviewer consistency</span> '
            f'{len(runs)} independent reviews of this exact state: '
            + ", ".join(f'<span class="badge {_e(v)}">{_e(v)}</span>' for v in verdicts)
            + (" — consistent" if agree else " — <strong>inconsistent</strong>") + "</p>")
    rows = "".join(
        f'<tr><td>{i + 1}</td><td><span class="badge {_e(r.get("verdict", "error"))}">{_e(r.get("verdict", "error"))}</span>'
        f'<br><span class="muted">sev {_e(r.get("severity"))} · {_e(r.get("confidence"))}</span></td>'
        f'<td>{_e(r.get("summary", r.get("error", "")))}</td><td>{_e(r.get("better_option"))}</td>'
        f'<td>{_e(r.get("proposed_fix"))}</td></tr>'
        for i, r in enumerate(runs))
    table = ('<table class="opts runs"><thead><tr><th>#</th><th>Verdict</th><th>Review</th><th>Better option</th>'
             '<th>Proposed fix</th></tr></thead><tbody>' + rows + "</tbody></table>")
    if agree:
        return head + f"<details><summary>Compare the {len(runs)} reviews</summary>{table}</details>"
    return head + table


def _drift_block(v):
    if not isinstance(v, dict) or v.get("same", True):
        return ""
    opts = "".join(f'<li>{"<strong>" if o.get("picked") else ""}{_e(o.get("option"))} ({_e(o.get("score"))})'
                   f'{"</strong> ← picked" if o.get("picked") else ""}</li>' for o in v.get("now_options", []))
    return (f'<div class="drift"><span class="label">Same position reloaded</span> the AI now suggests '
            f'<strong>{_e(v.get("now"))}</strong> instead.'
            + (f"<ul class='plain'>{opts}</ul>" if opts else "") + "</div>")


def build(run_dir, bundles, rows, repro, proposals_md, all_reviews=None, standalone=True):
    """standalone=False: body content only (title/meta/style first), for an
    Artifact publish, which wraps the page in its own document skeleton."""
    run_name = os.path.basename(run_dir.rstrip("/"))
    all_reviews = all_reviews or {}
    n_inconsistent = 0
    n_drift = 0
    counts = {}
    for r in rows:
        counts[r.get("verdict", "error")] = counts.get(r.get("verdict", "error"), 0) + 1
    cards = []
    for r in rows:
        cid = r["id"]
        b = bundles.get(cid, {})
        v = r.get("verdict", "error")
        shots = b.get("shots", {})
        imgs = []
        for key, label, w in (("board", "Whole board", 900), ("zoom", "Close-up", 1400)):
            p = os.path.join(run_dir, shots.get(key, "")) if shots.get(key) else ""
            if p and os.path.exists(p):
                imgs.append(f'<figure><a href="#" class="zoomable"><img decoding="async" alt="{label} for {_e(cid)}" '
                            f'src="{_img_uri(p, w)}"></a><figcaption>{label}</figcaption></figure>')
        rp = ("reproduces on reload" if _same(repro[cid]) else "drifts on reload") if cid in repro else ""
        drift = cid in repro and not _same(repro[cid])
        n_drift += drift
        runs = [x for x in all_reviews.get(cid, []) if "verdict" in x] or [r]
        inconsistent = len({x.get("verdict") for x in runs}) > 1
        n_inconsistent += inconsistent
        detail = lambda title, body: f"<details><summary>{title}</summary>{body}</details>"  # noqa: E731
        los = "".join(f'<li>{_e(l.get("enemy"))} — {l.get("centroid_dist_in")}" — '
                      f'{"<strong>visible</strong>" if l.get("has_los") else "no line of sight"}</li>'
                      for l in sorted(b.get("line_of_sight", []), key=lambda l: l.get("centroid_dist_in", 0)))
        reasoning = "".join(f"<li>{_e(s)}</li>" for s in b.get("ai_reasoning", []))
        review_rows = "".join(
            f"<dt>{label}</dt><dd>{_e(r.get(key))}</dd>"
            for key, label in (("board_observations", "What it saw"), ("summary", "Review"), ("better_option", "Better option"),
                               ("logic_flaw", "Logic flaw"), ("proposed_fix", "Proposed fix"),
                               ("rules_uncertainty", "Rules uncertainty"), ("error", "Error"))
            if r.get(key))
        cards.append(f"""
<article class="card" data-id="{_e(cid)}" data-verdict="{_e(v)}" data-flags="{"inconsistent " if inconsistent else ""}{"drift" if drift else ""}">
  <header>
    <span class="badge {_e(v)}">{_e(v)}</span>
    <h2>{_e(cid)}</h2>
    <span class="meta">P{_e(b.get("player"))} · round {_e(b.get("round"))} · {_e(b.get("phase"))}
      · severity {_e(r.get("severity"))} · {_e(r.get("confidence"))} confidence{(" · " + rp) if rp else ""}</span>
  </header>
  <div class="shots">{"".join(imgs) or '<p class="muted">No screenshots for this decision.</p>'}</div>
  <p class="suggestion"><span class="label">AI suggested</span> {_e(b.get("suggestion"))}</p>
  {_drift_block(repro.get(cid))}
  <dl class="review">{review_rows}</dl>
  {_consistency_block(runs) if len(runs) > 1 else ""}
  {detail(f"Options the AI weighed ({len(b.get('options', []))} of {b.get('options_total', '?')})", _options_table(b.get("options", [])))}
  {detail("AI reasoning", f"<ul class='plain'>{reasoning}</ul>")}
  {detail("Line of sight from the acting unit", f"<ul class='plain'>{los or '<li>n/a</li>'}</ul>") if b.get("line_of_sight") else ""}
  <fieldset class="you">
    <legend>Your call</legend>
    <div class="q"><span>The AI's decision was</span>
      <label><input type="radio" name="ai_{_e(cid)}" value="good"> good</label>
      <label><input type="radio" name="ai_{_e(cid)}" value="bad"> bad</label>
      <label><input type="radio" name="ai_{_e(cid)}" value="unsure"> unsure</label></div>
    <div class="q"><span>The reviewer was</span>
      <label><input type="radio" name="critic_{_e(cid)}" value="right"> right</label>
      <label><input type="radio" name="critic_{_e(cid)}" value="wrong"> wrong</label>
      <label><input type="radio" name="critic_{_e(cid)}" value="unsure"> unsure</label></div>
    <textarea name="note_{_e(cid)}" rows="2" placeholder="Note: what must the AI do? Where is the reviewer wrong?"></textarea>
  </fieldset>
</article>""")

    summary = ", ".join(f"{v} {k}" for k, v in sorted(counts.items()))
    filters = "".join(f'<button type="button" data-f="{k}">{k} ({n})</button>'
                      for k, n in [("all", len(rows))] + sorted(counts.items()))
    if n_inconsistent:
        filters += f'<button type="button" data-f="inconsistent">reviewer inconsistent ({n_inconsistent})</button>'
    if n_drift:
        filters += f'<button type="button" data-f="drift">AI drifts on reload ({n_drift})</button>'
    page = TEMPLATE \
        .replace("%%RUN%%", _e(run_name)) \
        .replace("%%RUN_JSON%%", json.dumps(run_name)) \
        .replace("%%SUMMARY%%", _e(f"{len(rows)} decisions reviewed — {summary}")) \
        .replace("%%PROPOSALS%%", _md(proposals_md) if proposals_md else '<p class="muted">No synthesis yet.</p>') \
        .replace("%%FILTERS%%", filters) \
        .replace("%%CARDS%%", "\n".join(cards))
    page = page.replace("%%TITLE%%", "AI Suggestion Critic")
    return ("<!doctype html>\n<html lang=\"en\"><head><meta charset=\"utf-8\">\n" + page.replace("</style>", "</style></head><body>", 1)
            + "\n</body></html>\n") if standalone else page


TEMPLATE = """<title>%%TITLE%%</title>
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="claude:viewport-fit-sides" content="cover">
<style>
:root { --bg:#f6f5f2; --panel:#ffffff; --ink:#1d1d1b; --muted:#6b6a65; --line:#dedbd3;
  --accent:#8a5a00; --flawed:#b42318; --questionable:#b54708; --sound:#067647; --error:#475467;
  --chosen:#fff4d6; --pos:#e7f4ec; --neg:#fdeceb; }
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) {
  --bg:#17171a; --panel:#212126; --ink:#ecebe8; --muted:#a3a19b; --line:#36363d;
  --accent:#e0a640; --flawed:#f97066; --questionable:#fdb022; --sound:#47cd89; --error:#98a2b3;
  --chosen:#3a3220; --pos:#1d3326; --neg:#3d2020; color-scheme:dark; } }
:root[data-theme="dark"] { --bg:#17171a; --panel:#212126; --ink:#ecebe8; --muted:#a3a19b; --line:#36363d;
  --accent:#e0a640; --flawed:#f97066; --questionable:#fdb022; --sound:#47cd89; --error:#98a2b3;
  --chosen:#3a3220; --pos:#1d3326; --neg:#3d2020; color-scheme:dark; }
* { box-sizing:border-box; }
body { margin:0; background:var(--bg); color:var(--ink); font:15px/1.5 system-ui, -apple-system, Segoe UI, sans-serif; }
main { max-width:1200px; margin:0 auto; padding-block:24px 80px;
  padding-left:max(16px, env(safe-area-inset-left, 0px)); padding-right:max(16px, env(safe-area-inset-right, 0px)); }
.card, .proposals { min-width:0; } details { overflow-x:auto; }
#copied { display:none; width:100%; } #copied.show { display:block; }
h1 { font-size:24px; margin:0 0 4px; } h2 { font-size:16px; margin:0; font-family:ui-monospace, monospace; }
h3 { font-size:16px; margin:20px 0 6px; }
.muted, .meta { color:var(--muted); font-size:13px; }
section.proposals, .card, .toolbar { background:var(--panel); border:1px solid var(--line); border-radius:10px; padding:16px; margin:16px 0; }
.toolbar { position:sticky; top:env(safe-area-inset-top, 0px); z-index:5; display:flex; flex-wrap:wrap; gap:8px; align-items:center; }
.toolbar button { border:1px solid var(--line); background:var(--bg); color:var(--ink); border-radius:999px; padding:4px 12px; cursor:pointer; font:inherit; font-size:13px; }
.toolbar button.on { border-color:var(--accent); color:var(--accent); font-weight:600; }
.toolbar .spacer { flex:1; } .toolbar .stat { font-size:13px; color:var(--muted); }
.card header { display:flex; flex-wrap:wrap; gap:8px 12px; align-items:baseline; margin-bottom:12px; }
.badge { text-transform:uppercase; font-size:11px; font-weight:700; letter-spacing:.05em; padding:2px 8px; border-radius:4px; color:#fff; background:var(--error); }
.badge.flawed { background:var(--flawed); } .badge.questionable { background:var(--questionable); } .badge.sound { background:var(--sound); }
.shots { display:grid; grid-template-columns: 2fr 3fr; gap:12px; }
.shots figure { margin:0; } .shots img { width:100%; height:auto; border-radius:6px; border:1px solid var(--line); display:block; }
figcaption { font-size:12px; color:var(--muted); margin-top:4px; }
.suggestion { font-weight:600; } .label { display:inline-block; font-size:11px; text-transform:uppercase; letter-spacing:.05em; color:var(--muted); margin-right:6px; font-weight:600; }
dl.review { display:grid; grid-template-columns: max-content 1fr; gap:4px 12px; margin:8px 0; }
dl.review dt { color:var(--muted); font-size:13px; } dl.review dd { margin:0; }
details { margin:6px 0; } summary { cursor:pointer; color:var(--accent); font-size:14px; }
.opts { width:100%; border-collapse:collapse; font-size:13px; margin-top:6px; }
.opts td, .opts th { border-bottom:1px solid var(--line); padding:4px 6px; text-align:left; vertical-align:top; }
.opts tr.chosen { background:var(--chosen); } .num { text-align:right; font-variant-numeric:tabular-nums; }
.term { display:inline-block; font-size:11px; padding:0 5px; border-radius:3px; margin:1px; font-family:ui-monospace, monospace; }
.term.pos { background:var(--pos); } .term.neg { background:var(--neg); }
ul.plain { margin:4px 0; padding-left:18px; font-size:13px; }
fieldset.you { border:1px dashed var(--line); border-radius:8px; margin-top:12px; padding:8px 12px; }
legend { font-size:12px; text-transform:uppercase; letter-spacing:.05em; color:var(--muted); font-weight:600; }
.q { display:flex; flex-wrap:wrap; gap:4px 14px; align-items:center; margin:4px 0; } .q > span { min-width:170px; }
textarea { width:100%; margin-top:6px; background:var(--bg); color:var(--ink); border:1px solid var(--line); border-radius:6px; padding:6px; font:inherit; }
code { font-family:ui-monospace, monospace; font-size:13px; }
.cons { margin:10px 0 4px; } .cons .badge { margin:0 2px; }
.cons.bad { border-left:3px solid var(--flawed); padding-left:8px; }
.drift { border-left:3px solid var(--questionable); padding:4px 0 4px 8px; margin:8px 0; }
.runs td:nth-child(3), .runs td:nth-child(5) { min-width:220px; }
#lightbox { position:fixed; inset:0; background:rgba(0,0,0,.85); display:none; align-items:center; justify-content:center; z-index:10; cursor:zoom-out; }
#lightbox img { max-width:96vw; max-height:96vh; }
@media (max-width: 760px) { .shots { grid-template-columns:1fr; } dl.review { grid-template-columns:1fr; } .q > span { min-width:0; width:100%; } }
</style>
<main>
<h1>LLM critic review</h1>
<p class="muted">Run <code>%%RUN%%</code> · %%SUMMARY%%</p>
<p class="muted">Examine each decision. Give your verdict on the AI and on the reviewer. Then click <strong>Copy verdicts</strong>.
Paste the verdicts into <code>python3 40k/tools/llm_critic/critic.py promote &lt;run&gt; --from-verdicts -</code>. This browser keeps your answers.</p>
<section class="proposals"><h2 style="font-family:inherit;font-size:18px">Proposed improvements</h2>%%PROPOSALS%%</section>
<div class="toolbar">%%FILTERS%%<span class="spacer"></span><span class="stat" id="stat"></span>
<button type="button" id="export">Copy verdicts</button>
<textarea id="copied" rows="4" readonly aria-label="Verdicts JSON"></textarea></div>
%%CARDS%%
</main>
<div id="lightbox"><img alt="Full-size screenshot"></div>
<script>
(function () {
  var RUN = %%RUN_JSON%%, KEY = "llmcritic:" + RUN, state = {};
  try { state = JSON.parse(localStorage.getItem(KEY) || "{}"); } catch (e) { state = {}; }
  function save() { try { localStorage.setItem(KEY, JSON.stringify(state)); } catch (e) {} stat(); }
  var cards = Array.prototype.slice.call(document.querySelectorAll(".card"));
  cards.forEach(function (card) {
    var id = card.dataset.id, s = state[id] || {};
    card.querySelectorAll("input[type=radio]").forEach(function (inp) {
      var field = inp.name.split("_")[0];
      if (s[field] === inp.value) inp.checked = true;
      inp.addEventListener("change", function () { (state[id] = state[id] || {})[field] = inp.value; save(); });
    });
    var ta = card.querySelector("textarea");
    if (s.note) ta.value = s.note;
    ta.addEventListener("input", function () { (state[id] = state[id] || {}).note = ta.value; save(); });
  });
  function stat() {
    var done = 0, right = 0, judged = 0;
    cards.forEach(function (c) { var s = state[c.dataset.id] || {};
      if (s.ai || s.critic) done++;
      if (s.critic === "right" || s.critic === "wrong") { judged++; if (s.critic === "right") right++; } });
    document.getElementById("stat").textContent = done + "/" + cards.length + " judged" +
      (judged ? " · reviewer right " + right + "/" + judged : "");
  }
  stat();
  document.querySelectorAll(".toolbar button[data-f]").forEach(function (b) {
    if (b.dataset.f === "all") b.classList.add("on");
    b.addEventListener("click", function () {
      document.querySelectorAll(".toolbar button[data-f]").forEach(function (x) { x.classList.remove("on"); });
      b.classList.add("on");
      cards.forEach(function (c) { var f = b.dataset.f;
        c.style.display = (f === "all" || c.dataset.verdict === f || (" " + c.dataset.flags + " ").indexOf(" " + f + " ") >= 0) ? "" : "none"; });
    });
  });
  var exp = document.getElementById("export"), box = document.getElementById("copied");
  exp.addEventListener("click", function () {
    var text = JSON.stringify({run: RUN, exported: new Date().toISOString(), verdicts: state}, null, 1);
    box.value = text;
    function fallback() { box.classList.add("show"); box.focus(); box.select(); exp.textContent = "Select all and copy"; }
    try {
      navigator.clipboard.writeText(text).then(function () { exp.textContent = "Copied"; box.classList.remove("show");
        setTimeout(function () { exp.textContent = "Copy verdicts"; }, 2000); }, fallback);
    } catch (e) { fallback(); }
  });
  var lb = document.getElementById("lightbox");
  document.querySelectorAll("a.zoomable").forEach(function (a) {
    a.addEventListener("click", function (ev) { ev.preventDefault(); lb.querySelector("img").src = a.querySelector("img").src; lb.style.display = "flex"; });
  });
  lb.addEventListener("click", function () { lb.style.display = "none"; });
})();
</script>
"""
