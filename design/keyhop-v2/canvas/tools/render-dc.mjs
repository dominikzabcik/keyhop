// Renders a canvas .dc.html artboard to a PNG: expands {{holes}}, <sc-for>, <sc-if> with renderVals().
import fs from 'node:fs';
import { createRequire } from 'node:module';
const require = createRequire(new URL('../../../../package.json', import.meta.url).pathname);
const { chromium } = require('playwright');
const [file, out, propsJson] = process.argv.slice(2);
const src = fs.readFileSync(file, 'utf8');
const xdc = src.split('<x-dc>')[1].split('</x-dc>')[0];
const helmet = (xdc.match(/<helmet>([\s\S]*?)<\/helmet>/) || [, ''])[1];
const body = xdc.replace(/<helmet>[\s\S]*?<\/helmet>/, '');
const script = src.match(/<script type="text\/x-dc" data-dc-script[^>]*>([\s\S]*?)<\/script>/)[1];
const meta = JSON.parse(src.match(/data-props='([^']*)'/)[1].replace(/&amp;/g, '&').replace(/&#39;/g, "'"));
const props = {};
for (const [k, v] of Object.entries(meta)) if (v && 'default' in v) props[k] = v.default;
Object.assign(props, propsJson ? JSON.parse(propsJson) : {});
const w = meta.$preview?.width || 1440, h = meta.$preview?.height || 960;
const html = `<!doctype html><html><head><meta charset="utf-8">${helmet}</head><body><template id="t">${body}</template></body></html>`;
const browser = await chromium.launch({ executablePath: '/home/dev/.cache/ms-playwright/chromium-1243/chrome-linux64/chrome', args: ['--no-sandbox'] });
const page = await browser.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: Number(process.env.SCALE || 1) });
await page.setContent(html, { waitUntil: 'networkidle' });
const err = await page.evaluate(({ script, props }) => {
  try {
    const C = new Function('class DCLogic{constructor(p){this.props=p||{};this.state={}} setState(){} forceUpdate(){}}\n' + script + '\nreturn Component;')();
    const inst = new C(props); inst.state = inst.state || {};
    const vals = inst.renderVals();
    const get = (sc, p) => { p = p.trim(); if (p === 'true') return true; if (p === 'false') return false; return p.split('.').reduce((o, k) => (o == null ? undefined : o[k]), sc); };
    const whole = /^\{\{\s*([^}]+?)\s*\}\}$/;
    const interp = (s, sc) => { const m = s.match(whole); if (m) return get(sc, m[1]); return s.replace(/\{\{\s*([^}]+?)\s*\}\}/g, (_, p) => { const v = get(sc, p); return v == null ? '' : String(v); }); };
    const render = (n, sc) => {
      if (n.nodeType === 3) { const v = interp(n.textContent, sc); return [document.createTextNode(v == null ? '' : String(v))]; }
      if (n.nodeType !== 1) return [];
      const tag = n.localName;
      if (tag === 'sc-for') {
        const list = get(sc, n.getAttribute('list').replace(/[{}]/g, '')) || []; const as = n.getAttribute('as');
        const outN = [];
        list.forEach((it, i) => { const s2 = Object.create(sc); s2[as] = it; s2.$index = i; n.childNodes.forEach((ch) => outN.push(...render(ch, s2))); });
        return outN;
      }
      if (tag === 'sc-if') { const v = get(sc, n.getAttribute('value').replace(/[{}]/g, '')); const o = []; if (v) n.childNodes.forEach((ch) => o.push(...render(ch, sc))); return o; }
      const el = n.cloneNode(false);
      for (const a of [...el.attributes]) {
        if (/^on/i.test(a.name)) { el.removeAttribute(a.name); continue; }
        if (a.value.includes('{{')) { const v = interp(a.value, sc); if (v === false || v == null) el.removeAttribute(a.name); else el.setAttribute(a.name, String(v)); }
      }
      if (tag === 'input' && el.hasAttribute('value')) el.value = el.getAttribute('value');
      n.childNodes.forEach((ch) => render(ch, sc).forEach((c) => el.appendChild(c)));
      return [el];
    };
    const t = document.getElementById('t').content;
    t.childNodes.forEach((ch) => render(ch, vals).forEach((c) => document.body.appendChild(c)));
    return null;
  } catch (e) { return String(e && e.stack || e); }
}, { script, props });
if (err) { console.error('RENDER ERROR', err); }
await page.waitForTimeout(2600);
if (process.env.HTML) fs.writeFileSync(process.env.HTML, (await page.content()).replace(/<template id="t">[\s\S]*?<\/template>/, ''));
if (process.env.CLIP) { const [x, y, cw, ch] = process.env.CLIP.split(',').map(Number); await page.screenshot({ path: out, clip: { x, y, width: cw, height: ch } }); }
else await page.screenshot({ path: out, fullPage: true });
await browser.close();
console.log('ok', out, w + 'x' + h);
