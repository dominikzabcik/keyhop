# Builds a standalone Coss Blue artboard (no window shell) from tools/kb/<name>.html and <name>.js,
# with KB-Home's helmet (fonts, classes, motion) and its tokens. {{PET:<px>}} drops in the pet.
#   python3 tools/kb_board.py menu 560 760 "Menu"
import re, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kb_icons
name, w, h, title = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
here = os.path.dirname(os.path.abspath(__file__))
proj = os.path.join(here, '..', 'project')
home = open(os.path.join(proj, 'KB-Home.dc.html')).read()
helmet = re.search(r'<helmet>[\s\S]*?</helmet>', home).group(0)
pet = re.search(r'<svg class="pet"[\s\S]*?</svg>', home).group(0)
body = kb_icons.expand(open(os.path.join(here, 'kb', name + '.html')).read())
js = open(os.path.join(here, 'kb', name + '.js')).read()
# {{PET:<px>}} hops; {{PET:<px>:still}} stands, for small frames that would clip the hop
body = re.sub(r'\{\{PET:(\d+)(:still)?\}\}', lambda m: pet.replace('width="72" height="72"', 'width="%s" height="%s"' % (m.group(1), m.group(1))).replace('class="pet" ', '' if m.group(2) else 'class="pet" '), body)
props = '{"$preview":{"width":%d,"height":%d}}' % (w, h)
out = f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Keyhop {title} — Coss Blue</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
{helmet}
{body.rstrip()}
</x-dc>
<script type="text/x-dc" data-dc-script data-props='{props}'>
class Component extends DCLogic {{
  renderVals() {{
    const accent = '#60A5FA';
    const rgba = (h, a) => {{ const n = parseInt(String(h).replace('#', '').slice(0, 6), 16); return 'rgba(' + ((n >> 16) & 255) + ',' + ((n >> 8) & 255) + ',' + (n & 255) + ',' + a + ')'; }};
    const sys = {{ green: '#34D399', orange: '#F59E0B', red: '#FB414A' }};
    const c = Object.assign({{ label: '#F5F5F5', secondary: '#A3A3A3', tertiary: '#737373', track: 'rgba(255,255,255,0.08)', accent: accent, accentInk: '#0A1628', redInk: '#FF8A82' }}, sys);
{kb_icons.JS.rstrip()}
{js.rstrip()}
    return Object.assign({{ c: c }}, extra);
  }}
}}
</script>
</body>
</html>
'''
p = os.path.join(proj, 'KB-%s.dc.html' % name.capitalize())
open(p, 'w').write(out)
print(p)
