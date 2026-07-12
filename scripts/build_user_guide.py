#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Build the UralCash user-guide catalog: docs/USER-GUIDE/*.md -> one self-contained
interactive docs/USER-GUIDE/index.html (inline CSS/JS, Cairo font embedded base64,
RTL Arabic, UralCash teal identity).

Run:  python scripts/build_user_guide.py
No third-party deps (stdlib only). Reads the md at build time, so the generator
carries the content — index.html is regenerated from the md, never hand-edited.
"""
import base64
import html
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GUIDE = ROOT / "docs" / "USER-GUIDE"
FONT = ROOT / "assets" / "fonts" / "Cairo-Regular.ttf"
OUT = GUIDE / "index.html"

DOMAIN_FILES = [
    "01-pos-hardware.md", "02-sales-delivery.md", "03-purchases.md",
    "04-inventory.md", "05-parties-loyalty.md", "06-treasury-papers.md",
    "07-accounting-core.md", "08-assets-mfg-einvoice.md",
    "09-reports-operational.md", "10-reports-financial.md",
    "11-admin-governance.md", "12-system-settings-hr.md",
]

# ── section label -> (icon, css-key). Matched by keyword substring since the
#    md labels vary ("الوصول / الصلاحية" vs "الوصول/الصلاحية", parentheticals…).
SECTION_MAP = [
    ("غرض", ("🎯", "purpose")),
    ("وصول", ("🔐", "access")),
    ("صلاحي", ("🔐", "access")),
    ("عناصر", ("🧩", "elements")),
    ("حقول", ("🧩", "elements")),
    ("سير العمل", ("🔄", "flow")),
    ("تدفق", ("🔄", "flow")),
    ("حالات", ("⚠️", "warn")),
    ("تحذير", ("⚠️", "warn")),
    ("مرتبط", ("🔗", "related")),
]


def section_meta(label):
    for key, meta in SECTION_MAP:
        if key in label:
            return meta
    return ("▪", "default")


# ────────────────────────────── inline markdown ──────────────────────────────
_CODE = re.compile(r"`([^`]+)`")
_BOLD = re.compile(r"\*\*(.+?)\*\*")
_LINK = re.compile(r"\[([^\]]+)\]\(([^)]+)\)")


def inline(text):
    """Escape then apply inline md: `code`, **bold**, [t](url).
    .md links render as plain text (standalone file — no local nav)."""
    out = []
    last = 0
    # protect inline code spans first (escape their content, no further md)
    for m in _CODE.finditer(text):
        out.append(_fmt(text[last:m.start()]))
        out.append("<code>%s</code>" % html.escape(m.group(1)))
        last = m.end()
    out.append(_fmt(text[last:]))
    return "".join(out)


def _fmt(text):
    text = html.escape(text)
    text = _BOLD.sub(lambda m: "<strong>%s</strong>" % m.group(1), text)

    def link(m):
        label, url = m.group(1), m.group(2)
        if ".md" in url:  # cross-doc link — keep text only in the standalone file
            return "<span class='xref'>%s</span>" % label
        return "<a href='%s' target='_blank' rel='noopener'>%s</a>" % (
            html.escape(url, quote=True), label)

    return _LINK.sub(link, text)


# ────────────────────────────── block parser ─────────────────────────────────
def render_blocks(lines):
    """Render a list of raw md lines (a section body) into HTML: paragraphs,
    nested unordered lists, ordered lists (as a step flow), blockquotes."""
    html_parts = []
    i = 0
    n = len(lines)
    while i < n:
        line = lines[i]
        stripped = line.strip()
        if not stripped:
            i += 1
            continue
        # heading inside a body (appendix sub-headings ###) -> small heading
        if stripped.startswith("###"):
            html_parts.append("<h4 class='sub'>%s</h4>" %
                              inline(stripped.lstrip("#").strip()))
            i += 1
            continue
        # pipe table: a '|...|' row followed by a '|---|' separator
        if (stripped.startswith("|") and i + 1 < n and
                re.match(r"^\|[\s:|-]+\|$", lines[i + 1].strip())):
            head = [c.strip() for c in stripped.strip("|").split("|")]
            i += 2
            rows = []
            while i < n and lines[i].strip().startswith("|"):
                rows.append([c.strip() for c in
                             lines[i].strip().strip("|").split("|")])
                i += 1
            th = "".join("<th>%s</th>" % inline(c) for c in head)
            trs = "".join(
                "<tr>%s</tr>" % "".join("<td>%s</td>" % inline(c) for c in r)
                for r in rows)
            html_parts.append(
                "<div class='tw'><table><thead><tr>%s</tr></thead>"
                "<tbody>%s</tbody></table></div>" % (th, trs))
            continue
        # blockquote
        if stripped.startswith(">"):
            buf = []
            while i < n and lines[i].strip().startswith(">"):
                buf.append(lines[i].strip()[1:].strip())
                i += 1
            html_parts.append("<blockquote>%s</blockquote>" %
                              inline(" ".join(buf)))
            continue
        # ordered list (numbered step flow)
        if re.match(r"^\d+\.\s", stripped):
            items, i = _collect_list(lines, i, ordered=True)
            html_parts.append(_render_list(items, ordered=True))
            continue
        # unordered list
        if re.match(r"^[-*]\s", stripped):
            items, i = _collect_list(lines, i, ordered=False)
            html_parts.append(_render_list(items, ordered=False))
            continue
        # paragraph (gather until blank / list / quote)
        buf = []
        while i < n and lines[i].strip() and not re.match(
                r"^(>|\d+\.\s|[-*]\s)", lines[i].strip()):
            buf.append(lines[i].strip())
            i += 1
        html_parts.append("<p>%s</p>" % inline(" ".join(buf)))
    return "\n".join(html_parts)


def _indent(line):
    return len(line) - len(line.lstrip(" "))


def _collect_list(lines, i, ordered):
    """Collect a (possibly nested) list starting at i. Returns (items, next_i).
    Each item = {'text': str, 'children': [items]}."""
    n = len(lines)
    base = _indent(lines[i])
    items = []
    pat = r"^\d+\.\s+(.*)$" if ordered else r"^[-*]\s+(.*)$"
    while i < n:
        raw = lines[i]
        if not raw.strip():
            i += 1
            continue
        ind = _indent(raw)
        if ind < base:
            break
        m = re.match(pat, raw.strip())
        if ind == base and m:
            items.append({"text": m.group(1), "children": []})
            i += 1
            # gather deeper-indented nested lists / continuation
            while i < n and (not lines[i].strip() or _indent(lines[i]) > base):
                if not lines[i].strip():
                    i += 1
                    continue
                sub = lines[i].strip()
                if re.match(r"^[-*]\s", sub):
                    children, i = _collect_list(lines, i, ordered=False)
                    items[-1]["children"].extend(
                        [("ul", children)])
                elif re.match(r"^\d+\.\s", sub):
                    children, i = _collect_list(lines, i, ordered=True)
                    items[-1]["children"].extend([("ol", children)])
                else:  # continuation text of the current item
                    items[-1]["text"] += " " + sub
                    i += 1
        elif ind == base and not m:
            break
        else:
            break
    return items, i


def _render_list(items, ordered):
    tag = "ol" if ordered else "ul"
    cls = " class='flow'" if ordered else ""
    parts = ["<%s%s>" % (tag, cls)]
    for it in items:
        inner = "<li>%s" % inline(it["text"])
        for ctag, children in it["children"]:
            inner += _render_list(children, ordered=(ctag == "ol"))
        inner += "</li>"
        parts.append(inner)
    parts.append("</%s>" % tag)
    return "".join(parts)


# ────────────────────────────── md structure ─────────────────────────────────
SECTION_RE = re.compile(r"^\*\*(.+?)\s*:\s*\*\*\s*(.*)$")
H2_RE = re.compile(r"^##\s+(.+?)\s*$")
CODECHIP_RE = re.compile(r"^(.*?)\s*—\s*`([^`]+)`\s*$")


def parse_domain(path):
    text = path.read_text(encoding="utf-8")
    text = text.replace("<div dir=\"rtl\">", "").replace("</div>", "")
    lines = text.split("\n")

    title = path.stem
    intro_lines, warn_lines = [], []
    screens = []
    i, n = 0, len(lines)

    # H1 title + domain intro (until first '##' or '---')
    while i < n:
        s = lines[i].strip()
        if s.startswith("# "):
            title = s[2:].replace("دليل المستخدم —", "").strip()
            i += 1
            break
        i += 1
    while i < n and not lines[i].strip().startswith("##"):
        s = lines[i].strip()
        if s.startswith(">"):
            warn_lines.append(s[1:].strip())
        elif s and s != "---":
            intro_lines.append(s)
        i += 1

    # screens
    while i < n:
        m = H2_RE.match(lines[i].strip())
        if not m:
            i += 1
            continue
        head = m.group(1)
        cm = CODECHIP_RE.match(head)
        stitle, chip = (cm.group(1).strip(), cm.group(2)) if cm else (head, None)
        i += 1
        # collect this screen's body until next '##'
        body = []
        while i < n and not H2_RE.match(lines[i].strip()):
            body.append(lines[i])
            i += 1
        screens.append({"title": stitle, "chip": chip, "raw": body,
                        "sections": parse_sections(body)})
    return {"title": title, "intro": " ".join(intro_lines),
            "warn": " ".join(warn_lines), "screens": screens}


def parse_sections(body):
    """Split a screen body into labelled sections on '**label:**' lines."""
    sections = []
    cur = None
    for line in body:
        if line.strip() == "---":
            continue
        m = SECTION_RE.match(line.strip())
        if m:
            if cur:
                sections.append(cur)
            cur = {"label": m.group(1).strip(), "lines": []}
            if m.group(2).strip():
                cur["lines"].append(m.group(2).strip())
        elif cur is not None:
            cur["lines"].append(line)
        # lines before the first bold-label are ignored (screens open with one)
    if cur:
        sections.append(cur)
    return sections


# ────────────────────────────── notes page ───────────────────────────────────
def parse_readme_notes(path):
    """Extract the 'ملاحظات وثغرات معروفة' section from README as the notes page."""
    text = path.read_text(encoding="utf-8").replace(
        "<div dir=\"rtl\">", "").replace("</div>", "")
    lines = text.split("\n")
    out, capture = [], False
    for line in lines:
        s = line.strip()
        if s.startswith("## ") and "ملاحظات" in s:
            capture = True
            continue
        if capture and s.startswith("## "):
            break
        if capture and s.startswith("---") and out and out[-1].strip() == "":
            break
        if capture:
            out.append(line)
    return render_blocks(out) if out else ""


# ────────────────────────────── slug ─────────────────────────────────────────
_slug_bad = re.compile(r"[^0-9a-zA-Z؀-ۿ]+")


def slug(*parts):
    s = "-".join(parts)
    s = _slug_bad.sub("-", s).strip("-")
    return s


# ────────────────────────────── HTML build ───────────────────────────────────
def build():
    domains = [parse_domain(GUIDE / f) for f in DOMAIN_FILES]
    for d in domains:
        d["real"] = [s for s in d["screens"] if s["sections"]]
    total_screens = sum(len(d["real"]) for d in domains)
    notes_html = parse_readme_notes(GUIDE / "README.md")

    font_b64 = base64.b64encode(FONT.read_bytes()).decode("ascii")

    # sidebar tree + main content
    sidebar, main = [], []
    for di, d in enumerate(domains, 1):
        num = "%02d" % di
        did = "domain-%s" % num
        sidebar.append(
            "<div class='nav-group' data-domain='%s'>"
            "<button class='nav-head' aria-expanded='false' "
            "data-target='grp-%s'>"
            "<span class='nav-num'>%s</span>"
            "<span class='nav-title'>%s</span>"
            "<span class='nav-count'>%d</span>"
            "<span class='nav-caret' aria-hidden='true'>‹</span>"
            "</button><ul class='nav-list' id='grp-%s'>"
            % (num, num, num, html.escape(d["title"]), len(d["real"]), num))

        main.append("<section class='domain' id='%s' data-domain='%s'>" %
                    (did, num))
        main.append(
            "<div class='domain-head'><span class='domain-num'>%s</span>"
            "<h2>%s</h2><span class='domain-count'>%d شاشة</span></div>"
            % (num, html.escape(d["title"]), len(d["real"])))
        if d["intro"]:
            main.append("<p class='domain-intro'>%s</p>" % inline(d["intro"]))
        if d["warn"]:
            main.append("<div class='domain-warn'>%s</div>" % inline(d["warn"]))

        for si, sc in enumerate(d["screens"], 1):
            sid = slug(num, "s%02d" % si, sc["chip"] or sc["title"][:24])
            appendix = not sc["sections"]
            hay = html.escape(
                (sc["title"] + " " + (sc["chip"] or "") + " " +
                 " ".join(sc["raw"])).lower(), quote=True)
            sidebar.append(
                "<li><a class='nav-screen%s' href='#%s' data-hay='%s'>%s</a></li>"
                % (" is-appendix" if appendix else "", sid, hay,
                   html.escape(sc["title"])))
            chip = ("<code class='chip'>%s</code>" % html.escape(sc["chip"])
                    if sc["chip"] else "")
            copy = ("<button class='copy' data-id='%s' title='نسخ الرابط' "
                    "aria-label='نسخ رابط الشاشة'>🔗</button>" % sid)

            if appendix:
                main.append(
                    "<article class='screen appendix' id='%s' data-hay='%s'>"
                    "<header class='screen-h'><span class='ap-tag'>مرجع</span>"
                    "<h3>%s</h3>%s%s</header>"
                    "<div class='facets'><div class='ap-body'>%s</div></div>"
                    "</article>"
                    % (sid, hay, html.escape(sc["title"]), chip, copy,
                       render_blocks(sc["raw"])))
                continue

            facets = []
            for s in sc["sections"]:
                icon, key = section_meta(s["label"])
                facets.append(
                    "<div class='facet facet-%s'><div class='facet-h'>"
                    "<span class='facet-ic' aria-hidden='true'>%s</span>"
                    "<span class='facet-l'>%s</span></div>"
                    "<div class='facet-b'>%s</div></div>"
                    % (key, icon, html.escape(s["label"]),
                       render_blocks(s["lines"])))
            main.append(
                "<article class='screen' id='%s' data-hay='%s'>"
                "<header class='screen-h'>"
                "<h3>%s</h3>%s%s"
                "</header><div class='facets'>%s</div></article>"
                % (sid, hay, html.escape(sc["title"]), chip, copy,
                   "".join(facets)))
        main.append("</section>")

    if notes_html:
        sidebar.append(
            "<div class='nav-group'><button class='nav-head' "
            "aria-expanded='false' data-target='grp-notes'>"
            "<span class='nav-num'>ℹ</span>"
            "<span class='nav-title'>ملاحظات وثغرات معروفة</span>"
            "<span class='nav-caret' aria-hidden='true'>‹</span></button>"
            "<ul class='nav-list' id='grp-notes'>"
            "<li><a class='nav-screen' href='#notes' data-hay='ملاحظات'>"
            "الملاحظات المعروفة</a></li></ul></div>")
        main.append(
            "<section class='domain' id='notes' data-domain='notes'>"
            "<div class='domain-head'><span class='domain-num'>ℹ</span>"
            "<h2>ملاحظات وثغرات معروفة</h2></div>"
            "<article class='screen' id='notes-body' data-hay='ملاحظات ثغرات'>"
            "<div class='facets'><div class='facet facet-warn'>"
            "<div class='facet-b'>%s</div></div></div></article></section>"
            % notes_html)

    doc = PAGE.format(
        font_b64=font_b64,
        total=total_screens,
        ndomains=len(domains),
        sidebar="\n".join(sidebar),
        main="\n".join(main),
    )
    OUT.write_text(doc, encoding="utf-8")

    # ── build self-check: every domain parsed, screen total sane ──
    print("Domains: %d" % len(domains))
    n_appendix = 0
    for di, d in enumerate(domains, 1):
        ap = len(d["screens"]) - len(d["real"])
        n_appendix += ap
        flag = "  (+%d مرجع)" % ap if ap else ""
        print("  %02d %-42s %2d شاشة%s" % (di, d["title"][:42],
                                           len(d["real"]), flag))
    print("TOTAL screens: %d  (+%d appendix ref cards)" %
          (total_screens, n_appendix))
    print("Output: %s (%.0f KB)" % (OUT, OUT.stat().st_size / 1024))
    assert total_screens >= 90, "expected ~96 screens, parsed %d" % total_screens
    assert len(domains) == 12
    print("OK")


# ────────────────────────────── template ─────────────────────────────────────
PAGE = r"""<!doctype html>
<html lang="ar" dir="rtl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>دليل المستخدم — UralCash ERP</title>
<style>
@font-face{{font-family:'Cairo';src:url(data:font/ttf;base64,{font_b64}) format('truetype');font-weight:400 700;font-display:swap;}}
:root{{
  --teal-900:#134657; --teal-600:#2B737F; --teal-400:#469CA5;
  --slate:#1E293B; --surface:#F8FAFC; --success:#22C55E; --warning:#F59E0B; --error:#EF4444;
  --ink:#1E293B; --ink-soft:#475569; --line:#E2E8F0; --card:#FFFFFF;
  --teal-tint:#EAF3F4; --warn-tint:#FEF6E7; --shadow:0 1px 2px rgba(15,42,54,.06),0 8px 24px rgba(15,42,54,.06);
  --sidebar-w:320px; --hero-h:132px;
}}
*{{box-sizing:border-box;}}
html,body{{margin:0;padding:0;}}
body{{font-family:'Cairo','Segoe UI',Tahoma,sans-serif;background:var(--surface);color:var(--ink);
  line-height:1.75;font-size:15px;-webkit-font-smoothing:antialiased;}}
