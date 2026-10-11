import Foundation

/// Keyhop cloud in the window: leaderboard, season, teams, profile, quests, badges and the work card.
extension DashboardPage {
    static let scriptCloud = ##"""
  // MARK: Leaderboard

  function ago(iso) {
    const seconds = Math.max(0, (Date.now() - new Date(iso).getTime()) / 1000);
    if (seconds < 60) return "just now";
    if (seconds < 3600) return `${Math.floor(seconds / 60)} min ago`;
    if (seconds < 86400) return `${Math.floor(seconds / 3600)} h ago`;
    return `${Math.floor(seconds / 86400)} d ago`;
  }

  function workCard(work) {
    if (!work) return "";
    if (!work.gitAvailable) {
      return `<section class="card"><div class="card-head"><h2>What you shipped</h2></div>
        <div class="card-body"><p class="empty-inline">git isn't installed, so Keyhop can't count commits on this computer.</p></div></section>`;
    }
    const folders = work.roots.length
      ? `<div class="list">${work.roots.map((path) => `<div class="row setting-row"><div><b class="mono" style="font-size:12.5px">${esc(path)}</b></div>
          ${isStatic ? "" : `<button class="btn sm ghost" data-action="work-remove" data-path="${esc(path)}">Remove folder</button>`}</div>`).join("")}</div>`
      : `<p class="empty">No folders yet. Add one below, or Keyhop will offer the usual ones when you turn this on.</p>`;
    const index = work.index && work.index.total
      ? (work.index.complete
        ? `Indexed ${work.index.total} ${work.index.total === 1 ? "repository" : "repositories"}.`
        : `Indexing: ${work.index.done} of ${work.index.total} repositories, so figures are still filling in.`)
      : "";
    const synced = work.lastSync ? `Last sent ${esc(ago(work.lastSync))}.` : "Not sent yet.";
    const toggle = work.enabled
      ? `<button class="btn sm ghost" data-action="work-off">Stop counting</button>`
      : `<button class="btn sm" data-action="work-on">Count commits</button>`;
    const subjects = work.shareSubjects
      ? `<div class="card-body setting-row"><div><b>Subject lines are shared</b><p>The first line of each commit goes with the counts. Teams reads them as tasks, and so does the team's day on the website. Turning this off deletes the ones already sent.</p></div>
          <button class="btn sm ghost" data-action="work-subjects-off">Keep subjects here</button></div>`
      : `<div class="card-body setting-row"><div><b>Keep subject lines here</b><p>Counts still go. The words you wrote stay on this computer until you share them.</p></div>
          <button class="btn sm secondary" data-action="work-subjects-on">Share subject lines</button></div>`;
    const add = isStatic ? "" : `<form class="form" data-form="work-folder" style="padding-top:0">
      <label>Folder to scan<input class="field" name="folder" placeholder="~/Projects" autocomplete="off"></label>
      <div class="row-actions" style="justify-content:flex-start"><button class="btn sm secondary">Add folder</button></div>
    </form>`;
    const read = isStatic ? "" : `<div class="card-body setting-row"><div><b>Read repositories now</b>
        <p>Walks the folders below. A repository that hasn't changed since last time is skipped.</p></div>
        <button class="btn sm secondary" data-action="work-index">Read repositories now</button></div>`;
    return `<section class="card"><div class="card-head"><h2>What you shipped</h2>${work.enabled ? `<span class="badge live">On</span>` : ""}</div>
      <div class="card-body setting-row"><div><b>Count the commits you author</b>
        <p>Token totals say what a day cost. This adds what came out of it, from the git repositories already on this computer. Paths and diffs never leave. ${index} ${synced}</p></div>
        ${toggle}</div>
      ${work.enabled ? `${subjects}${read}${folders}${add}` : ""}
    </section>`;
  }

  function profileForm() {
    if (data.profileError) return `<div class="card-body"><p class="empty-inline">${esc(data.profileError)}</p></div>`;
    const profile = data.profile;
    if (!profile) return `<div class="card-body">${busy("Reading your profile", "empty")}</div>`;
    return `<form class="form card-body" data-form="profile">
      <label>Display name<input class="field" name="displayName" maxlength="40" value="${esc(profile.displayName || "")}" placeholder="${esc(profile.name || profile.login)}" autocomplete="off"></label>
      <label>Bio<input class="field" name="bio" maxlength="160" value="${esc(profile.bio || "")}" placeholder="One line about you" autocomplete="off"></label>
      <label>Link<input class="field" name="link" maxlength="200" value="${esc(profile.link || "")}" placeholder="your-site.dev" autocomplete="off"></label>
      <label class="check"><input type="checkbox" name="public" ${profile.public ? "checked" : ""}> Show me on the global leaderboard</label>
      <div class="row-actions" style="justify-content:flex-start"><button class="btn sm">Save profile</button></div>
    </form>`;
  }

