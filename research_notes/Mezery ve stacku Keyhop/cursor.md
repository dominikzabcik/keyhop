# Cursor login, usage, and TypeScript SDK gaps for Keyhop

Research date: 3 October 2026. Pages with no visible date are marked "undated page, fetched 3 Oct 2026". Keyhop's current behavior (state.vscdb `cursorAuth/*`, `cli-config.json` `authInfo`, unreleased `~/.cursor/sdk/auth.json` swap, CSV `strategy=tokens`, `usage-summary`) is the baseline and is not re-cited as a Cursor source.

## Did Cursor change where logins live in 2026?

### Takeaway
Official 2026 docs still put the TypeScript SDK browser login at `~/.cursor/sdk/auth.json` and the CLI config at `~/.cursor/cli-config.json`. They also added a separate CLI file store (`AGENT_CLI_CREDENTIAL_STORE=file`) and still treat the macOS keychain as the CLI default. No official 2026 source says the editor left `state.vscdb` or that `cursorAuth/*` keys were renamed.

### Cited Findings
- SDK browser login persists a minted user API key at `~/.cursor/sdk/auth.json` by default. `Cursor.auth.login()` / `status()` / `logout()` shipped in `@cursor/sdk` 1.0.27. The changelog page has version numbers and no calendar dates. — [SDK changelog](https://cursor.com/docs/sdk/changelog) (undated page, fetched 3 Oct 2026); [TypeScript SDK](https://cursor.com/docs/sdk/typescript) (undated page, fetched 3 Oct 2026)
- On-disk shape in the published 1.0.27 types, interface `StoredSdkCredentials`: `version: 1`, `backendUrl` (key is paired to that backend), `apiKey`, optional `apiKeyExpiresAtMs` (absent if the key never expires), optional `email`, `createdAtMs`. Session tokens are dropped after the key is minted. `FileCredentialStore` writes owner-only `0600` file / `0700` directory and treats a foreign or corrupt file as logged out. `getDefaultSdkAuthPath()` is documented only as `~/.cursor/sdk/auth.json`. A caller can pass another `FileCredentialStore` path, `InMemoryCredentialStore`, or `store: null` (key returned, not written). — [@cursor/sdk@1.0.27 credential-store.d.ts](https://cdn.jsdelivr.net/npm/@cursor/sdk@1.0.27/dist/cjs/auth/credential-store.d.ts) (package version 1.0.27; file has no date)
- Resolution order in the current docs: explicit `apiKey`, then `CURSOR_API_KEY`, then the stored login. The stored file does not read the Cursor app install. — [TypeScript SDK](https://cursor.com/docs/sdk/typescript) (undated page, fetched 3 Oct 2026)
- CLI config file, official: macOS/Linux `~/.cursor/cli-config.json`, Windows `$env:USERPROFILE\.cursor\cli-config.json`, project `<repo>/.cursor/cli.json` (permissions only). Overrides: `CURSOR_CONFIG_DIR`, and on Linux/BSD `$XDG_CONFIG_HOME/cursor/cli-config.json`. Schema version is `1`. The published field list does not include `authInfo`. — [CLI configuration](https://cursor.com/docs/cli/reference/configuration) (undated page, fetched 3 Oct 2026)
- CLI auth page says browser login stores credentials "securely" locally and does not name a path, keychain, or `auth.json`. API keys are `CURSOR_API_KEY` or `agent --api-key`. — [CLI authentication](https://cursor.com/docs/cli/reference/authentication) (undated page, fetched 3 Oct 2026)
- 29 June 2026: `AGENT_CLI_CREDENTIAL_STORE=file` stores CLI credentials unencrypted in an owner-only file so sandboxes can skip the macOS keychain. The changelog does not name the filename. — [CLI changelog, 29 June 2026 release](https://cursor.com/docs/cli/changelog)
- 20 July 2026: macOS keychain failures at CLI startup now print a cause (locked keychain, log out and back in) instead of a raw exit code. — [CLI changelog, 20 July 2026 release](https://cursor.com/docs/cli/changelog)
- 11 August 2026: CLI login enforces MDM sign-in policy (organization, team, email, domain allowlists). Windows uninstall can optionally delete Cursor user data, including the `~/.cursor` folder "that stores CLI credentials". — [CLI changelog, 11 August 2026 release](https://cursor.com/docs/cli/changelog)
- 4 August 2026, Cursor staff (@mohitjain) on a CLI bug with `agent` 2026.07.23: default store is the macOS login keychain. File mode is `export AGENT_CLI_CREDENTIAL_STORE=file` then `agent login`, and "Tokens land in `~/.cursor/auth.json`". Keychain items named in the same post: service `cursor-access-token`, `cursor-refresh-token`, `cursor-api-key`, account `cursor-user`. The reporter's login URL was `https://cursor.com/loginDeepControl?challenge=…&uuid=…&mode=login&redirectTarget=cli`. — [Forum thread, created 3 August 2026](https://forum.cursor.com/t/errsecitemnotfound-couldnt-find-your-saved-login-in-the-macos-keychain/167325)
- 6 July 2026: concurrent CLI processes could corrupt `cli-config.json`; writes are now temp file plus atomic rename. That is the config file, not a new credential path. — [CLI changelog, 6 July 2026 release](https://cursor.com/docs/cli/changelog)
- 6 June 2026, third party (caam): claims cursor-agent moved credentials to `~/.cursor/cli-config.json` under `authInfo`, and that `auth.json` is legacy. Not a Cursor doc. — [coding_agent_account_manager commit 65a9fb6](https://github.com/Dicklesworthstone/coding_agent_account_manager/commit/65a9fb6f090c7ecc68b531c5a4e410ca2dc4e49f)
- 4 May 2026, third party: claims the auth file is `~/.config/cursor/auth.json` and that `~/.cursor/auth.json` is "CLI config / stats cache". Conflicts with the 4 August 2026 staff post. — [upflow commit 5b23d41](https://github.com/coji/upflow/commit/5b23d417b7f64b984da979b2e7e0f4305d93aacc)
- No official changelog or docs page found that moves editor logins out of `state.vscdb` or renames `cursorAuth/accessToken`. Third-party collectors in 2026 still read `cursorAuth/accessToken` from `User/globalStorage/state.vscdb` and fall back to `authInfo.authId` in `cli-config.json`. — [agent-walker docs/cursor.md](https://github.com/miiiiiiich/agent-walker/blob/main/docs/cursor.md) (no date on the page)

### Inferences
- Keyhop's unreleased `~/.cursor/sdk/auth.json` snapshot matches the default SDK file and the 1.0.27 `StoredSdkCredentials` fields. A version bump past `1` would make Keyhop ignore the file, because it accepts only `version == 1`. Nothing published shows that bump.
- Swapping `authInfo` inside `cli-config.json` is what Keyhop already does, and a June 2026 third party agrees, but Cursor's own config schema does not document `authInfo`. Staff in August 2026 describe the live CLI secret as the keychain, or `~/.cursor/auth.json` when file mode is on. Those are different stores from `cli-config.json`.
- `CURSOR_CONFIG_DIR` and `$XDG_CONFIG_HOME/cursor/cli-config.json` are official locations Keyhop's hardcoded `~/.cursor/cli-config.json` path does not follow.

### Gaps
- No Cursor doc names the `AGENT_CLI_CREDENTIAL_STORE=file` filename. The `~/.cursor/auth.json` path is a staff forum post, not the changelog.
- No official statement on whether a normal `agent login` in 2026 still writes `authInfo` into `cli-config.json` in addition to the keychain.
- Linux/Windows CLI secret location when the keychain is unavailable, other than the file-mode env var, is not specified. The May 2026 `~/.config/cursor/auth.json` claim is unverified and conflicts with staff.
- `getDefaultSdkAuthPath()` in the 1.0.27 types does not document an env override. Not re-checked against the 1.0.31 package tarball.
- Editor `state.vscdb` key list: no 2026 primary source confirming the set is unchanged.

## What does the TypeScript SDK document for auth, and what does a file swap miss?

### Takeaway
The SDK has three credential kinds and one default file. A swap of `~/.cursor/sdk/auth.json` covers only the default browser-minted user key. It does not cover env keys, service-account keys, team admin keys, a custom store, or the editor/CLI session.

### Cited Findings
- Accepted keys, both local and cloud: user API keys (Dashboard → API Keys) and service-account API keys (Team settings). Team Admin API keys are not supported. User keys bill to that user's plan. Service-account keys bill to the owning team's pool. — [TypeScript SDK](https://cursor.com/docs/sdk/typescript) (undated page, fetched 3 Oct 2026)
- `Cursor.auth.login(options)` opens the website login, waits, mints a user API key (default TTL 90 days), stores it, and returns `{ apiKey, email?, apiKeyExpiresAtMs }`. Options: `backendUrl` (`CURSOR_BACKEND_URL`, else production), `websiteUrl` (`CURSOR_WEBSITE_URL`, else production), `openBrowser`, `onLoginUrl`, `signal`, `store`, `apiKeyName`, `apiKeyTtlMs`. Status is `{ status: "logged-in", backendUrl, email?, apiKeyExpiresAtMs? }` or `{ status: "logged-out" }`. — [TypeScript SDK](https://cursor.com/docs/sdk/typescript) (undated page, fetched 3 Oct 2026)
- Login handshake in 1.0.27 types: PKCE-style, same flow as the CLI. Browser goes to the portal `/loginDeepControl` with a challenge and one-time `uuid` (`redirectTarget=sdk`). SDK polls `POST /auth/poll` with the verifier in the JSON body. A backend that 404s that POST falls back once to `GET /auth/poll?uuid=…&verifier=…`. Poll returns null on abort, ~20 minute timeout, or 3 consecutive non-404 errors. The session token is used once to call `DashboardService/CreateUserApiKey`, then discarded. — [login-flow.d.ts](https://cdn.jsdelivr.net/npm/@cursor/sdk@1.0.27/dist/cjs/auth/login-flow.d.ts); [login.d.ts](https://cdn.jsdelivr.net/npm/@cursor/sdk@1.0.27/dist/cjs/auth/login.d.ts); [mint-api-key.d.ts](https://cdn.jsdelivr.net/npm/@cursor/sdk@1.0.27/dist/cjs/auth/mint-api-key.d.ts) (package 1.0.27, no file dates)
- Service accounts are Enterprise, non-human, no extra seat, consume the team usage pool. Created at Dashboard → Settings → API Keys → Service Accounts. The key is shown once. CLI use is `CURSOR_API_KEY` only. Cloud Agents API example is `POST https://api.cursor.com/agents` with `Authorization: Bearer`. The service-account page does not mention `sdk/auth.json` or `cli-config.json`. — [Service accounts](https://cursor.com/docs/account/enterprise/service-accounts) (undated page, fetched 3 Oct 2026)
- Team Admin keys for the Admin API use format `crsr_…` and scope `admin:*`, sent as Basic auth to `https://api.cursor.com`. The API overview says those keys are not the Cloud Agents user/service-account keys. The SDK repeats that Team Admin keys are not accepted. — [Cursor APIs overview](https://cursor.com/docs/api) (undated page, fetched 3 Oct 2026); [TypeScript SDK](https://cursor.com/docs/sdk/typescript)
- Cloud vs local does not change where the key lives. The same user or service-account key is valid for both. Difference that is documented: `cloud.openAsCursorGithubApp` defaults to true for service-account keys and false for user keys (SDK 1.0.27). — [SDK changelog 1.0.27](https://cursor.com/docs/sdk/changelog); [TypeScript SDK](https://cursor.com/docs/sdk/typescript)
- 1.0.30: long-running local agents refresh a short-lived access token before it expires so runs longer than an hour do not fail auth. Cloud runs are unaffected. The note does not say the process re-reads `auth.json`. — [SDK changelog 1.0.30](https://cursor.com/docs/sdk/changelog)
- Self-hosted workers take a separate token file: `agent worker --auth-token-file`. Cloud Agents pool endpoints require a service-account key and can mint 1-hour sub-tokens. — [CLI parameters](https://cursor.com/docs/cli/reference/parameters) (undated page, fetched 3 Oct 2026); [Cloud Agents API](https://cursor.com/docs/cloud-agent/api/endpoints) (undated page, fetched 3 Oct 2026)

### Inferences
- File-swapping `~/.cursor/sdk/auth.json` switches the default SDK browser login only. It does not switch a process that already loaded a key, a `CURSOR_API_KEY` in the environment, a service-account key that was never written to that file, a custom `store` path, an in-memory store, or `store: null`.
- It also does not log the editor or `cursor-agent` into that account. The SDK docs say the stored login does not read the app install, and login drops the session token after minting the API key.
- 1.0.30 token refresh is a runtime access token for a local run, not a new on-disk credential. It does not contradict "a process that already loaded the key keeps it until restart."

### Gaps
- Docs do not say whether `Cursor.auth.login()` can mint a service-account key. The types describe a user API key only.
- No doc lists a second default SDK credential path on Windows or under `XDG_CONFIG_HOME`.
- Worker `--auth-token-file` contents and path defaults are not specified on the parameters page beyond "a file containing the worker auth token".

## Are there new usage or billing endpoints, CSV columns, or SDK usage exports the CSV parser would miss?

### Takeaway
Cursor's own docs still do not publish `usage-summary` or `export-usage-events-csv`. Staff say the personal CSV Cost column was wiped on 31 July 2026 and restored on 1 August 2026, with included rows as a word such as "Included" and on-demand rows as dollars. Enterprise Admin/Analytics APIs are a different host and key. `Agent.getUsage()` is per agent, not an account export. No official source lists CSV columns or a separate SDK usage export.

### Cited Findings
- SDK billing text: SDK runs use the same pricing, request pools, and Privacy Mode as IDE and Cloud Agents. "Spend shows up in your team's usage dashboard under the SDK tag." Per-run token counts are stream events. Billed dollars are `Agent.getUsage()`, not a new account CSV. — [TypeScript SDK](https://cursor.com/docs/sdk/typescript) (undated page, fetched 3 Oct 2026)
- `Agent.getUsage()` / `Agent.getUsage(agentId)`: cloud returns per-run rows, local returns per-turn rows (local added in 1.0.27; cloud billed usage added in 1.0.25, when local threw). `runId` filters one entry. `UsageCost` is `rawCostCents` (undiscounted model cost; 0 for request-priced usage) and `chargedCents` (discounts and the Cursor Token Fee included). `cost` is absent until it settles. `chargedCents` is 0 for plan-included, BYOK, and credit-grant usage. This is not an account-wide export. — [TypeScript SDK](https://cursor.com/docs/sdk/typescript); [SDK changelog 1.0.22, 1.0.25, 1.0.27](https://cursor.com/docs/sdk/changelog)
- Official APIs that do exist, all Enterprise, on `https://api.cursor.com`, Basic auth with an admin key, not the browser session cookie: Admin API `POST /teams/filtered-usage-events` (hourly aggregate, 60 req/min, poll at most hourly) and `POST /teams/daily-usage-data`; organization counterparts `POST /organizations/filtered-usage-events`, `POST /organizations/pooled-usage`, `POST /organizations/daily-usage-data`, `POST /organizations/spend`. Event fields named on the Admin API page include `tokenUsage.inputTokens`, `outputTokens`, `cacheWriteTokens`, `cacheReadTokens`, `chargedCents`, `cursorTokenFee`. Analytics API is team metrics (`/analytics/team/dau`, models, and so on), not a per-request token CSV. — [API overview](https://cursor.com/docs/api); [Admin API](https://cursor.com/docs/account/teams/admin-api); [Organization API](https://cursor.com/docs/account/organizations/organization-admin-api); [Analytics API](https://cursor.com/docs/account/teams/analytics-api) (all undated pages, fetched 3 Oct 2026)
- None of those official pages mention `https://cursor.com/api/usage-summary` or `https://cursor.com/api/dashboard/export-usage-events-csv`.
- 31 July 2026, staff (@kevinn): a change that day made the Usage page tokens-only for self-serve plans, including Teams. Staff first said the CSV Cost column still had dollars for on-demand and the word "Included" for plan usage, then said the Cost column was removed and the CSV no longer contained dollar costs. A user the same day said `https://cursor.com/api/dashboard/get-filtered-usage-events` returned `chargedCents: 0` and `usageBasedCosts: "$0.00"`, including historical on-demand rows. Staff called that intentional for the dashboard Usage endpoint and pointed Teams admins at the Admin API. — [Forum thread, created 31 July 2026](https://forum.cursor.com/t/usage-page-to-token-amount-what/167153)
- 1 August 2026: a Teams admin's CSV for 1–31 July 2026 still had a Kind column with "On-Demand" and "Included", and a Cost column of `0` on on-demand lines. Staff then said wiping CSV dollars was an inadvertent side effect and, at 19:59 UTC, that the change was reversed: Cost column back on `https://cursor.com/dashboard/usage`, dollar amounts back in the CSV including past dates. — [Forum page 2](https://forum.cursor.com/t/usage-page-to-token-amount-what/167153?page=2); [staff post 64](https://forum.cursor.com/t/usage-page-to-token-amount-what/167153/64)
- 2 August 2026, a user: `https://cursor.com/api/dashboard/export-usage-events-csv` "now exports the cost." 3 August 2026, staff: the 1 August fix restored the table Cost column and CSV dollars, not the dollar chart. Included usage stays the word "Included". On-demand dollars stay in the table, the CSV for any date range, the Spending page, and the invoice. The daily dollar chart for individual plans is not coming back. — [Forum page 3](https://forum.cursor.com/t/usage-page-to-token-amount-what/167153?page=3)
- The query string `strategy=tokens` does not appear in the staff posts. Users cite the path without it.
- Third parties, not Cursor, describe extra CSV headers and a column-semantics fight. One parser maps columns by header name and treats `Input (w/ Cache Write)` and `Input (w/o Cache Write)` as disjoint buckets whose sum, plus cache read and output, equals `Total Tokens`. Another older comment in a published `.d.ts` lists `Date, Model, Input (w/ Cache Write), Input (w/o Cache Write), Cache Read, Output Tokens, Total Tokens, Cost, Cost to you` with no Kind column. A tokscale change says a "v3" export added Cloud Agent ID and Automation ID. None of this is an official column list. — [agent-walker docs/cursor.md](https://github.com/miiiiiiich/agent-walker/blob/main/docs/cursor.md); [tokscale cursor.d.ts on unpkg](https://app.unpkg.com/@tokscale/cli@1.2.7/files/dist/cursor.d.ts) (package version, no date); [tokscale PR 434](https://github.com/junhoyeo/tokscale/pull/434); [tokscale PR 1154](https://github.com/junhoyeo/tokscale/pull/1154)
- "Cost to you" as a dashboard column is older than 2026 (forum thread from August 2025). No 2026 staff post says that column returned in the CSV. — [Forum, 16 August 2025](https://forum.cursor.com/t/api-cost-vs-cost-to-you-removed/130201)

### Inferences
- Keyhop's required headers (Date, Model, both Input columns, Cache Read, Output Tokens, Cost) still match what staff and users called the CSV in August 2026: a Cost column, a Kind column, "Included" vs on-demand dollars. Extra columns do not by themselves break a header-name parser. A renamed required header would.
- If the two Input columns are now disjoint, Keyhop's `cacheWrite = max(with − without, 0)` undercounts. That is a third-party claim. Cursor has not published the formula. Keyhop's own fixture treats the "with" column as a superset (`1500` with, `1000` without, total `21800 = 1500 + cache read + output`). Do not treat the third-party formula as confirmed.
- SDK spend is supposed to appear on the team usage dashboard under an "SDK tag". The docs do not say the tag is a CSV column, a Kind value, or a filter that drops those rows from `export-usage-events-csv`. There is no documented second export for SDK-only usage. `getUsage()` cannot fill an account-wide gap.
- Enterprise `api.cursor.com` usage events are invisible to a parser that only GETs the cookie CSV. They are also the only documented place staff still pointed to for team cost fields on 31 July, before the CSV restore.

### Gaps
- No official column list, and no post-August 2026 sample CSV, so a later rename of Input or Cost is unconfirmed.
- Whether `get-filtered-usage-events` got its `chargedCents` values back after 1 August 2026 is not in the staff follow-up. That endpoint is also absent from the public API docs.
- `usage-summary` response shape (Auto vs API percents, cents caps) has no official schema and no 2026 source showing a new pool.
- Whether `?strategy=tokens` is still required, or what other `strategy` values exist, is not documented.

## Did cursor-agent or the SDK start storing credentials somewhere else?

### Takeaway
Yes for the CLI, as an additional store, not as a documented replacement of `cli-config.json`. The SDK's default file is still `~/.cursor/sdk/auth.json`. The new CLI places Keyhop does not touch are the macOS keychain and `~/.cursor/auth.json` in file mode.

### Cited Findings
- Default CLI secret, staff, 4 August 2026: macOS keychain items `cursor-access-token`, `cursor-refresh-token`, `cursor-api-key` (account `cursor-user`). File mode: `~/.cursor/auth.json`. — [Forum, 4 August 2026](https://forum.cursor.com/t/errsecitemnotfound-couldnt-find-your-saved-login-in-the-macos-keychain/167325)
- Same file mode, without a path, shipped 29 June 2026 as `AGENT_CLI_CREDENTIAL_STORE=file`. — [CLI changelog](https://cursor.com/docs/cli/changelog)
- 29 September 2026, a user asked staff to relocate that `auth.json` off `~/.cursor` for shared CI runners. No answer on that page. — [Same forum thread](https://forum.cursor.com/t/errsecitemnotfound-couldnt-find-your-saved-login-in-the-macos-keychain/167325)
- SDK default remains `~/.cursor/sdk/auth.json`, with an explicit custom `store` for anywhere else, including memory or nowhere. — [TypeScript SDK](https://cursor.com/docs/sdk/typescript); [credential-store.d.ts @1.0.27](https://cdn.jsdelivr.net/npm/@cursor/sdk@1.0.27/dist/cjs/auth/credential-store.d.ts)
- CLI config can live outside `~/.cursor` when `CURSOR_CONFIG_DIR` or `XDG_CONFIG_HOME` is set. The official schema still has no `authInfo` field. — [CLI configuration](https://cursor.com/docs/cli/reference/configuration)
- `agent worker --auth-token-file` is a separate worker credential, documented as a flag only. — [CLI parameters](https://cursor.com/docs/cli/reference/parameters)

### Inferences
- A hop that rewrites `cli-config.json` `authInfo` and `sdk/auth.json` still leaves a keychain-backed `agent` on the previous account, and leaves a file-mode CLI on the previous account if `~/.cursor/auth.json` is the file staff named.
- `~/.cursor/auth.json` (CLI file mode) and `~/.cursor/sdk/auth.json` (SDK) are different paths. Swapping one does not swap the other.

### Gaps
- No staff confirmation that `cli-config.json` `authInfo` stopped being read.
- No schema for `~/.cursor/auth.json` (field names). Not safe to assume it matches `StoredSdkCredentials` or the editor tokens.
- No doc for the Linux secret-service / Windows credential-manager equivalent of the macOS keychain items.

## Any breaking changes to the login deep link cursor://cursorAuth?

### Takeaway
No 2026 source says `cursor://cursorAuth` changed or was removed. CLI and SDK login in 2026 use the website `/loginDeepControl` page plus `/auth/poll`, which is a different handoff from the editor deep link.

### Cited Findings
- 1.0.27 SDK types: browser login opens `/loginDeepControl` with challenge, uuid, and `redirectTarget=sdk`, then `POST /auth/poll` (GET fallback if POST 404s). The comment says this is the same PKCE flow as the CLI. The types do not mention `cursor://`. — [login-flow.d.ts @1.0.27](https://cdn.jsdelivr.net/npm/@cursor/sdk@1.0.27/dist/cjs/auth/login-flow.d.ts)
- 3 August 2026, a failing CLI login printed `https://cursor.com/loginDeepControl?challenge=…&uuid=…&mode=login&redirectTarget=cli`, then failed to store tokens in the keychain. The protocol handler in that report is the website, not `cursor://cursorAuth`. — [Forum](https://forum.cursor.com/t/errsecitemnotfound-couldnt-find-your-saved-login-in-the-macos-keychain/167325)
- 6 July 2026 CLI: `agent login` can show a QR code for "the same login URL" (`q`). Non-interactive sessions still print the URL. Not a new scheme. — [CLI changelog, 6 July 2026](https://cursor.com/docs/cli/changelog)
- Editor login bugs in 2026 forum threads are "browser says All set, desktop stays logged out", blamed by staff on the `cursor://` protocol handler, proxy support, or HTTP/2 (`cursor.general.disableHttp2`). They do not describe a new query shape. Threads checked: [callback not reaching the client](https://forum.cursor.com/t/the-login-result-on-the-webpage-cannot-be-transmitted-to-the-client/167317) (no creation date in the fetched extract), [callback fails to sync](https://forum.cursor.com/t/login-issue-web-login-successful-but-fails-to-sync-callback-to-cursor-desktop/158916), [stuck after browser auth, Cursor 3.9.16 HTTP/2](https://forum.cursor.com/t/desktop-app-stuck-on-login-screen-after-successful-browser-authentication/164774). Dates were not on the fetched extracts except where noted elsewhere; treat the last two as undated fetches on 3 Oct 2026 unless the page header is re-read.
- CLI and SDK changelogs through 26 August 2026 (CLI) and 1.0.31 (SDK) contain no entry about `cursor://cursorAuth`, `route=login`, or `accessToken`/`refreshToken` query items. — [CLI changelog](https://cursor.com/docs/cli/changelog); [SDK changelog](https://cursor.com/docs/sdk/changelog)

### Inferences
- Keyhop's handoff (`cursor://cursorAuth/?route=login&accessToken&refreshToken`) is still an undocumented editor route. Nothing in the 2026 changelogs says it broke. Nothing confirms it still works on current builds either.
- CLI/SDK account switches cannot be done by opening that deep link. They mint or store an API key through `/loginDeepControl` and `/auth/poll`, or they read the keychain / `~/.cursor/auth.json` / `sdk/auth.json`.

### Gaps
- No official reference for the editor deep link's query parameters, so a silent break would not show up in these docs.
- Forum threads about the desktop callback were not fully dated in this pass, and they do not print the `cursor://` URL they failed on.
