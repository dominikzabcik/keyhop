import re, sys
P = sys.argv[1]
def hx(h): h=h.lstrip('#'); return tuple(int(h[i:i+2],16) for i in (0,2,4))
def tohex(c): return '#%02X%02X%02X' % tuple(max(0,min(255,round(v))) for v in c)
def mix(a,b,w): a,b=hx(a),hx(b); return tohex([a[i]*(1-w)+b[i]*w for i in range(3)])
fam = {
 'iris': None,
 'zinc': dict(zip('0C0C16 0A0A13 0E0E1C 12121F 171726 232336 25253A 2B2B40 15152A 10101F 0B0B1A 09090F FAFAFF E4E4F0 A9A9C2 7C7C96 5A5A70'.split(),
              '0B0B0D 09090B 111114 131316 1A1A1E 26262B 28282E 2E2E34 18181C 121215 0B0B0D 09090B FAFAFA E4E4E7 A1A1AA 71717A 52525B'.split())),
 'stone': dict(zip('0C0C16 0A0A13 0E0E1C 12121F 171726 232336 25253A 2B2B40 15152A 10101F 0B0B1A 09090F FAFAFF E4E4F0 A9A9C2 7C7C96 5A5A70'.split(),
              '0D0B0A 0A0908 14110F 161311 1D1916 2A2521 2C2723 322C27 1B1714 13100E 0D0B0A 0A0908 FAF8F5 E9E4DE ABA39A 7F776F 5C554F'.split())),
 'slate': dict(zip('0C0C16 0A0A13 0E0E1C 12121F 171726 232336 25253A 2B2B40 15152A 10101F 0B0B1A 09090F FAFAFF E4E4F0 A9A9C2 7C7C96 5A5A70'.split(),
              '0A0D12 080B10 0E131B 111620 161C27 212937 232C3A 293344 141B27 0F151F 0A0D12 080B10 F8FAFC E2E8F0 94A3B8 64748B 475569'.split())),
}
pal = {'iris': ('iris', '#8B7DFF'), 'graphite': ('zinc', '#E4E4E7'), 'emerald': ('zinc', '#34D399'), 'ember': ('stone', '#FF8A3D'), 'cobalt': ('slate', '#4C8DFF')}[P]
grounds = fam[pal[0]]; acc = pal[1]
amap = {} if P == 'iris' else {
 '8B7DFF': acc, 'A99DFF': mix(acc,'#FFFFFF',.2), '9B8FFF': mix(acc,'#FFFFFF',.12), 'B4A9FF': mix(acc,'#FFFFFF',.3), 'C9C1FF': mix(acc,'#FFFFFF',.45),
 '6F62E0': mix(acc,'#000000',.2), '5549B8': mix(acc,'#000000',.36), '3F3690': mix(acc,'#000000',.52)}
if P == 'graphite':
    amap.update({'A99DFF': '#C4C4C9', '9B8FFF': '#D4D4D8', 'B4A9FF': '#F4F4F5', 'C9C1FF': '#FAFAFA', '6F62E0': '#A1A1AA', '5549B8': '#71717A', '3F3690': '#52525B'})
m = {}
if grounds: m.update({k.upper(): v for k, v in grounds.items()})
m.update({k.upper(): v.lstrip('#').upper() for k, v in amap.items()})
if P == 'ember': m.update({'FF9F0A': 'F5C542', 'F5A524': 'F2C94C'})
for f in sys.argv[2:]:
    s = open(f).read()
    s = re.sub(r'#([0-9A-Fa-f]{6})\b', lambda x: '#' + m.get(x.group(1).upper(), x.group(1)), s)
    if P != 'iris':
        r,g,b = hx(acc); s = re.sub(r'rgba\(139,\s*125,\s*255,', 'rgba(%d,%d,%d,' % (r,g,b), s)
        g2 = hx('#' + (grounds or {}).get('0A0A13', '0A0A13')); s = re.sub(r'rgba\(10,\s*10,\s*19,', 'rgba(%d,%d,%d,' % g2, s)
        if P == 'ember': s = re.sub(r'rgba\(255,\s*159,\s*10,', 'rgba(245,197,66,', s)
    out = f.replace('S1-', 'P-' + P + '-')
    s = s.replace('<title>Keyhop', '<title>Keyhop ' + P.capitalize() + ' —', 1)
    open(out, 'w').write(s)
    print(out)