  function appsCard() {
    if (data.appsError) return `<div class="card-body"><p class="empty-inline">${esc(data.appsError)}</p></div>`;
    const apps = data.apps?.apps;
    if (!apps) return `<div class="card-body">${busy("Reading linked apps", "empty")}</div>`;
    if (!apps.length) return `<div class="card-body"><p class="empty-inline">No Keyhop app is linked yet.</p></div>`;
    const rows = apps.map((app) => `<div class="row setting-row"><div><b>${esc(app.label || "Keyhop")}${app.current ? " · this computer" : ""}</b><p>${app.access === "read" ? "Read only" : "Can sync"}${app.lastUsedAt ? ` · used ${esc(ago(app.lastUsedAt))}` : ""}</p></div>
      ${app.current ? "" : `<button class="btn sm ghost" type="button" data-action="app-revoke" data-id="${esc(app.id)}">Unlink</button>`}</div>`).join("");
    return `<div class="card-head"><h2>Linked apps</h2><span class="hint">${apps.length}</span></div><div class="list">${rows}</div>`;
  }

  function deleteAccountForm() {
    const login = data.profile?.login || data.state?.cloud?.login || "";
    return `<form class="form card-body" data-form="account-delete">
      <p class="empty-inline">Removes your profile, synced totals, linked apps, memberships and the teams you own.</p>
      <label>Delete account<input class="field" name="confirm" placeholder="Type ${esc(login)} to confirm" autocomplete="off"></label>
      <div class="row-actions" style="justify-content:flex-start"><button class="btn sm secondary danger">Delete account</button></div>
    </form>`;
  }

  function cloudCard(cloud) {
    if (cloud.linking) {
      return `<section class="card"><div class="card-head"><h2>Link with GitHub</h2><span class="badge">Waiting</span></div>
        <div class="card-body setting-row"><div><b>Approve <span class="mono">${esc(cloud.linking.userCode)}</span> in your browser</b>
          <p>Sign in with GitHub, check that the code matches, and approve it. This page notices by itself.</p></div>
          <div class="row-actions"><a class="btn sm" href="${esc(cloud.linking.verifyUrl)}" target="_blank" rel="noopener">Open sign-in</a>
          <button class="btn sm ghost" data-action="cloud-unlink">Cancel</button></div></div></section>`;
    }
    if (!cloud.linked) {
      return `<section class="card"><div class="card-head"><h2>Link with GitHub</h2></div>
        <div class="card-body setting-row"><div><b>Compare your usage with friends and teams</b>
          <p>Linking joins leaderboards and gives you a profile you can share. Keyhop sends tokens, API value and requests per tool per day. Never prompts, emails or account names.</p></div>
          <button class="btn sm" data-action="cloud-link">Link with GitHub</button></div></section>`;
    }
    const synced = cloud.lastSyncError ? `The last sync failed: ${esc(cloud.lastSyncError)}` : cloud.lastSync ? `Synced ${esc(ago(cloud.lastSync))}` : "Not synced yet";
    const limits = cloud.sharesLimits
      ? `<div class="card-body setting-row"><div><b>Your phone can see your limits</b>
          <p>How full each account is, when it comes back, and the name you gave it. No emails, and nothing about what you asked.</p></div>
          <button class="btn sm ghost danger" data-action="cloud-limits-off">Stop sharing</button></div>`
      : `<div class="card-body setting-row"><div><b>Let your phone see your limits</b>
          <p>The Keyhop app on your phone can then tell you when an account comes back. It sends how full each account is and the name you gave it, never an email.</p></div>
          <button class="btn sm secondary" data-action="cloud-limits-on">Share limits</button></div>`;
    const live = cloud.sharesLive
      ? `<div class="card-body setting-row"><div><b>Your team's day moves with your work</b>
          <p>Every ninety seconds Keyhop sends today's tokens, API value and requests per tool. Nothing about a request, a session or a prompt.</p></div>
          <button class="btn sm ghost danger" data-action="cloud-live-off">Stop sharing</button></div>`
      : `<div class="card-body setting-row"><div><b>Let your team's day move with your work</b>
          <p>Keyhop then sends today's totals per tool every ninety seconds instead of once an hour. The readings are kept for minutes, never as history.</p></div>
          <button class="btn sm secondary" data-action="cloud-live-on">Share live</button></div>`;
    const outbound = data.outbound
      ? data.outbound.sections.map((section) => `<details class="outbound"${section.on ? " open" : ""}><summary><b class="mono">${esc(section.endpoint)}</b><span class="subtle">${esc(section.when)}</span></summary><pre class="mono">${esc(JSON.stringify(section.payload, null, 2))}</pre></details>`).join("")
      : data.outboundError
        ? `<p class="empty-inline">${esc(data.outboundError)}</p>`
        : `<button class="btn sm secondary" data-action="cloud-show-data">Show the exact data</button>`;
    const shows = `<section class="card"><div class="card-head"><h2>What this computer sends</h2><span class="hint">Shown before anything goes</span></div>
      <div class="card-body setting-row"><div><b>Exactly the payloads, as they would go right now</b>
        <p>Daily totals per tool, commit counts per repository, limit readings and today's live totals. Never a prompt, an email or an account name.</p></div></div>
      <div class="card-body">${outbound}</div></section>`;
    const images = cloud.isPublic && cloud.profile
      ? `<section class="card"><div class="card-head"><h2>README images</h2></div><div class="form card-body">${shareLines(cloud.profile, [["Badge", "badge.svg"], ["Card", "card.svg"], ["Streak", "streak.svg"], ["Tools", "tools.svg"], ["Year", "graph.svg"], ["Pet", "pet.svg"]])}
        <p class="empty-inline subtle">The badge shows tokens for the last 7 days. Add ?metric= and ?period= to the image address, and ?theme=light on a light page. <a href="https://github.com/dominikzabcik/keyhop#readme-images" target="_blank" rel="noopener">How the images work</a></p></div></section>`
      : "";
    return `<section class="card"><div class="card-head"><h2>This computer</h2><span class="badge live">Linked</span></div>
      <div class="card-body setting-row"><div><b>@${esc(cloud.login)}${cloud.isPublic ? "" : " · private profile"}</b>
        <p>${synced}. Daily totals go out hourly, after a refresh.</p></div>
        <div class="row-actions"><button class="btn sm secondary" data-action="cloud-sync">Sync now</button>
        <button class="btn sm ghost danger" data-action="cloud-unlink">Unlink</button></div></div></section>
      <section class="card"><div class="card-head"><h2>How you appear</h2></div>${profileForm()}</section>
      ${images}
      <section class="card">${appsCard()}</section>
      <section class="card"><div class="card-head"><h2>Phone</h2></div>${limits}</section>
      <section class="card"><div class="card-head"><h2>Live</h2></div>${live}</section>
      ${shows}
      <section class="card"><div class="card-head"><h2>Delete account</h2></div>${deleteAccountForm()}</section>`;
  }

