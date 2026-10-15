# Tool marks for the Coss Blue boards. Data: tools/kb/tool-icons.json (Simple Icons CC0, Lobe Icons MIT,
# monograms where a tool has no free mark). In a template, {{ICON:<expr>:<px>}} becomes an inline SVG
# reading <expr>.d, .d2 (a 35% shade) and .t (a monogram); in the script, ic('claude') gives that object.
import json, os, re
here = os.path.dirname(os.path.abspath(__file__))
DATA = json.load(open(os.path.join(here, 'kb', 'tool-icons.json')))
JS = ('    const TOOL_MARKS = ' + json.dumps({k: {f: v[f] for f in ('d', 'd2', 't', 'fs') if f in v} for k, v in DATA.items()}, ensure_ascii=False) + ';\n'
      "    const ic = (k) => Object.assign({ d: '', d2: '', t: '', fs: 14 }, TOOL_MARKS[k] || {});\n")

def svg(expr, px):
    return ('<svg width="%s" height="%s" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true" style="flex: none; display: block">'
            '<path d="{{%s.d}}"></path><path d="{{%s.d2}}" opacity=".35"></path>'
            '<text x="12" y="17" text-anchor="middle" font-size="{{%s.fs}}" font-weight="700" font-family="Geist Mono, ui-monospace, monospace">{{%s.t}}</text></svg>') % (px, px, expr, expr, expr, expr)

def expand(html):
    return re.sub(r'\{\{ICON:([\w.]+):(\d+)\}\}', lambda m: svg(m.group(1), m.group(2)), html)
