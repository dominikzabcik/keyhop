# Writes the devl.dev (coss-ui) takes on S1 Crisp: neutral #161616 grounds, 10% white borders,
# radius 10/12, tracked uppercase labels, and optionally a monospace body like devl.dev.
#   python3 tools/devl.py <mono|ember|blue|iris> project/S1-Home.dc.html project/S1-Components.dc.html
import re, sys

def hx(h): h = h.lstrip('#'); return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))
def tohex(c): return '#%02X%02X%02X' % tuple(max(0, min(255, round(v))) for v in c)
def mix(a, b, w): a, b = hx(a), hx(b); return tohex([a[i]*(1-w) + b[i]*w for i in range(3)])

V = sys.argv[1]
# name, accent, accent ink, monospace body
cfg = {
    'mono':  ('Coss Mono',  '#F5F5F5', '#171717', True),
    'ember': ('Coss Ember', '#FF8A3D', '#1A0E05', True),
    'blue':  ('Coss Blue',  '#60A5FA', '#0A1628', False),
    'iris':  ('Coss Iris',  '#8B7DFF', '#0B0B1A', False),
}[V]
title, acc, accInk, mono = cfg

# S1 grounds and inks -> coss-ui dark neutrals (background = neutral-950 + 5% white = #161616)
grounds = dict(zip(
    '0C0C16 0A0A13 0E0E1C 12121F 171726 232336 25253A 2B2B40 15152A 10101F 0B0B1A 09090F FAFAFF E4E4F0 A9A9C2 7C7C96 5A5A70'.split(),
    '111111 161616 13151A 1A1A1A 1F1F1F 262626 2A2A2A 2E2E2E 1C1F26 171A20 111111 0E0E0E F5F5F5 E5E5E5 A3A3A3 737373 525252'.split()))
if V == 'mono':  # white primary: tool shades go grey
    amap = {'8B7DFF': '#F5F5F5', 'C9C1FF': '#FAFAFA', 'B4A9FF': '#E5E5E5', 'A99DFF': '#D4D4D4', '9B8FFF': '#D4D4D4',
            '6F62E0': '#A3A3A3', '5549B8': '#737373', '3F3690': '#525252'}
else:
    amap = {'8B7DFF': acc, 'A99DFF': mix(acc, '#FFFFFF', .2), '9B8FFF': mix(acc, '#FFFFFF', .12), 'B4A9FF': mix(acc, '#FFFFFF', .3),
            'C9C1FF': mix(acc, '#FFFFFF', .45), '6F62E0': mix(acc, '#000000', .2), '5549B8': mix(acc, '#000000', .36), '3F3690': mix(acc, '#000000', .52)}
# status colours from coss-ui: amber-500, red-500 lifted, emerald-400
status = {'FF9F0A': 'F59E0B', 'F5A524': 'F59E0B', 'FF453A': 'FB414A', '8FE3BC': '34D399', '30D158': '34D399'}
if V == 'ember': status.update({'FF9F0A': 'FACC15', 'F5A524': 'FACC15'})
m = {k.upper(): v.lstrip('#').upper() for k, v in grounds.items()}
m.update({k.upper(): v.lstrip('#').upper() for k, v in amap.items()})
m.update(status)

MONO = "'Geist Mono', ui-monospace, 'SF Mono', Menlo, monospace"
SANS = "'Geist', system-ui, sans-serif"
LAB = ("font-family:" + MONO + "!important;text-transform:uppercase;letter-spacing:.16em;"
       "font-size:11px!important;font-weight:500!important;color:#A3A3A3!important")
css = """
.glass{background:#1A1A1A;box-shadow:inset 0 0 0 1px rgba(255,255,255,.10);border-radius:12px}
.well{background:rgba(255,255,255,.03);box-shadow:inset 0 0 0 1px rgba(255,255,255,.08);border-radius:10px}
.card:hover{box-shadow:inset 0 0 0 1px rgba(255,255,255,.18)}
h2[id$="-h"]:not(#total-h){%(lab)s}
.lab{%(lab)s}
.sans{font-family:%(sans)s!important}
""" % {'lab': LAB, 'sans': SANS}
if mono:
    css += "h1,h2,.sans{font-family:%s!important}\n" % SANS