  // Six squares climbing to the right, lit as far as the tier has come.
  function tierMark(key) {
    const steps = { bronze: 1, silver: 2, gold: 3, platinum: 4, diamond: 5, master: 6 }[key] || 1;
    const cells = Array.from({ length: 6 }, (_, index) => {
      const height = 3 + index * 2.4;
      return `<rect x="${index * 4}" y="${(17 - height).toFixed(1)}" width="3" height="${height.toFixed(1)}" rx="1" fill-opacity="${index < steps ? 1 : 0.22}"/>`;
    }).join("");
    return `<svg viewBox="0 0 23 18" aria-hidden="true">${cells}</svg>`;
  }

  function tierTag(tier, size) {
    const roman = ["", "I", "II", "III"][tier.division || 0];
    return `<span class="tier tier-${esc(tier.key)}${size === "sm" ? " sm" : ""}">${tierMark(tier.key)}<span>${esc(tier.name)}${roman ? ` ${roman}` : ""}</span></span>`;
  }

  // This month's ranked season.
  function seasonRow(season) {
    if (!season) return "";
    const you = season.you;
    const left = season.over ? "Finished" : season.daysLeft === 1 ? "Ends today" : `${season.daysLeft} days left`;
    const note = !you || you.rank === null || you.rank === undefined
      ? "Sync some usage this month to take a place."
      : you.next
        ? `${fmt.tokens(you.next.tokens)} more tokens for ${esc(you.next.label)}.`
        : "You're at the top of the ladder.";
    const divisionName = { free: "Free", pro: "Pro", max: "Max" }[you && you.division] || "";
    const place = you && you.rank ? `#${you.rank} of ${you.players || season.players}${divisionName ? ` in ${divisionName}` : ""}. ` : "";
    const seasons = season.seasons || [];
    const tabs = seasons.length > 1
      ? `<div class="tabs">${seasons.map((item) => `<button type="button" data-action="board-season" data-value="${esc(item.id)}" aria-pressed="${item.id === season.season}">${esc(item.label)}</button>`).join("")}</div>`
      : "";
    return `<section class="card season-row">
      ${tierTag(you ? you.tier : { key: "bronze", name: "Bronze", division: 3 })}
      <div class="grow"><b>${esc(season.label)} · ${esc(left)}</b><p>${place}${note}</p>${tabs}</div>
    </section>`;
  }

