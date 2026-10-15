    const rows = [['Cx', 'Codex', 'me@personal.dev', 7], ['CC', 'Claude Code', 'Personal', 49], ['Cu', 'Cursor', 'me@personal.dev', 38], ['GH', 'Copilot', 'Personal', 53], ['G', 'Gemini CLI', 'me@personal.dev', 72], ['W', 'Windsurf', 'me@windsurf.dev', 67]]
      .map((r) => ({ mark: r[0], tool: r[1], login: r[2], pct: r[3] + '%', w: r[3] + '%',
        bar: r[3] <= 15 ? c.red : r[3] <= 40 ? c.orange : 'rgba(255,255,255,0.78)', ink: r[3] <= 15 ? c.redInk : c.label }));
    const menu = [['Open Keyhop', '⌘O'], ['Refresh limits', '⌘R'], ['Quit Keyhop', '⌘Q']].map((m) => ({ name: m[0], key: m[1] }));
    const extra = { rows: rows, menu: menu };
