    const L = (() => {
      const win = (name, u, reset) => ({ name: name, used: u + '%', reset: reset,
        bar: u >= 90 ? sys.red : u >= 70 ? sys.orange : 'rgba(255,255,255,0.78)', ink: u >= 90 ? '#FF8A82' : c.label, weight: u >= 90 ? 600 : 500 });
      const login = (o) => Object.assign({ hasBadge: false, badge: '', badgeBg: 'transparent', badgeInk: c.secondary, hasNote: false, note: '', windows: [],
        forecast: '', foreInk: c.tertiary, hasAction: false, action: '', btnBg: 'transparent', btnInk: '#E5E5E5', btnLine: '1px solid rgba(255,255,255,0.10)',
        bg: 'transparent', dot: c.green, line: 'none' }, o);
      const inUse = { hasBadge: true, badge: 'In use', badgeBg: rgba(accent, 0.16), badgeInk: '#93C5FD' };
      const divide = 'inset 0 1px 0 rgba(255,255,255,0.07)';
      const groups = [
        { name: 'Codex', left: '7% of 100% left · partial outage', leftInk: '#FF8A82', logins: [
          login(Object.assign({ name: 'me@personal.dev', sub: 'Plus · read 2m ago', dot: sys.red, bg: rgba(sys.red, 0.06), windows: [win('5-hour', 93, 'runs out 11:19 AM')], forecast: 'No other Codex login', foreInk: '#FF8A82', hasAction: true, action: 'Add a login' }, inUse))
        ] },
        { name: 'Claude Code', left: '108% of 200% left · about 28%/h', leftInk: c.secondary, logins: [
          login(Object.assign({ name: 'Personal', sub: 'Max 5x · me@personal.dev', windows: [win('5-hour', 51, 'back in 3h 05m'), win('Weekly', 6, 'back in 6d 19h')], forecast: 'Empty around 12:43 PM' }, inUse)),
          login({ name: 'work@studio.dev', sub: 'Pro · read 2m ago', line: divide, windows: [win('5-hour', 12, 'back in 39m'), win('Weekly', 41, 'back in 3d 11h')], forecast: 'Has the most room', foreInk: c.green, hasAction: true, action: 'Hop here', btnBg: accent, btnInk: '#0A1628', btnLine: '0' })
        ] },
        { name: 'Cursor', left: '38% of 100% left · about 0.2%/h', leftInk: c.secondary, logins: [
          login(Object.assign({ name: 'me@personal.dev', sub: 'Ultra · read 2m ago', windows: [win('Auto', 62, 'back in 13d 4h')] }, inUse)),
          login({ name: 'spare@personal.dev', sub: 'Pro · login expired', line: divide, dot: sys.red, hasBadge: true, badge: 'Signed out', badgeBg: rgba(sys.red, 0.16), badgeInk: '#FF8A82', hasNote: true, note: 'Hop to it and sign in to Cursor again to read its limits.', hasAction: true, action: 'Hop and sign in' })
        ] }
      ];
      const singles = [['Copilot', 53, 'Premium · back in 13d 4h'], ['Windsurf', 67, 'Day · back in 14h 16m'], ['Codebuff', 70, 'Usage'], ['Gemini CLI', 72, 'Quota']]
        .map((s) => ({ tool: s[0], left: s[1] + '% left', used: (100 - s[1]) + '%', sub: s[2] }));
      const tabs = [['All', '11'], ['Codex', '1'], ['Claude Code', '2'], ['Cursor', '2'], ['Copilot', '1'], ['Windsurf', '1'], ['Codebuff', '1'], ['Gemini CLI', '1']]
        .map((t, i) => ({ name: t[0], n: t[1], on: i === 0 ? 'true' : 'false', bg: i === 0 ? '#2A2A2A' : 'transparent', ink: i === 0 ? '#F5F5F5' : '#A3A3A3', weight: i === 0 ? 600 : 500 }));
      const stats = [['Draining', '80%/h', 'this hour, all logins', c.label], ['Next reset', '+35%', 'at 12:41 PM', c.green], ['At this pace', '7 days', 'before all run out', c.label]]
        .map((s) => ({ name: s[0], value: s[1], sub: s[2], ink: s[3] }));
      const y = (v) => (400 - v / 800 * 400).toFixed(1);
      const mPts = [[0, 640], [40, 610], [80, 520], [110, 560], [150, 470], [190, 500], [230, 430], [270, 450], [300, 415]];
      const pPts = [[300, 415], [330, 395], [330, 430], [400, 360], [400, 470], [520, 330], [520, 420], [640, 300], [640, 380], [780, 250], [780, 330], [1000, 180]];
      const resets = [[330, 395, 430], [400, 360, 470], [520, 330, 420], [640, 300, 380], [780, 250, 330]].map((r) => ({ x: r[0], y1: y(r[1]), y2: y(r[2]) }));
      const ticks = ['Sun', 'Mon', 'Today', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun', 'Mon', 'Tue'].map((d, i) => ({ label: d, ink: i === 2 ? c.label : c.tertiary }));
      return { groups: groups, singles: singles, tabs: tabs, stats: stats, resets: resets, ticks: ticks,
        measured: mPts.map((p) => p[0] + ',' + y(p[1])).join(' '), projected: pPts.map((p) => p[0] + ',' + y(p[1])).join(' '),
        area: 'M0,400 L' + mPts.map((p) => p[0] + ',' + y(p[1])).join(' L') + ' L300,400 Z' };
    })();
    const extra = L;