  // The streak number is already counted. This is the click that takes today's keep.
  function claimCard(quests) {
    const claim = quests && quests.claim;
    if (!claim) return "";
    const keeps = (claim.keeps || []).map((keep) => `<span class="badge">${esc(keep.name)} ${keep.count}</span>`).join("");
    const action = claim.claimed && claim.today
      ? `<p class="empty-inline subtle">Claimed today · ${esc(claim.today.name)}</p>`
      : claim.active && claim.today
        ? `<button class="btn claim-kick" type="button" data-action="streak-claim">Claim ${esc(claim.today.name)}</button>`
        : `<p class="empty-inline subtle">The streak counts a day with tokens or a commit. Claim opens once today has one.</p>`;
    const days = `${claim.streak} ${claim.streak === 1 ? "day" : "days"}`;
    return `<section class="card"><div class="card-head"><h2>Keeps</h2><span class="hint">${esc(days)}</span></div>
      <div class="card-body">${keeps ? `<p style="margin:0 0 12px;display:flex;flex-wrap:wrap;gap:8px">${keeps}</p>` : `<p class="empty-inline">Nothing kept yet.</p>`}${action}</div></section>`;
  }

  // The same goals the website shows, so the window and the site never disagree.
  function questsCard(quests) {
    if (!quests || !quests.quests || quests.quests.length === 0) return "";
    const done = quests.quests.filter((goal) => goal.complete).length;
    const row = (goal) => `<div class="quest-row${goal.complete ? " done" : ""}">
      <div><b>${esc(goal.name)}</b><p>${esc(goal.note)}</p></div>
      <div><div class="quest-track"><span style="width:${Math.max(0, Math.min(100, Math.round((goal.done / goal.target) * 100)))}%"></span></div>
        <div class="quest-state">${goal.complete ? "Done" : goal.target <= 7 ? `${goal.done} of ${goal.target}` : `${Math.round((goal.done / goal.target) * 100)}%`}</div></div>
    </div>`;
    return `<section class="card"><div class="card-head"><h2>Quests</h2><span class="hint">${done} of ${quests.quests.length} done</span></div>
      ${quests.quests.map(row).join("")}</section>`;
  }

  function badgesCard(quests) {
    const badges = quests?.badges || [];
    if (!badges.length) return "";
    const earned = badges.filter((badge) => badge.earned).length;
    return `<section class="card"><div class="card-head"><h2>Badges</h2><span class="hint">${earned} of ${badges.length}</span></div>
      ${badges.map((badge) => `<div class="quest-row${badge.earned ? " done" : ""}"><div><b>${esc(badge.name)}</b><p>${esc(badge.earned && badge.day ? `Earned ${badge.day}` : badge.note)}</p></div></div>`).join("")}</section>`;
  }

  function seasonStandings(season) {
    const entries = season?.entries || [];
    if (!entries.length) return "";
    return `<section class="card"><div class="card-head"><h2>Season standings</h2><span class="hint">${entries.length}</span></div>
      <table class="table"><thead><tr><th style="width:52px">#</th><th>Person</th><th>Tier</th><th class="right">Tokens</th></tr></thead>
      <tbody>${entries.map((entry) => `<tr class="${entry.isYou ? "me" : ""}"><td class="mono subtle">${entry.rank}</td><td><b>${esc(entry.name || entry.login)}</b> <small class="subtle">@${esc(entry.login)}</small></td><td>${tierTag(entry.tier, "sm")}</td><td class="right mono">${fmt.tokens(entry.tokens)}</td></tr>`).join("")}</tbody></table></section>`;
  }

  function shareLines(page, files) {
    return files.map(([label, file]) => `<label>${esc(label)}<input class="field mono" readonly value="[![${esc(label)}](${esc(page)}/${file})](${esc(page)})"></label>`).join("");
  }

  function boardChoice(action, options, current) {
    return `<div class="tabs">${options.map(([value, label]) => `<button data-action="${action}" data-value="${value}" aria-pressed="${value === current}">${label}</button>`).join("")}</div>`;
  }

  function knownTeams() {
    return data.day?.teams || data.board?.teams || [];
  }