a{{color:var(--teal-600);text-decoration:none;}}
a:hover{{text-decoration:underline;}}
code{{font-family:'Cairo',ui-monospace,Menlo,Consolas,monospace;background:var(--teal-tint);
  color:var(--teal-900);padding:.05em .4em;border-radius:5px;font-size:.9em;direction:ltr;
  unicode-bidi:embed;display:inline-block;}}
.xref{{color:var(--ink-soft);font-weight:600;}}
:focus-visible{{outline:2.5px solid var(--teal-400);outline-offset:2px;border-radius:4px;}}

/* ── hero ── */
.hero{{position:sticky;top:0;z-index:40;background:linear-gradient(135deg,var(--teal-900),var(--teal-600));
  color:#fff;padding:16px 26px;box-shadow:0 6px 22px rgba(19,70,87,.28);}}
.hero-top{{display:flex;align-items:center;gap:16px;flex-wrap:wrap;}}
.brand{{display:flex;align-items:baseline;gap:10px;}}
.brand .u{{font-size:26px;font-weight:700;letter-spacing:-.5px;}}
.brand .u span{{color:var(--teal-400);}}
.brand .tag{{font-size:13px;opacity:.85;font-weight:600;}}
.stats{{display:flex;gap:8px;margin-inline-start:auto;flex-wrap:wrap;}}
.stat{{background:rgba(255,255,255,.13);border:1px solid rgba(255,255,255,.16);border-radius:999px;
  padding:4px 13px;font-size:12.5px;font-weight:700;white-space:nowrap;}}
.stat b{{color:var(--teal-400);font-size:14px;}}
.search-wrap{{margin-top:12px;position:relative;max-width:640px;}}
.search-wrap .ic{{position:absolute;inset-inline-start:14px;top:50%;transform:translateY(-50%);
  opacity:.6;font-size:16px;pointer-events:none;}}
#search{{width:100%;border:0;border-radius:12px;padding:11px 42px;font-family:inherit;font-size:15px;
  background:#fff;color:var(--ink);box-shadow:0 4px 14px rgba(0,0,0,.14);}}
#search::placeholder{{color:#94A3B8;}}
.search-count{{position:absolute;inset-inline-end:14px;top:50%;transform:translateY(-50%);
  font-size:12px;color:var(--ink-soft);font-weight:700;pointer-events:none;}}
.menu-btn{{display:none;background:rgba(255,255,255,.15);border:0;color:#fff;font-size:20px;
  width:40px;height:40px;border-radius:10px;cursor:pointer;}}

/* ── layout: narrow list on the RIGHT (inline-start in RTL), wide content LEFT.
   grid-template-areas maps to the inline direction, so "side main" puts the
   sidebar at inline-start (right) unambiguously regardless of DOM order. ── */
.wrap{{display:grid;grid-template-columns:var(--sidebar-w) 1fr;
  grid-template-areas:"side main";align-items:start;}}
.sidebar{{grid-area:side;position:sticky;top:var(--hero-h);align-self:start;
  height:calc(100vh - var(--hero-h));overflow-y:auto;
  border-inline-end:1px solid var(--line);background:#fff;padding:14px 10px 60px;}}
.nav-group{{margin-bottom:2px;}}
.nav-head{{display:flex;align-items:center;gap:9px;width:100%;background:transparent;border:0;
  cursor:pointer;padding:9px 10px;border-radius:10px;font-family:inherit;font-size:14px;
  color:var(--slate);text-align:start;font-weight:700;}}
.nav-head:hover{{background:var(--teal-tint);}}
.nav-num{{background:var(--teal-900);color:#fff;font-size:11px;font-weight:700;min-width:24px;height:22px;
  display:inline-flex;align-items:center;justify-content:center;border-radius:6px;}}
.nav-title{{flex:1;line-height:1.4;}}
.nav-count{{font-size:11px;color:var(--ink-soft);background:var(--surface);border-radius:999px;
  padding:1px 8px;font-weight:700;}}
.nav-caret{{transition:transform .18s;color:var(--teal-600);font-size:17px;}}
.nav-head[aria-expanded="true"] .nav-caret{{transform:rotate(-90deg);}}
.nav-list{{list-style:none;margin:0;padding:0;max-height:0;overflow:hidden;transition:max-height .26s ease;}}
.nav-group.open .nav-list{{max-height:2400px;}}
.nav-screen{{display:block;padding:6px 12px 6px 34px;color:var(--ink-soft);font-size:13px;border-radius:8px;
  border-inline-start:2px solid transparent;margin:1px 6px;}}
.nav-screen:hover{{background:var(--teal-tint);color:var(--teal-900);text-decoration:none;}}
.nav-screen.active{{background:var(--teal-tint);color:var(--teal-900);border-inline-start-color:var(--teal-400);font-weight:700;}}

.content{{grid-area:main;padding:30px 40px 120px;max-width:1040px;}}
.domain{{scroll-margin-top:var(--hero-h);margin-bottom:30px;}}
.domain-head{{display:flex;align-items:center;gap:12px;padding-bottom:12px;margin-bottom:16px;
  border-bottom:2px solid var(--teal-tint);}}
.domain-num{{background:linear-gradient(135deg,var(--teal-900),var(--teal-400));color:#fff;font-weight:700;
  width:40px;height:40px;border-radius:11px;display:inline-flex;align-items:center;justify-content:center;
  font-size:15px;box-shadow:var(--shadow);}}
.domain-head h2{{margin:0;font-size:22px;color:var(--teal-900);flex:1;}}
.domain-count{{font-size:12.5px;color:var(--ink-soft);font-weight:700;}}
.domain-intro{{color:var(--ink-soft);margin:0 0 12px;font-size:14.5px;}}
.domain-warn{{background:var(--warn-tint);border-inline-start:4px solid var(--warning);border-radius:10px;
  padding:11px 15px;color:#7c5006;font-size:13.5px;margin-bottom:18px;font-weight:600;}}

/* ── screen card ── */
.screen{{background:var(--card);border:1px solid var(--line);border-radius:16px;box-shadow:var(--shadow);
  margin-bottom:18px;overflow:hidden;scroll-margin-top:calc(var(--hero-h) + 10px);}}
.screen-h{{display:flex;align-items:center;gap:10px;padding:15px 20px;
  background:linear-gradient(180deg,#fff,#fbfdfe);border-bottom:1px solid var(--line);}}
.screen-h h3{{margin:0;font-size:17px;color:var(--teal-900);flex:1;line-height:1.5;}}
.chip{{background:var(--slate);color:#cfe4e7;font-size:11.5px;}}
.copy{{background:transparent;border:0;cursor:pointer;font-size:15px;opacity:.5;padding:4px;border-radius:6px;}}
.copy:hover{{opacity:1;background:var(--teal-tint);}}
.copy.done{{opacity:1;}}
.facets{{padding:8px 20px 18px;}}
.facet{{border-inline-start:3px solid var(--teal-400);padding:8px 0 8px 0;margin-top:12px;}}
.facet-h{{display:flex;align-items:center;gap:8px;padding-inline-start:12px;margin-bottom:4px;}}
.facet-ic{{font-size:15px;}}
.facet-l{{font-weight:700;color:var(--teal-900);font-size:14px;}}
.facet-b{{padding-inline-start:12px;color:var(--ink);}}
.facet-b p{{margin:.35em 0;}}
.facet-b ul,.facet-b ol{{margin:.35em 0;padding-inline-start:22px;}}
.facet-b li{{margin:.28em 0;}}
.facet-b blockquote{{margin:.5em 0;padding:8px 13px;background:var(--surface);
  border-inline-start:3px solid var(--teal-600);border-radius:8px;color:var(--ink-soft);}}
.facet-purpose{{border-color:var(--teal-600);}}
.facet-access{{border-color:var(--slate);}} .facet-access .facet-l{{color:var(--slate);}}
.facet-elements{{border-color:var(--teal-400);}}
.facet-flow{{border-color:var(--teal-600);}}
.facet-warn{{border-color:var(--warning);background:var(--warn-tint);border-radius:0 10px 10px 0;}}
.facet-warn .facet-l{{color:#b45309;}}
.facet-related{{border-color:#94A3B8;}} .facet-related .facet-l{{color:var(--ink-soft);}}
/* numbered workflow -> connected step-flow diagram (نodes + path), animated
   once when scrolled into view via the .play class (see JS). --i = step index. */
ol.flow{{list-style:none;counter-reset:step;padding-inline-start:6px;position:relative;margin:.5em 0;}}
ol.flow>li{{counter-increment:step;position:relative;padding-inline-start:44px;
  padding-bottom:16px;margin:0;}}
ol.flow>li:last-child{{padding-bottom:2px;}}
/* the connector path from this node down to the next */
ol.flow>li:not(:last-child)::after{{content:'';position:absolute;inset-inline-start:16px;
  top:30px;bottom:0;width:2.5px;border-radius:2px;background:var(--teal-tint);
  transform-origin:top;}}
/* the step node */
ol.flow>li::before{{content:counter(step);position:absolute;inset-inline-start:4px;top:1px;
  width:28px;height:28px;background:#fff;border:2px solid var(--teal-400);color:var(--teal-900);
  border-radius:50%;font-size:12.5px;font-weight:700;display:flex;align-items:center;
  justify-content:center;z-index:1;box-shadow:0 0 0 4px var(--surface);}}
/* when the flow enters view: draw nodes + path in sequence, one ripple each */
ol.flow.play>li::before{{animation:nodePop .42s both calc(var(--i,0)*.11s),
  nodeRing 1s both calc(var(--i,0)*.11s + .18s);}}
ol.flow.play>li:not(:last-child)::after{{animation:pathGrow .4s ease both calc(var(--i,0)*.11s + .12s);}}
@keyframes nodePop{{from{{transform:scale(.15);opacity:0;}}
  60%{{transform:scale(1.12);}} to{{transform:scale(1);opacity:1;}}}}
@keyframes pathGrow{{from{{transform:scaleY(0);}} to{{transform:scaleY(1);}}}}
@keyframes nodeRing{{0%{{box-shadow:0 0 0 4px var(--surface),0 0 0 4px rgba(70,156,165,.55);}}
  70%{{box-shadow:0 0 0 4px var(--surface),0 0 0 12px rgba(70,156,165,0);}}
  100%{{box-shadow:0 0 0 4px var(--surface),0 0 0 12px rgba(70,156,165,0);}}}}
.facet-flow{{background:linear-gradient(180deg,rgba(43,115,127,.04),transparent);
  border-radius:0 10px 10px 0;padding-bottom:6px;}}

.facet-b h4.sub,.ap-body h4.sub{{margin:.8em 0 .3em;font-size:14px;color:var(--teal-600);}}
/* tables */
.tw{{overflow-x:auto;margin:.5em 0;border-radius:10px;border:1px solid var(--line);}}
.tw table{{border-collapse:collapse;width:100%;font-size:13px;min-width:340px;}}
.tw th{{background:var(--teal-900);color:#fff;padding:8px 11px;text-align:start;font-weight:700;white-space:nowrap;}}
.tw td{{padding:7px 11px;border-top:1px solid var(--line);vertical-align:top;}}
.tw tbody tr:nth-child(even){{background:var(--surface);}}
/* appendix (a '##' block with no facet structure — a reference table/summary) */
.screen.appendix{{border-style:dashed;border-color:var(--teal-tint);background:linear-gradient(180deg,#fff,#fbfdfe);}}
.ap-tag{{background:var(--teal-tint);color:var(--teal-600);font-size:11px;font-weight:700;
  padding:2px 9px;border-radius:6px;}}
.ap-body{{padding:6px 4px;}}
.ap-body p{{margin:.35em 0;}} .ap-body ul,.ap-body ol{{margin:.35em 0;padding-inline-start:22px;}}
.nav-screen.is-appendix{{color:#94A3B8;font-style:italic;}}
.empty{{display:none;text-align:center;padding:70px 20px;color:var(--ink-soft);}}
.empty.show{{display:block;}}
.hidden{{display:none !important;}}
.totop{{position:fixed;inset-inline-end:22px;bottom:22px;background:var(--teal-900);color:#fff;border:0;
  width:46px;height:46px;border-radius:50%;cursor:pointer;font-size:20px;box-shadow:0 6px 18px rgba(19,70,87,.4);
  opacity:0;pointer-events:none;transition:opacity .2s;z-index:30;}}
.totop.show{{opacity:1;pointer-events:auto;}}
.scrim{{display:none;}}

@media (max-width:860px){{
  :root{{--hero-h:150px;}}
  .wrap{{grid-template-columns:1fr;grid-template-areas:"main";}}
  .menu-btn{{display:block;}}
  .sidebar{{position:fixed;inset-block:0;inset-inline-end:0;top:0;height:100vh;width:300px;z-index:60;
    transform:translateX(100%);transition:transform .25s;box-shadow:-8px 0 30px rgba(0,0,0,.2);
    padding-top:18px;}}
  .sidebar.open{{transform:translateX(0);}}
  .scrim.show{{display:block;position:fixed;inset:0;background:rgba(15,42,54,.45);z-index:55;}}
  .content{{padding:22px 18px 120px;}}
}}
@media (prefers-reduced-motion:reduce){{*{{transition:none !important;animation:none !important;scroll-behavior:auto !important;}}}}
@media (prefers-color-scheme:dark){{
  :root{{--surface:#0F1E25;--ink:#E6EEF0;--ink-soft:#9DB2B8;--line:#22323A;--card:#152730;
    --teal-tint:#17323B;--warn-tint:#33270f;--shadow:0 1px 2px rgba(0,0,0,.4),0 8px 24px rgba(0,0,0,.35);}}
  .screen-h{{background:linear-gradient(180deg,#152730,#12222a);}}
  #search{{background:#1b2f38;color:#E6EEF0;}} .search-count{{color:#9DB2B8;}}
  code{{background:#17323B;color:#8fd0d8;}}
  .domain-warn,.facet-warn{{color:#f3c98a;}}
}}
html{{scroll-behavior:smooth;}}
</style>
</head>
<body>
<header class="hero">
  <div class="hero-top">
    <button class="menu-btn" id="menuBtn" aria-label="القائمة">☰</button>
    <div class="brand"><div class="u">Ural<span>Cash</span></div>
      <div class="tag">دليل المستخدم — كتالوج الشاشات</div></div>
    <div class="stats">
      <span class="stat"><b>{total}</b> شاشة</span>
      <span class="stat"><b>{ndomains}</b> أقسام</span>
      <span class="stat">🟢 جاهز للنشر</span>
    </div>
  </div>
  <div class="search-wrap">
    <span class="ic">🔍</span>
    <input id="search" type="search" placeholder="ابحث عن شاشة… (الاسم، الوظيفة، اسم الملف)"
      autocomplete="off" aria-label="بحث">
    <span class="search-count" id="scount"></span>
  </div>
</header>
<div class="scrim" id="scrim"></div>
<div class="wrap">
  <main class="content">
    {main}
    <div class="empty" id="empty">لا توجد شاشات مطابقة لبحثك.</div>
  </main>
  <nav class="sidebar" id="sidebar" aria-label="فهرس الأقسام">
    {sidebar}
  </nav>
</div>
<button class="totop" id="totop" aria-label="أعلى الصفحة">↑</button>
<script>
(function(){{
  var groups=[].slice.call(document.querySelectorAll('.nav-group'));
  var screens=[].slice.call(document.querySelectorAll('.screen'));
  var navScreens=[].slice.call(document.querySelectorAll('.nav-screen'));
  var domains=[].slice.call(document.querySelectorAll('.domain'));
  var sidebar=document.getElementById('sidebar');
  var scrim=document.getElementById('scrim');

  function openGroup(g,on){{g.classList.toggle('open',on);
    g.querySelector('.nav-head').setAttribute('aria-expanded',on?'true':'false');}}
  groups.forEach(function(g){{
    g.querySelector('.nav-head').addEventListener('click',function(){{
      openGroup(g,!g.classList.contains('open'));}});
  }});

  // ── search ──
  var search=document.getElementById('search'),scount=document.getElementById('scount'),
      empty=document.getElementById('empty'),t;
  function doFilter(){{
    var q=search.value.trim().toLowerCase();
    var shown=0;
    var perDomain={{}};
    screens.forEach(function(s){{
      var ok=!q||s.getAttribute('data-hay').indexOf(q)>=0||
             s.querySelector('h3') && s.querySelector('h3').textContent.toLowerCase().indexOf(q)>=0;
      s.classList.toggle('hidden',!ok);
      var dom=s.closest('.domain').getAttribute('data-domain');
      if(ok){{shown++;perDomain[dom]=(perDomain[dom]||0)+1;}}
    }});
    domains.forEach(function(d){{
      var dom=d.getAttribute('data-domain');
      d.classList.toggle('hidden',!!q && !perDomain[dom]);
    }});
    navScreens.forEach(function(a){{
      var hay=a.getAttribute('data-hay')||'';
      var txt=a.textContent.toLowerCase();
      var ok=!q||hay.indexOf(q)>=0||txt.indexOf(q)>=0;
      a.parentElement.classList.toggle('hidden',!ok);
    }});
    groups.forEach(function(g){{
      var vis=g.querySelectorAll('.nav-list li:not(.hidden)').length;
      var hasList=g.querySelector('.nav-list li');
      if(hasList) g.classList.toggle('hidden',!!q&&vis===0);
      if(q&&vis>0) openGroup(g,true);
    }});
    empty.classList.toggle('show',shown===0);
    scount.textContent=q?(shown+' نتيجة'):'';
  }}
  search.addEventListener('input',function(){{clearTimeout(t);t=setTimeout(doFilter,110);}});
  search.addEventListener('keydown',function(e){{if(e.key==='Escape'){{search.value='';doFilter();}}}});

  // ── copy link ──
  document.querySelectorAll('.copy').forEach(function(b){{
    b.addEventListener('click',function(){{
      var url=location.href.split('#')[0]+'#'+b.getAttribute('data-id');
      var done=function(){{b.textContent='✓';b.classList.add('done');
        setTimeout(function(){{b.textContent='🔗';b.classList.remove('done');}},1200);}};
      if(navigator.clipboard){{navigator.clipboard.writeText(url).then(done,done);}}else{{done();}}
      history.replaceState(null,'','#'+b.getAttribute('data-id'));
    }});
  }});

  // ── deep-link on load: expand the target's domain ──
  function expandFor(hash){{
    if(!hash)return;
    // ids start with a digit ("01-s01-…") -> querySelector('#01..') is an
    // invalid CSS selector and throws; getElementById handles any id.
    var el=document.getElementById(hash.replace(/^#/,''));
    if(!el)return;
    var dom=el.closest('.domain');
    if(dom){{var g=groups.filter(function(x){{
      return x.getAttribute('data-domain')===dom.getAttribute('data-domain');}})[0];
      if(g)openGroup(g,true);}}
    setTimeout(function(){{el.scrollIntoView();}},60);
  }}
  navScreens.forEach(function(a){{
    a.addEventListener('click',function(){{
      if(window.matchMedia('(max-width:860px)').matches) closeDrawer();
    }});
  }});
  if(location.hash) expandFor(location.hash);
  else if(groups[0]) openGroup(groups[0],true);
  window.addEventListener('hashchange',function(){{expandFor(location.hash);}});

  // ── scroll spy ──
  var spy;
  window.addEventListener('scroll',function(){{
    clearTimeout(spy);
    spy=setTimeout(function(){{
      var top=null,y=180;
      screens.forEach(function(s){{
        if(s.classList.contains('hidden'))return;
        var r=s.getBoundingClientRect();
        if(r.top<=y) top=s.id;
      }});
      navScreens.forEach(function(a){{
        a.classList.toggle('active',a.getAttribute('href')==='#'+top);
      }});
      totop.classList.toggle('show',window.scrollY>500);
    }},80);
  }});

  // ── animated workflow step-flows: number each step (--i) then draw the
  //    nodes + connecting path in sequence the first time it scrolls into view ──
  var flows=[].slice.call(document.querySelectorAll('ol.flow'));
  flows.forEach(function(f){{
    [].slice.call(f.children).forEach(function(li,i){{li.style.setProperty('--i',i);}});
  }});
  var reduceMotion=window.matchMedia('(prefers-reduced-motion:reduce)').matches;
  if(!reduceMotion && 'IntersectionObserver' in window){{
    var fio=new IntersectionObserver(function(es){{
      es.forEach(function(e){{
        if(e.isIntersecting){{e.target.classList.add('play');fio.unobserve(e.target);}}
      }});
    }},{{threshold:0.2}});
    flows.forEach(function(f){{fio.observe(f);}});
  }}

  // ── mobile drawer ──
  var menuBtn=document.getElementById('menuBtn'),totop=document.getElementById('totop');
  function closeDrawer(){{sidebar.classList.remove('open');scrim.classList.remove('show');}}
  if(menuBtn)menuBtn.addEventListener('click',function(){{
    sidebar.classList.toggle('open');scrim.classList.toggle('show');}});
  scrim.addEventListener('click',closeDrawer);
  totop.addEventListener('click',function(){{window.scrollTo({{top:0,behavior:'smooth'}});}});
}})();
</script>
</body>
</html>
"""

if __name__ == "__main__":
    build()
