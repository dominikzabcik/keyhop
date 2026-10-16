    const C = 2 * Math.PI * 22;
    const rows = [['codex', 'Codex', 'me@personal.dev', 7], ['claude', 'Claude Code', 'Personal', 19], ['cursor', 'Cursor', 'me@personal.dev', 38], ['copilot', 'Copilot', 'Personal', 53], ['gemini', 'Gemini CLI', 'me@personal.dev', 72], ['windsurf', 'Windsurf', 'me@windsurf.dev', 67]]
      .map((r) => {
        const out = r[3] <= 15, low = r[3] <= 40;
        return { ic: ic(r[0]), tool: r[1], login: r[2], pct: r[3] + '%', w: r[3] + '%', flex: String(Math.max(r[3], 4)),
          bar: out ? c.red : low ? c.orange : 'rgba(255,255,255,0.78)', ink: out ? c.redInk : c.label,
          seg: out ? c.red : low ? c.orange : 'rgba(255,255,255,0.55)', ringInk: out ? c.red : low ? c.orange : '#E5E5E5',
          dash: (r[3] / 100 * C).toFixed(1) + ' ' + C.toFixed(1),
          tileBg: out ? rgba(c.red, 0.07) : 'rgba(255,255,255,0.025)', tileRing: out ? 'inset 0 0 0 1px ' + rgba(c.red, 0.28) : 'inset 0 0 0 1px rgba(255,255,255,0.06)',
          hasHop: r[0] === 'claude', rowBg: r[0] === 'claude' ? 'rgba(255,255,255,0.03)' : 'transparent' };
      });
    const menu = [['Open', '⌘O'], ['Refresh', '⌘R'], ['Quit', '⌘Q']].map((m, i) => ({ short: m[0], key: m[1], line: i ? 'inset 1px 0 0 rgba(255,255,255,0.07)' : 'none' }));
    let seed = 11;
    const rnd = () => { seed = (seed * 9301 + 49297) % 233280; return seed / 233280; };
    const stars = Array.from({ length: 26 }, () => ({ x: Math.round(rnd() * 360), y: Math.round(rnd() * 110), r: rnd() > 0.85 ? 2 : 1.2 }));
    const extra = { rows: rows, menu: menu, stars: stars, codexIc: ic('codex'), claudeIc: ic('claude') };