  function teamMenu() {
    const teams = knownTeams();
    if (!teams.length) return "";
    const options = [`<option value="">All teams</option>`].concat(teams.map((team) => `<option value="${esc(team.slug)}"${team.slug === ui.boardTeam ? " selected" : ""}>${esc(team.name)}</option>`));
    return `<select class="field" data-action="board-team">${options.join("")}</select>`;
  }

  function teamList(website) {
    const teams = knownTeams();
    const rows = teams.map((team) => `<div class="row setting-row"><div><b>${esc(team.name)}</b><p>${team.members} ${team.members === 1 ? "member" : "members"}${team.role === "owner" ? " · owner" : ""}</p></div>
      <button class="btn sm ghost" type="button" data-action="board-pick" data-value="${esc(team.slug)}">Open</button></div>`).join("");
    return `<section class="card"><div class="card-head"><h2>Your teams</h2>${teams.length ? `<span class="hint">${teams.length}</span>` : ""}</div>
      ${rows ? `<div class="list">${rows}</div>` : `<p class="empty">You aren't on a team yet. Create one, or paste an invite from a teammate.</p>`}
      <div class="card-body">
        <form class="form" data-form="team-create"><label>New team<input class="field" name="name" maxlength="40" placeholder="Studio" autocomplete="off"></label><button class="btn sm">Create team</button></form>
        <form class="form" data-form="team-join"><label>Invite link or code<input class="field" name="code" placeholder="https://keyhop.app/invite/…" autocomplete="off"></label><button class="btn sm secondary">Join team</button></form>
        <p class="empty-inline subtle"><a href="${esc(website)}/teams" target="_blank" rel="noopener">The same teams are on the website</a></p>
      </div></section>`;
  }

  function teamManage(website) {
    const current = knownTeams().find((team) => team.slug === ui.boardTeam);
    if (!current) return "";
    const roster = (data.board?.team === ui.boardTeam ? data.board.members : data.day?.team?.slug === ui.boardTeam ? data.day.members : null) || [];
    const people = roster.map((person) => `<div class="row setting-row"><div><b>${esc(person.name || person.login)}</b><p>@${esc(person.login)}${person.role === "owner" ? " · owner" : ""}</p></div>
      ${current.role === "owner" && person.role !== "owner" ? `<button class="btn sm ghost" type="button" data-action="team-remove" data-login="${esc(person.login)}">Remove</button>` : ""}</div>`).join("");
    const invite = data.invite ? `<label>Share this link<input class="field" readonly value="${esc(data.invite)}"></label>` : "";
    const publish = current.role === "owner"
      ? `<label class="check"><input type="checkbox" data-action="team-public" ${current.public ? "checked" : ""}> Publish this team's totals</label>
         <p class="empty-inline subtle">The image shows summed totals and how many members there are. Anyone with the link can load it.</p>`
      : "";
    const snippets = current.public
      ? `<div class="form">${shareLines(`${website}/t/${current.slug}`, [["Badge", "badge.svg"], ["Card", "card.svg"], ["Streak", "streak.svg"], ["Tools", "tools.svg"], ["Year", "graph.svg"]])}
         <p class="empty-inline subtle">The badge shows this team's tokens for the last 7 days. A team image takes tokens, cost, requests, commits, lines or streak.</p></div>`
      : "";
    const actions = current.role === "owner"
      ? `${people}<div class="row-actions" style="justify-content:flex-start"><button class="btn sm secondary" type="button" data-action="team-invite">Create invite link</button><button class="btn sm ghost" type="button" data-action="team-revoke">Turn off invite links</button></div>${invite}
        <form class="form" data-form="team-delete"><label>Delete this team<input class="field" name="confirm" placeholder="Type ${esc(current.slug)} to confirm" autocomplete="off"></label><button class="btn sm secondary danger">Delete team</button></form>`
      : `${people}<div class="row-actions" style="justify-content:flex-start"><button class="btn sm ghost" type="button" data-action="team-leave">Leave ${esc(current.name)}</button></div>`;
    return `<section class="card"><div class="card-head"><h2>${esc(current.name)}</h2><span class="hint">${current.members} ${current.members === 1 ? "member" : "members"}</span></div>
      <div class="card-body">${publish}${snippets}${actions}</div></section>`;
  }

  function boardValue(entry) {
    if (ui.boardMetric === "efficiency") return entry.efficiency == null ? "Unranked" : `${entry.efficiency >= 10 ? Math.round(entry.efficiency) : entry.efficiency.toFixed(1)} per M`;
    if (ui.boardMetric === "cache") return entry.cacheHit == null ? "Unknown" : `${Math.round(entry.cacheHit)}%`;
    if (ui.boardMetric === "cost") return fmt.usd(entry.cost);
    if (ui.boardMetric === "requests") return fmt.count(entry.requests);
    if (ui.boardMetric === "commits") return fmt.count(entry.commits);
    if (ui.boardMetric === "lines") return fmt.count((entry.insertions || 0) + (entry.deletions || 0));
    return fmt.tokens(entry.tokens);
  }

