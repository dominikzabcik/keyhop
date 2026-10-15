import fs from 'node:fs';
const src = fs.readFileSync(process.argv[2], 'utf8');
const m = src.match(/<script type="text\/x-dc" data-dc-script[^>]*>([\s\S]*?)<\/script>/);
const props = JSON.parse(src.match(/data-props='([^']*)'/)[1].replace(/&amp;/g,'&'));
const C = new Function('class DCLogic{constructor(p){this.props=p||{};this.state={}} setState(){}}\n' + m[1] + '\nreturn Component;')();
const loops = [...src.matchAll(/as="(\w+)"/g)].map(x => x[1]).concat(['$index']);
for (const theme of ['night', 'day', 'light', 'dark']) {
  const v = new C({ theme, appearance: theme }).renderVals();
  const roots = [...src.split('<x-dc>')[1].split('</x-dc>')[0].matchAll(/\{\{\s*([\w$]+)/g)].map(x => x[1]);
  const missing = [...new Set(roots.filter(r => !(r in v) && !loops.includes(r) && !['true','false'].includes(r)))];
  console.log(process.argv[2].split('/').pop(), theme, 'ok', 'missing roots:', missing.length ? missing : 'none');
}
const bad = [...src.matchAll(/\{\{\s*([^}]+?)\s*\}\}/g)].map(x => x[1]).filter(h => !/^[\w$.]+$/.test(h));
console.log('non-dotted holes:', bad.length ? bad : 'none', '| tweaks:', Object.keys(props).join(','));