for f in sys.argv[2:]:
    s = open(f).read()
    # dark ink on the accent (button text, the workspace mark), set before the grounds are remapped
    s = s.replace("btnInk: '#0C0C16'", "btnInk: '%s'" % accInk)
    s = s.replace('color: #0C0C16; font-size: 12px; font-weight: 600">Hop', 'color: %s; font-size: 12px; font-weight: 600">Hop' % accInk)
    if V == 'mono':  # a white primary needs a dark knob and a dark Hop on the white bubble
        s = s.replace('background: {{c.accent}}; color: #0C0C16; font-size: 12px; font-weight: 600">Hop', 'background: #171717; color: #F5F5F5; font-size: 12px; font-weight: 600">Hop')
        s = s.replace('background: #FAFAFF; transition: left .15s ease', 'background: {{s.knob}}; transition: left .15s ease')
        s = s.replace("x: sw[k] ? '18px' : '2px',", "x: sw[k] ? '18px' : '2px', knob: sw[k] ? '#171717' : '#F5F5F5',")
    s = s.replace('One violet for actions', {'mono': 'White for actions', 'ember': 'The pet\'s orange for actions', 'blue': 'One blue for actions', 'iris': 'One violet for actions'}[V])
    s = s.replace('''<h1 style="margin: 0; font-family: 'Instrument Serif', Georgia, serif; font-weight: 400; font-size: 44px; line-height: 44px; letter-spacing: -0.02em">Crisp components</h1>''',
                  '<h1 class="sans" style="margin: 0; font-weight: 500; font-size: 40px; line-height: 44px; letter-spacing: -0.03em">' + title + ' components</h1>')
    s = s.replace('radius 6 (cards 8)', 'radius 10 (cards 12)')
    s = s.replace('<span style="font-size: 30px; line-height: 34px; font-weight: 600; letter-spacing: -0.03em">', '<span class="sans" style="font-size: 30px; line-height: 34px; font-weight: 500; letter-spacing: -0.03em">')
    s = s.replace('background: #8B7DFF; color: #0B0B1A', 'background: %s; color: %s' % (acc, accInk))
    s = re.sub(r'#([0-9A-Fa-f]{6})\b', lambda x: '#' + m.get(x.group(1).upper(), x.group(1)), s)
    r, g, b = hx(acc if V != 'mono' else '#F5F5F5')
    s = re.sub(r'rgba\(139,\s*125,\s*255,', 'rgba(%d,%d,%d,' % (r, g, b), s)
    s = re.sub(r'rgba\(10,\s*10,\s*19,', 'rgba(22,22,22,', s)
    s = re.sub(r'rgba\(255,\s*159,\s*10,', 'rgba(245,158,11,' if V != 'ember' else 'rgba(250,204,21,', s)
    s = re.sub(r'rgba\(255,\s*69,\s*58,', 'rgba(251,65,74,', s)
    s = re.sub(r'rgba\(48,\s*209,\s*88,', 'rgba(52,211,153,', s)
    # fonts
    s = s.replace('family=Geist:wght@400;500;600;700;800', 'family=Geist:wght@400;500;600;700;800&amp;family=Geist+Mono:wght@400;500;600')
    if mono:
        s = s.replace("font-family: 'Geist', system-ui, sans-serif; font-size: 13px", "font-family: " + MONO.replace("'", "'") + "; font-size: 12.5px")
        s = s.replace("body{margin:0;font-family:'Geist',system-ui,sans-serif", "body{margin:0;font-family:" + MONO)
    # radius: the inset panel and range control
    s = s.replace('margin: 8px; display: flex; flex-direction: column; border-radius: 8px', 'margin: 8px; display: flex; flex-direction: column; border-radius: 12px')
    # the serif card title becomes an eyebrow + sans title, devl.dev's page heading
    s = re.sub(r'<h2 id="total-h" style="[^"]*">([^<]*)</h2>',
               r'<span style="display: flex; flex-direction: column; gap: 6px"><span class="lab">Tue, Oct 13 · Week</span>'
               r'<h2 id="total-h" class="sans" style="margin: 0; font-weight: 500; font-size: 26px; line-height: 30px; letter-spacing: -0.02em">\1</h2></span>', s)
    # sidebar group labels and big numbers
    s = s.replace('font-size: 12px; font-weight: 500; color: #737373">', 'font-size: 12px; font-weight: 500; color: #737373" class="lab">')
    s = s.replace('font-size: 12px; font-weight: 500; color: #737373; justify-content: space-between">', 'font-size: 12px; font-weight: 500; color: #737373; justify-content: space-between" class="lab">')
    s = s.replace('<span style="font-size: 60px; line-height: 56px; font-weight: 600; letter-spacing: -0.035em">',
                  '<span class="sans" style="font-size: 60px; line-height: 56px; font-weight: 500; letter-spacing: -0.04em">')
    s = s.replace('<span style="font-size: 20px; line-height: 24px; font-weight: 600;', '<span class="sans" style="font-size: 20px; line-height: 24px; font-weight: 500;')
    s = s.replace('gap: 7px; font-size: 18px; line-height: 22px; font-weight: 600">', 'gap: 7px; font-size: 18px; line-height: 22px; font-weight: 500" class="sans">')
    s = s.replace('</style>\n</helmet>', css + '</style>\n</helmet>', 1)
    out = f.replace('S1-', 'K-' + V + '-')
    s = re.sub(r'<title>Keyhop ([^<]*?) — Crisp', r'<title>Keyhop \1 — ' + title, s, 1)
    open(out, 'w').write(s)
    print(out)