  function diffStat(added, removed) {
    if (!added && !removed) return "";
    return `<span class="diff">+${fmt.count(added)} −${fmt.count(removed)}</span>`;
  }

  // The same day the website shows at /t/<team>/day.
  function dayView(toolbar) {
    if (data.dayError) return { toolbar, body: `<div class="notice">${icon("alert")}<div><p>${esc(data.dayError)}</p></div></div>` };
    if (!data.day) return { toolbar, body: busy("Reading the day", "lede") };
    const day = data.day;
    if (!day.team) return { body: teamList(day.website) };
    if (ui.boardTeam && day.team.slug !== ui.boardTeam) return { toolbar, body: busy("Reading the day", "lede") };
    const label = day.day === day.today ? "Today" : day.day;
    const previous = `<button class="btn sm ghost" type="button" data-action="day-step" data-value="${esc(day.previous)}" aria-label="Previous day">Previous</button>`;
    const following = day.next
      ? `<button class="btn sm ghost" type="button" data-action="day-step" data-value="${esc(day.next)}" aria-label="Next day">Next</button>`
      : "";
    const back = day.day === day.today ? `<span class="now">${label}</span>` : `<button class="btn sm ghost" type="button" data-action="day-step" data-value="${esc(day.today)}">Today</button>`;
    const nav = `<div class="day-nav">${previous}${back}${following}</div>`;
    const people = day.people || [];
    const commits = people.reduce((sum, person) => sum + (person.commits || 0), 0);
    const tokens = people.reduce((sum, person) => sum + (person.tokens || 0), 0);
    const worked = people.filter((person) => person.commits > 0 || person.tokens > 0).length;
    const repos = new Set(people.flatMap((person) => (person.repos || []).map((repo) => repo.repo)));
    const sum = `<p class="day-sum"><span><b>${worked}</b> of ${people.length} working</span><span><b>${fmt.count(commits)}</b> ${commits === 1 ? "commit" : "commits"}</span><span><b>${repos.size}</b> ${repos.size === 1 ? "repository" : "repositories"}</span><span><b>${fmt.tokens(tokens)}</b> tokens</span></p>`;
    const card = (person) => {
      const tasks = person.tasks || [];
      const shown = tasks.slice(0, 6);
      const many = (person.repos || []).length > 1;
      const lines = tasks.length === 0 && person.commits > 0
        ? `<p class="day-note" style="padding:0 16px 14px">Commit subjects aren't shared from this computer.</p>`
        : shown.map((task) => `<li class="task"><div class="task-head"><h3>${esc(task.title)}</h3><span class="task-meta">${many ? `<span>${esc(task.repos.map((repo) => repo.split("/").pop()).join(", "))}</span>` : ""}${task.commits.length === 1 ? `<code class="sha">${esc(task.commits[0].sha.slice(0, 7))}</code>` : ""}<span>${fmt.count(task.commits.length)} ${task.commits.length === 1 ? "commit" : "commits"}</span><span>${esc(task.span)}</span>${diffStat(task.insertions, task.deletions)}</span></div>${task.commits.length < 2 ? "" : `<ul class="commits">${task.commits.map((commit) => `<li class="commit"><code class="sha">${esc(commit.sha.slice(0, 7))}</code><span>${esc(commit.subject)}</span></li>`).join("")}</ul>`}</li>`).join("");
      const more = tasks.length > 6 ? `<li class="task"><span class="day-note">and ${tasks.length - 6} more</span></li>` : "";
      const indexing = person.indexing ? `<p class="day-note" style="padding:0 16px 12px">Still reading this computer's repositories, ${fmt.count(person.indexing.done)} of ${fmt.count(person.indexing.total)}. What's here is real, but it isn't all of it yet.</p>` : "";
      const quiet = person.commits === 0 && person.tokens === 0 && !person.indexing ? `<p class="day-note" style="padding:0 16px 14px">Nothing synced for this day.</p>` : "";
      return `<section class="card day-person"><header class="card-head day-head"><h2>${esc(person.name || person.login)}${person.isYou ? " · you" : ""}</h2><div class="day-figures"><div><b>${fmt.count(person.commits)}</b><small>${person.commits === 1 ? "commit" : "commits"}</small></div><div><b>${fmt.tokens(person.tokens)}</b><small>${person.live ? `<i class="live-dot" title="Sent in the last few minutes"></i>live` : "tokens"}</small></div><div>${diffStat(person.insertions, person.deletions) || "<b>0</b>"}<small>lines</small></div></div></header>${indexing}${quiet}<ol class="tasks">${lines}${more}</ol></section>`;
    };
    const empty = commits === 0 ? `<section class="card"><p class="empty">No commits synced for this day. Turn counting on under Settings, Activity.</p></section>` : "";
    const note = `<p class="empty-inline subtle"><a href="${esc(day.website)}/t/${esc(day.team.slug)}/day/${esc(day.day)}" target="_blank" rel="noopener">Open this day on the website</a></p>`;
    return { toolbar: `${toolbar}${nav}`, body: sum + people.map(card).join("") + empty + note };
  }

