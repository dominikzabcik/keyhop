# Builds a Coss Blue window artboard from KB-Home's shell: the sidebar, the inset panel and the tokens stay,
# the header and the panel body come from tools/kb/<page>.html, extra values from tools/kb/<page>.js.
#   python3 tools/kb_page.py limits "#limits" 1500 "Limits"
import re, sys, os
page, href, height, title = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
here = os.path.dirname(os.path.abspath(__file__))
proj = os.path.join(here, '..', 'project')
src = open(os.path.join(proj, 'KB-Home.dc.html')).read()
frag = open(os.path.join(here, 'kb', page + '.html')).read()
js = open(os.path.join(here, 'kb', page + '.js')).read()

CUR = ' aria-current="page"'
CUR_STYLE = '; background: rgba(255,255,255,0.07); color: #FFFFFF; font-weight: 500"'
nav_start = src.index('<nav aria-label="Places"')
nav_end = src.index('</nav>', nav_start)
nav = src[nav_start:nav_end].replace(CUR, '').replace(CUR_STYLE, '"')
if href != '#home':
    nav = re.sub(r'(<a href="' + re.escape(href) + r'")( style="[^"]*)"', lambda m: m.group(1) + CUR + m.group(2) + CUR_STYLE, nav, count=1)
else:
    nav = src[nav_start:nav_end]
s = src[:nav_start] + nav + src[nav_end:]

# panel: keep the opening div of the inset panel, replace header + body
p_open = s.index('<div style="position: relative; flex: 1; min-width: 0; margin: 10px')
p_body = s.index('<header', p_open)
end = s.index('</x-dc>')
tail = '  </div>\n</div>\n'
s = s[:p_body] + frag.rstrip() + '\n' + tail + s[end:]

s = s.replace('width: 1440px; height: 960px; overflow: hidden', 'width: 1440px; height: %dpx; overflow: hidden' % height, 1)
s = s.replace('"$preview":{"width":1440,"height":960}', '"$preview":{"width":1440,"height":%d}' % height, 1)
s = re.sub(r'<title>[^<]*</title>', '<title>Keyhop %s — Coss Blue</title>' % title, s, 1)
s = s.replace('    return { models: models,', js.rstrip() + '\n    return { ...extra, models: models,', 1)
out = os.path.join(proj, 'KB-%s.dc.html' % page.capitalize())
open(out, 'w').write(s)
print(out)
