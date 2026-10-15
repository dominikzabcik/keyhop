    const oldBanners = [
      ['Codex 5-hour limit at 93%', 'me@personal.dev is close to its limit, and no other saved Codex account has room.'],
      ['Claude Code 5-hour limit runs out around 12:43 PM', 'Personal is close to its limit. work@studio.dev has 88% left.'],
      ['Hopped Claude Code to work@studio.dev', 'The limit was close, so Keyhop moved over while there was room.']
    ].map((b) => ({ title: b[0], body: b[1] }));
    const newBanners = [
      ['Claude Code runs out around 12:43', 'Personal · 5-hour at 81%', '#FBBF24', 'work@studio.dev has 88% left. Hop now and keep going.', 'claude', true, 'Hop to work@studio.dev', 'Later'],
      ['Codex is nearly out', 'me@personal.dev · 5-hour at 93%', '#FF8A82', 'No other Codex login has room. Add one to hop next time.', 'codex', true, 'Add a login', 'Later'],
      ['Claude Code hopped to work@studio.dev', 'Smart Hop · Personal was at 90%', '#34D399', 'It moved while there was room. Open Keyhop to hop back.', 'claude', false, '', ''],
      ['Cursor passed 80% of this month’s budget', '$160 of $200', '#FBBF24', 'Keyhop tells you again at 100%.', 'cursor', false, '', '']
    ].map((b) => ({ title: b[0], sub: b[1], subInk: b[2], body: b[3], ic: ic(b[4]), markInk: '#F5F5F5', hasActions: b[5], act1: b[6], act2: b[7] }));
    const oldNotices = [['Codex is nearly out', 'No other Codex login has room.', 'Add login'], ['Cursor signed out', 'spare@personal.dev needs you to sign in.', 'Sign in']]
      .map((n, i) => ({ title: n[0], body: n[1], act: n[2], line: i ? 'inset 0 1px 0 rgba(232,165,79,0.18)' : 'none' }));
    const divide = 'inset 0 1px 0 rgba(255,255,255,0.07)';
    const notices = [
      ['codex', 'Codex is nearly out', 'Out', rgba(c.red, 0.16), c.redInk, c.red, 'me@personal.dev runs out around 11:19 AM, and no other Codex login has room.', 'Add a login', 'transparent', '#E5E5E5', 'inset 0 0 0 1px rgba(255,255,255,0.12)'],
      ['claude', 'Hop Claude Code', 'Hop', rgba(accent, 0.16), '#93C5FD', accent, 'Personal is at 81%. work@studio.dev has 88% left.', 'Hop', accent, c.accentInk, 'none'],
      ['cursor', 'Cursor signed out', 'Sign in', 'rgba(255,255,255,0.08)', c.secondary, '#737373', 'spare@personal.dev needs you to sign in to read its limits.', 'Sign in', 'transparent', '#E5E5E5', 'inset 0 0 0 1px rgba(255,255,255,0.12)']
    ].map((n, i) => ({ ic: ic(n[0]), title: n[1], pill: n[2], pillBg: n[3], pillInk: n[4], tone: n[5], body: n[6], act: n[7], btnBg: n[8], btnInk: n[9], btnLine: n[10], dismiss: 'Dismiss', line: i ? divide : 'none' }));
    const mono = "'Geist Mono', ui-monospace, monospace";
    const seg = (o) => Object.assign({ bg: 'transparent', ink: c.secondary, flex: 'none', font: 'inherit', size: '12px', track: '0', case: 'none', hasDot: false, dot: '', cls: '', hasIc: false, ic: ic(''), text: '' }, o);
    const fig = (t) => seg({ text: t, font: mono, size: '11px', track: '.08em', case: 'uppercase' });
    const bar = [
      seg({ text: '2 need a hop', hasDot: true, dot: c.red, bg: rgba(c.red, 0.12), ink: c.redInk }),
      seg({ text: 'Codex partial outage', hasIc: true, ic: ic('codex'), bg: rgba(c.orange, 0.12), ink: '#FBBF24' }),
      seg({ flex: '1' }),
      fig('7.6M today'), fig('12-day streak'), fig('Night'),
      seg({ text: 'Read 2 min ago', hasIc: false, ink: '#E5E5E5', bg: 'rgba(255,255,255,0.05)' })
    ];
    const barCalm = [
      seg({ text: 'Live', hasDot: true, dot: c.green, cls: 'live', ink: c.green }),
      seg({ text: 'Limits clear', ink: c.secondary }),
      seg({ flex: '1' }),
      fig('7.6M today'), fig('12-day streak'),
      seg({ text: 'Read 2 min ago', ink: '#E5E5E5', bg: 'rgba(255,255,255,0.05)' })
    ];
    const extra = { oldBanners: oldBanners, newBanners: newBanners, oldNotices: oldNotices, notices: notices, bar: bar, barCalm: barCalm };
