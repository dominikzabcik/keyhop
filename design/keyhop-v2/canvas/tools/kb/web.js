    let seed = 5;
    const rnd = () => { seed = (seed * 9301 + 49297) % 233280; return seed / 233280; };
    const stars = Array.from({ length: 44 }, () => ({ x: Math.round(rnd() * 400), y: Math.round(rnd() * 210), r: rnd() > 0.85 ? 2.2 : 1.3 }));
    const heroRows = [['Personal · Claude Code', 'Max 5x · empty ~12:43 PM', 49, 'in use'], ['work@studio.dev · Claude Code', 'Pro · 5-hour 12%, weekly 41%', 59, 'pick'], ['me@personal.dev · Codex', 'Plus · runs out ~11:19 AM', 7, 'out']]
      .map((r) => ({ ic: ic(r[0].includes('Codex') ? 'codex' : 'claude'), who: r[0], sub: r[1], left: r[2] + '%', w: r[2] + '%',
        bar: r[3] === 'out' ? c.red : r[3] === 'pick' ? accent : 'rgba(255,255,255,0.78)', ink: r[3] === 'out' ? c.redInk : c.label,
        ring: r[3] === 'pick' ? rgba(accent, 0.55) : 'rgba(255,255,255,0.10)' }));
    const figures = [['9', 'AI coding tools it can switch'], ['6', 'of them with a full token history'], ['0', 'logins that leave your computer'], ['1 click', 'from the alert to the login with room']]
      .map((f, i) => ({ value: f[0], label: f[1], line: i ? 'inset 1px 0 0 rgba(255,255,255,0.08)' : 'none' }));
    const steps = [['Save', 'First, it saves the login in use.', 'Personal is saved to your keychain before anything changes.'],
      ['Load', 'Then it loads the one you chose.', 'work@studio.dev comes out of the same vault.'],
      ['Hand over', 'Next, it hands it to the tool.', 'Claude Code gets it through the path it already reads.'],
      ['Confirm', 'Last, it reads it back.', 'Claude Code now uses work@studio.dev, 12% into its 5-hour window.']]
      .map((s, i) => ({ n: i + 1, verb: s[0], title: s[1], say: s[2], chip: i === 3 ? accent : 'rgba(255,255,255,0.06)', chipInk: i === 3 ? c.accentInk : '#E5E5E5' }));
    const mono = "'Geist Mono', ui-monospace, monospace";
    const tools = [['Claude Code', '5-hour and weekly', 'Its own login, in your keychain', 1], ['Cursor', 'Auto and API', "Cursor's own login link", 1], ['Codex', '5-hour and weekly', '~/.codex/auth.json', 1],
      ['Gemini CLI', 'Stays in Gemini CLI', 'Google sign-in files', 1], ['OpenCode', 'Stays with each provider', 'The whole auth.json profile', 1], ['Pi', 'Stays with each provider', 'The whole auth.json profile', 1],
      ['GitHub Copilot', 'Plan quota from GitHub', "The GitHub CLI's accounts", 0], ['Windsurf', 'Cached for the login in use', '~/.codeium/config.json', 0], ['Codebuff', 'Credits, block and week', 'Its default profile', 0]]
      .map((t, i) => ({ ic: ic(['claude', 'cursor', 'codex', 'gemini', 'opencode', 'pi', 'copilot', 'windsurf', 'codebuff'][i]), name: t[0], limits: t[1], login: t[2], font: t[2].startsWith('~') ? mono : 'inherit', size: t[2].startsWith('~') ? '13px' : '14px',
        tag: t[3] ? 'Counted' : 'Limits only', tagBg: t[3] ? rgba(accent, 0.14) : 'rgba(255,255,255,0.06)', tagInk: t[3] ? '#93C5FD' : c.secondary,
        line: i ? 'inset 0 1px 0 rgba(255,255,255,0.06)' : 'none' }));
    const toggles = [['Hop for me before a limit runs out.', 'The alert switches to Smart Hop’s best login by itself.', 1],
      ['Warn me when a budget passes 80%.', 'Per login or across all of them, by day, week or month. Keyhop notifies you at 80% and at 100%.', 1],
      ['Share today’s totals live with my team.', 'Per-tool totals go every 90 seconds; your team day marks you live for three minutes.', 0],
      ['Count the commits I wrote myself.', 'Merge commits are left out, and each day is rewritten on sync, so a rebase counts once.', 0],
      ['Rank me by commits per million tokens.', 'The season compares people on your plan, past a floor of one million tokens.', 0]]
      .map((t, i) => ({ ic: ic(['claude', 'cursor', 'codex', 'gemini', 'opencode', 'pi', 'copilot', 'windsurf', 'codebuff'][i]), name: t[0], desc: t[1], on: t[2] ? 'true' : 'false', track: t[2] ? accent : '#2E2E2E', x: t[2] ? '21px' : '3px', line: i ? 'inset 0 1px 0 rgba(255,255,255,0.06)' : 'none' }));
    const board = [['1', 'MK', 'mkovar', 'Monument · 41-day streak', '18.4', '2.1B', '38,640'], ['2', 'AL', 'alina-dev', 'Mass · 12-day streak', '16.9', '940M', '15,886'],
      ['3', 'DZ', 'you', 'Bulk · 12-day streak', '15.2', '800M', '12,160'], ['4', 'JP', 'jpetr', 'Bulk · 3-day streak', '13.7', '620M', '8,494'], ['5', 'RS', 'rsato', 'Frame · 9-day streak', '12.1', '48M', '581']]
      .map((b, i) => ({ n: b[0], ini: b[1], who: b[2], pet: b[3], eff: b[4], tokens: b[5], commits: b[6],
        bg: b[2] === 'you' ? rgba(accent, 0.07) : 'transparent', ink: b[2] === 'you' ? '#93C5FD' : c.label,
        av: b[2] === 'you' ? rgba(accent, 0.25) : 'rgba(255,255,255,0.08)', line: i ? 'inset 0 1px 0 rgba(255,255,255,0.06)' : 'none' }));
    const faq = [['What is Keyhop, exactly?', 'A small app on your own computer. It sits in the menu bar or tray, answers as the keyhop command, holds the logins you already have for each AI coding tool, and hands a tool another of your accounts when you ask or when the one in use runs out.', ''],
      ['Does it share accounts or add usage?', 'No. Keyhop only switches between accounts you own. It cannot raise a plan’s limits, and every provider’s terms still apply.', ''],
      ['What leaves my computer?', 'Nothing, until you link GitHub. Then daily totals per tool go to the leaderboard, and current limits only if you share them. Prompts, code and logins never do. This prints every payload before it goes:', 'keyhop cloud show-data'],
      ['How do I install it?', 'On macOS and Linux, run the line below. On Windows, the PowerShell installer is on GitHub.', 'curl -fsSL https://raw.githubusercontent.com/dominikzabcik/keyhop/main/install.sh | bash'],
      ['What does API value mean?', 'The tokens you used, priced at each provider’s standard API rates. It is the value of your usage, not a bill from your subscription.', ''],
      ['Can I build it myself?', 'Yes. Keyhop is MIT licensed, its installers are readable shell scripts, and the app, the website, the packaging and the tests are in one public repository.', '']]
      .map((q) => ({ q: q[0], a: q[1], code: q[2], hasCode: !!q[2] }));
    const extra = { stars: stars, heroRows: heroRows, figures: figures, steps: steps, tools: tools, toggles: toggles, board: board, faq: faq };