  const MIX_TONES = {
    claude: .9, cursor: .55, codex: .28, gemini: .14, opencode: .11, pi: .08,
    amp: .4, goose: .34, qwen: .22, kimi: .18, grok: .125, kilo: .1, openclaw: .07,
  };

  function ranksBody(entries, scope) {
    const cloud = data.state.cloud;
    const value = boardValue;
    const avatar = (e, size) => `<span class="avatar" style="width:${size}px;height:${size}px;font-size:${Math.round(size * 0.42)}px" aria-hidden="true">${esc(e.login.slice(0, 1).toUpperCase())}</span>`;
    const person = (e, size) => `<div class="who">${avatar(e, size)}<div><b>${esc(e.name || e.login)}</b><small>@${esc(e.login)}</small></div></div>`;
    // Every measured tool, in the website's order and at its shade, so the two bars agree.
    const mix = (e) => {
      const parts = Object.keys(MIX_TONES).filter((tool) => (e.tools[tool] || 0) > 0);
      const total = parts.reduce((sum, tool) => sum + e.tools[tool], 0);
      return `<div class="mix-bar">${parts.map((tool) => `<span style="width:${(e.tools[tool] / total * 100).toFixed(2)}%;background:hsl(var(--on) / ${MIX_TONES[tool]})" title="${esc(toolName(tool))} ${fmt.tokens(e.tools[tool])}"></span>`).join("")}</div>`;
    };
    const me = entries.find((e) => e.isYou);
    const ahead = me && me.rank > 1 ? entries[me.rank - 2] : null;
    const gap = ahead ? value({ efficiency: ahead.efficiency != null && me.efficiency != null ? ahead.efficiency - me.efficiency : null, cacheHit: ahead.cacheHit != null && me.cacheHit != null ? ahead.cacheHit - me.cacheHit : null, tokens: ahead.tokens - me.tokens, cost: ahead.cost - me.cost, requests: ahead.requests - me.requests, commits: (ahead.commits || 0) - (me.commits || 0), insertions: (ahead.insertions || 0) - (me.insertions || 0), deletions: (ahead.deletions || 0) - (me.deletions || 0) }) : null;
    const onTeam = scope !== "the global board";
    const stats = `<div class="stats three">
      <div class="card stat"><div class="label">Your rank</div><div class="value">${me ? `#${me.rank}` : "Unranked"}</div>
        <div class="foot">${me ? `of ${entries.length} on ${esc(scope)}` : cloud.isPublic || onTeam ? "Nothing synced for this period" : "Private profiles rank only on teams"}</div></div>
      <div class="card stat"><div class="label">You</div><div class="value">${me ? esc(value(me)) : "0"}</div>
        <div class="foot">${me ? `${me.activeDays} active ${me.activeDays === 1 ? "day" : "days"}` : "&nbsp;"}</div></div>
      <div class="card stat"><div class="label">${ahead ? `To catch @${esc(ahead.login)}` : "Ahead of you"}</div><div class="value">${gap ? esc(gap) : me ? "Nobody" : "&nbsp;"}</div>
        <div class="foot">${ahead ? `They're #${ahead.rank}` : me ? "You lead this board" : "&nbsp;"}</div></div>
    </div>`;
    const podium = entries.length ? `<div class="podium">${entries.slice(0, 3).map((e) => `<div class="card podium-card${e.isYou ? " you" : ""}">
        <span class="place mono">#${e.rank}</span>${person(e, 36)}<div class="podium-value">${esc(value(e))}</div>${mix(e)}</div>`).join("")}</div>` : "";
    const heading = { efficiency: "Commits per M tokens", cache: "Cache hit", tokens: "Tokens", cost: "API value", requests: "Requests", commits: "Commits", lines: "Lines" }[ui.boardMetric];
    const table = entries.length
      ? `<section class="card"><table class="table"><thead><tr><th style="width:52px">#</th><th>Person</th><th>Tools</th><th class="right">Active days</th><th class="right">${heading}</th></tr></thead>
          <tbody>${entries.map((e) => `<tr class="${e.isYou ? "me" : ""}"><td class="mono subtle">${e.rank}</td><td>${person(e, 26)}</td><td class="bar-cell">${mix(e)}</td>
          <td class="right mono subtle">${e.activeDays}</td><td class="right mono">${esc(value(e))}</td></tr>`).join("")}</tbody></table></section>`
      : `<section class="card"><p class="empty">No usage yet for this period. It fills in as the computers on your board refresh.</p></section>`;
    return stats + podium + table;
  }

  function periodChoices() {
    return boardChoice("board-period", [["today", "Today"], ["week", "7 days"], ["month", "30 days"], ["all", "All time"]], ui.boardPeriod)
      + boardChoice("board-metric", [["efficiency", "Efficiency"], ["cache", "Cache hit"], ["tokens", "Tokens"], ["cost", "API value"], ["requests", "Requests"], ["commits", "Commits"], ["lines", "Lines"]], ui.boardMetric)
      + boardChoice("board-division", [["", "Everyone"], ["free", "Free"], ["pro", "Pro"], ["max", "Max"]], ui.boardDivision);
  }

  function boardProblem() {
    return `<div class="notice">${icon("alert")}<div><p>${esc(data.boardError)}</p></div></div>`;
  }

  function leaderboardPage() {
    const cloud = data.state.cloud;
    if (!cloud.linked || cloud.linking) return { body: cloudCard(cloud) };
    const toolbar = periodChoices();
    if (data.boardError) return { toolbar, body: boardProblem() };
    if (!data.board || data.board.team) return { toolbar, body: busy("Reading the leaderboard", "lede") };
    const note = cloud.isPublic ? "" : `<p class="empty-inline subtle">Your profile is private. Make it public in Settings, Cloud, to join the global board.</p>`;
    return { toolbar, body: ranksBody(data.board.board.entries, "the global board") + note };
  }

  function seasonPage() {
    if (data.boardError) return { body: boardProblem() };
    if (!data.board) return { body: busy("Reading the season", "lede") };
    if (!data.board.season) return { body: `<section class="card"><p class="empty">No season to show yet.</p></section>` };
    return { body: seasonRow(data.board.season) + seasonStandings(data.board.season) };
  }

  function profilePage() {
    const cloud = data.state.cloud;
    if (data.boardError) return { body: boardProblem() };
    if (!data.board) return { body: busy("Reading your profile", "lede") };
    const link = cloud.profile ? `<p class="empty-inline subtle"><a href="${esc(cloud.profile)}" target="_blank" rel="noopener">Open the full profile</a></p>` : "";
    return { body: petCard() + claimCard(data.board.quests) + questsCard(data.board.quests) + badgesCard(data.board.quests) + link };
  }

  function teamsPage() {
    const website = data.day?.website || data.board?.website || "https://keyhop.app";
    if (ui.boardView !== "day" && !ui.boardTeam) {
      if (data.boardError && !knownTeams().length) return { body: boardProblem() };
      if (!data.board && !data.day) return { body: busy("Reading your teams", "lede") };
      return { body: teamList(website) };
    }
    const mode = ui.boardView === "ranks" ? "ranks" : ui.boardView === "members" ? "members" : "day";
    const view = boardChoice("board-view", [["day", "Day"], ["ranks", "Ranks"], ["members", "Members"]], mode);
    if (mode === "members") {
      const toolbar = `${teamMenu()}${view}`;
      const ready = data.board?.team === ui.boardTeam || data.day?.team?.slug === ui.boardTeam;
      if (data.boardError && !ready) return { toolbar, body: boardProblem() };
      if (!ready) return { toolbar, body: busy("Reading the team", "lede") };
      return { toolbar, body: teamManage(data.board?.website || data.day?.website || website) };
    }
    if (mode === "ranks") {
      const toolbar = `${teamMenu()}${view}${periodChoices()}`;
      const name = knownTeams().find((team) => team.slug === ui.boardTeam)?.name || "your team";
      if (data.boardError) return { toolbar, body: boardProblem() };
      if (!data.board || data.board.team !== ui.boardTeam) return { toolbar, body: busy("Reading the board", "lede") };
      return { toolbar, body: ranksBody(data.board.board.entries, name) };
    }
    return dayView(`${teamMenu()}${view}`);
  }

"""##
}
