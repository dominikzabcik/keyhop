# Other coding agents: auth paths and 2026 changes

Research date: 3 October 2026. Confirmed facts are under Cited Findings. Anything that follows from those facts, or that comes only from a non-official write-up, is under Inferences or is labeled as a third-party claim. No file path below is inferred from a product name.

## Did Gemini CLI, OpenCode, Pi, Windsurf, or Codebuff move their auth path, rename, or add a usage export in 2026?

### Takeaway

None of the five has an official 2026 doc that moves the login file Keyhop already swaps. Gemini CLI, OpenCode, and Pi still document the same default files. Codebuff’s live docs still use `~/.config/manicode`. Windsurf’s current docs still use `~/.codeium/`, but they no longer describe the `config.json` login key, so that part of Keyhop is unverified against current docs. The changes that can break or extend Keyhop are Gemini’s optional encrypted OAuth store and 30-day session cleanup, OpenCode’s `OPENCODE_AUTH_CONTENT` override plus a May 2026 session-usage database, Pi’s manual `/export`, and Codebuff’s Freebuff naming beside the old folder.

### Cited Findings

#### Gemini CLI

- The current FAQ still says third-party tools must not harvest or piggyback on Gemini CLI OAuth to reach Google’s backend, and it names Claude Code, OpenClaw, and OpenCode as examples. The supported alternative is a Vertex AI or Google AI Studio API key. The published page says “Last updated: Apr 10, 2026.” — [Gemini CLI FAQ](https://geminicli.com/docs/resources/faq/)
- The same prohibition is in the repository FAQ, under the heading “Why can't I use third-party software like Claude Code, OpenClaw, or OpenCode with Gemini CLI?” — [docs/resources/faq.md](https://github.com/google-gemini/gemini-cli/blob/HEAD/docs/resources/faq.md)
- Individual accounts still use “Sign in with Google.” API-key and Vertex AI remain separate methods. — [Authentication](https://github.com/google-gemini/gemini-cli/blob/main/docs/get-started/authentication.mdx)
- Default state is still `~/.gemini`. `GEMINI_CLI_HOME` replaces the home directory, and the CLI creates a `.gemini` directory inside that path. — [Enterprise](https://geminicli.com/docs/cli/enterprise/)
- Current source still defines `oauth_creds.json` via `getOAuthCredsPath()` and `google_accounts.json` via `getGoogleAccountsPath()`, both under the global `.gemini` directory from `homedir()` (`GEMINI_CLI_HOME`, else the OS home). — [storage.ts](https://github.com/google-gemini/gemini-cli/blob/07ab16db/packages/core/src/config/storage.ts), [paths.ts](https://github.com/google-gemini/gemini-cli/blob/caa04664/packages/core/src/utils/paths.ts)
- When `GEMINI_FORCE_ENCRYPTED_FILE_STORAGE` is exactly `true`, current `oauth2.ts` loads credentials from `OAuthCredentialStorage` and does not add `oauth_creds.json` to the file list. Without the flag, it still reads `Storage.getOAuthCredsPath()`. — [oauth2.ts](https://github.com/google-gemini/gemini-cli/blob/main/packages/core/src/code_assist/oauth2.ts)
- The encrypted-storage class migrates `oauth_creds.json` and then deletes that file. The env var name is `GEMINI_FORCE_ENCRYPTED_FILE_STORAGE`. — [PR 8101](https://github.com/google-gemini/gemini-cli/pull/8101), [oauth-credential-storage.ts](https://github.com/google-gemini/gemini-cli/blob/f8541cf7/packages/core/src/code_assist/oauth-credential-storage.ts)
- Official session docs: history, including token-usage statistics, is stored in `~/.gemini/tmp/<project_hash>/chats/`. Default retention is 30 days (`general.sessionRetention.maxAge` defaults to `"30d"`). — [Session management](https://geminicli.com/docs/cli/session-management/)
- Current `chatRecordingService.ts` writes session files as `.jsonl` under the project temp `chats` directory. — [chatRecordingService.ts](https://github.com/google-gemini/gemini-cli/blob/main/packages/core/src/services/chatRecordingService.ts)
- `/stats` still shows total token usage inside the CLI. Cached-token counts are documented for API-key and Vertex users, not for OAuth users. — [FAQ](https://geminicli.com/docs/resources/faq/)
- `/chat share [filename]` exports the current conversation to Markdown or JSON. A separate PR adds `/export-session` and `gemini --session-file`. — [commands.md](https://github.com/google-gemini/gemini-cli/blob/HEAD/docs/reference/commands.md), [PR 26514](https://github.com/google-gemini/gemini-cli/pull/26514)

#### OpenCode

- Official troubleshooting still puts auth at `~/.local/share/opencode/auth.json` on macOS and Linux, and `%USERPROFILE%\.local\share\opencode` on Windows. The same directory holds `project/` session and message data. That page does not name `XDG_DATA_HOME` or `OPENCODE_AUTH_PATH`. — [Troubleshooting](https://opencode.ai/docs/troubleshooting/)
- Current `dev` `packages/opencode/src/auth/index.ts` still sets `const file = path.join(Global.Path.data, "auth.json")`. If `OPENCODE_AUTH_CONTENT` is set and parses as JSON, `Auth.all()` returns that object and does not read the file. — [auth/index.ts on dev](https://github.com/anomalyco/opencode/blob/dev/packages/opencode/src/auth/index.ts)
- PR #18563 (opened 21 March 2026, closed 15 May 2026) proposed `OPENCODE_AUTH_PATH`. The `dev` auth file above does not reference that variable. — [PR 18563](https://github.com/anomalyco/opencode/pull/18563), [issue 18562](https://github.com/anomalyco/opencode/issues/18562)
- Commit `36d40fe` on 12 May 2026 (“Track session usage totals”) adds a SQL migration `20260510033149_session_usage`. That is an internal session-usage total, not a documented user export. — [commit 36d40fe](https://github.com/anomalyco/opencode/commit/36d40fee4dec052e5c81664390e61a74705dfa13)
- Issue #9281, a unified `/usage` view of provider quotas, was still an open feature request in the results used here. — [issue 9281](https://github.com/anomalyco/opencode/issues/9281)
- Desktop UI state is separate from `auth.json`: `opencode.settings.dat`, `opencode.global.dat`, and `opencode.workspace.*.dat`, found by searching Application Support / `%APPDATA%`. Config remains `~/.config/opencode/opencode.jsonc`. — [Troubleshooting](https://opencode.ai/docs/troubleshooting/)
- The repo linked from the docs is still `anomalyco/opencode`. — [Troubleshooting](https://opencode.ai/docs/troubleshooting/)

#### Pi

- Current docs still put saved API keys and OAuth in `<agent-dir>/auth.json`. The agent directory defaults to `~/.pi/agent`. `PI_CODING_AGENT_DIR` replaces that directory. — [Configuration](https://pi.dev/docs/latest/configuration)
- Sessions default to `~/.pi/agent/sessions/`, grouped by working directory. Overrides, in order: `--session-dir`, then `PI_CODING_AGENT_SESSION_DIR`, then the `sessionDir` setting. — [Sessions](https://pi.dev/docs/latest/sessions), [Environment variables](https://pi.dev/docs/latest/environment-variables)
- `/export` writes the current session as HTML or JSONL. `/share` uploads it. This is a manual transcript export, not a quota API. — [Sessions](https://pi.dev/docs/latest/sessions)
- `PI_CODING_AGENT_DIR` is the agent directory itself. The default path appends `/agent`; the env var does not. A June 2026 note quotes `getAgentDir()` from `packages/coding-agent/src/config.ts`. — [shukebeta, 17 June 2026](https://blog.shukebeta.com/2026/06/17/picodingagentdir-points-at-the-agent-dir-not-the-pi-home/)
- `PI_CONFIG_DIR` does not relocate the coding agent. Maintainer reply, 19 March 2026: “`PI_CONFIG_DIR` is for pods, not for the coding agent.” — [badlogic/pi-mono#2390](https://github.com/badlogic/pi-mono/issues/2390)
- Issue #3793 (April 2026) is filed against the repo GitHub identifies as `earendil-works/pi`, while the issue URL is still under `badlogic/pi-mono`. The product name in the docs is still Pi. — [earendil-works/pi issue 3793](https://github.com/badlogic/pi-mono/issues/3793), [pi.dev configuration](https://pi.dev/docs/latest/configuration)

#### Windsurf

- Current plugin docs are on `docs.devin.ai` and say “Windsurf Plugin (formerly Codeium).” Sign-in is the editor UI, not a documented `config.json` key. — [Getting started](https://docs.devin.ai/windsurf/plugins/getting-started)
- Devin CLI’s Windsurf import table names `~/.codeium/<channel>/` for skills and MCP: stable `~/.codeium/windsurf/`, next `~/.codeium/windsurf-next/`, insiders `~/.codeium/windsurf-insiders/`. It does not name `config.json`, a login key, or `CODEIUM_HOME`. — [read-config-from](https://docs.devin.ai/cli/reference/configuration/read-config-from)
- Cascade MCP docs still name `~/.codeium/mcp_config.json`. That file is MCP servers, not the account login. — [Cascade MCP](https://docs.devin.ai/windsurf/plugins/cascade/mcp)
- No official page in this pass names a usage-transcript export or a token ledger for Windsurf.

#### Codebuff

- Live Codebuff docs still say files live at `~/.config/manicode`, including the `codebuff` binary, and chats live at `~/.config/manicode/projects/<project>/chats`. The same page says prompts are sent to Freebuff. It does not name `credentials.json`, `FREEBUFF_CONFIG_DIR`, or a usage-export command. — [Troubleshooting](https://www.codebuff.com/docs/advanced/troubleshooting), [Quick start](https://www.codebuff.com/docs/help/quick-start)
- The GitHub project page is `CodebuffAI/codebuff` and the description says “Contribute to CodebuffAI/freebuff development.” The client name in the docs is still Codebuff. — [CodebuffAI/codebuff](https://github.com/CodebuffAI/codebuff)
- A third-party docs mirror quotes SDK `getConfigDir()` as `~/.config/manicode` plus an environment suffix (`manicode-dev`, `manicode-staging`) and `credentials.json` inside it. A different page on the same mirror says `~/.config/codebuff/credentials.json`. Neither page is `codebuff.com`. — [mirror: credentials](https://mintlify.wiki/CodebuffAI/codebuff/advanced/credentials), [mirror: configuration](https://mintlify.wiki/CodebuffAI/codebuff/cli/configuration)
- OpenUsage, a third-party reader, still scans `~/.config/manicode`, `manicode-dev`, and `manicode-staging`, and also `CODEBUFF_DATA_DIR`. It says the `manicode` directory name is historical. — [OpenUsage Codebuff](https://openusage.sh/docs/providers/codebuff/)
- `FREEBUFF_CREDENTIALS_PATH` defaulting to `$HOME/.config/manicode/credentials.json` is an env var of the third-party `freebuff-proxy`, not of the Codebuff docs. — [ferdiunal/freebuff-proxy](https://github.com/ferdiunal/freebuff-proxy)

### Inferences

- Gemini file swap of `oauth_creds.json` still matches the default path. It stops matching as soon as `GEMINI_FORCE_ENCRYPTED_FILE_STORAGE=true`, because that mode stops reading the JSON file and deletes it after migration. The on-disk path of the encrypted store is not named in the user docs read here.
- Gemini usage from local transcripts still has a documented directory. A reader that only accepts `.json`, or that assumes transcripts older than 30 days are still present, will under-count. `/chat share` is an explicit export; it is not the ledger Keyhop already reads.
- OpenCode’s default auth file is unchanged. A set `OPENCODE_AUTH_CONTENT` makes a file swap invisible to the process. `OPENCODE_AUTH_PATH` should not be treated as shipped.
- The May 2026 session-usage migration means OpenCode now keeps a usage total in its own database as well as message storage. The official troubleshooting page still points usage readers at `project/.../storage/`, not at a new export file.
- Pi’s auth and session paths match what Keyhop uses. `/export` is an extra transcript format, not a replacement ledger. Pointing `PI_CODING_AGENT_DIR` at `~/.pi` instead of `~/.pi/agent` would miss `auth.json`.
- Windsurf has not published a replacement for `~/.codeium/config.json`. Until an official page names the login field, Keyhop’s swap of that key is an assumption carried forward, not a 2026 confirmation. A third-party reverse-engineering note claims the key moved to `~/Library/Application Support/Windsurf/User/globalStorage/state.vscdb` under `windsurfAuthStatus` — [CASCADE_PROTOCOL.md](https://github.com/rsvedant/opencode-windsurf-auth/blob/master/docs/CASCADE_PROTOCOL.md). That path is not confirmed by Windsurf or Devin docs.
- Codebuff’s on-disk directory name is still `manicode` in the vendor’s own troubleshooting page. “Freebuff” is the name that page uses for the service that receives prompts, and it is the GitHub repo name in the project description. `~/.config/codebuff/credentials.json` appears only on an inconsistent mirror and should not be treated as the new path.
- No official source found here shows that the Codebuff CLI reads `FREEBUFF_CONFIG_DIR`. That variable may be Keyhop’s own lookup only.

### Gaps

- Merge date of the Gemini encrypted-OAuth flag, and the filename it writes, are not in the pages above. Presence in current `main` is confirmed; “added in 2026” is not.
- Whether PR #26514 (`/export-session`) merged is not confirmed. The command reference that was fetched documents `/chat share`, not `/export-session`.
- OpenCode `Global.Path.data` resolution (`XDG_DATA_HOME`) was not re-read from `packages/core/src/global.ts` in this pass. Official troubleshooting documents only the default `~/.local/share/opencode/` path.
- No official Windsurf page was found that still names `~/.codeium/config.json` or `CODEIUM_HOME`.
- No official Codebuff page was found that names `credentials.json`. The mirror quote of `sdk/src/credentials.ts` was not re-checked against a current raw file.
- Pi `/export` and the `earendil-works/pi` repo name: the year those shipped is not stated in the docs.

## Is Google's ban on third-party Gemini CLI OAuth still in the current FAQ?

### Takeaway

Yes. The FAQ live on 3 October 2026 still forbids third-party software from using Gemini CLI OAuth credentials to call Google’s backend services. The page’s own “last updated” date is 10 April 2026.

### Cited Findings

- “Using third-party software, tools, or services to harvest or piggyback on Gemini CLI’s OAuth authentication to access our backend services is a direct violation of our applicable terms and policies… If you would like to use a third-party coding agent with Gemini, the supported and secure method is to use a Vertex AI or Google AI Studio API key.” Last updated 10 April 2026. — [FAQ](https://geminicli.com/docs/resources/faq/)
- The repository copy uses the same rule and names Claude Code, OpenClaw, and OpenCode. — [docs/resources/faq.md](https://github.com/google-gemini/gemini-cli/blob/HEAD/docs/resources/faq.md)
- OAuth users still cannot see cached-token stats because the Gemini Code Assist API does not support cached content creation for those accounts. `/stats` remains the in-CLI total. — [FAQ](https://geminicli.com/docs/resources/faq/)

### Inferences

- Keyhop’s refusal to call Gemini quota endpoints with the user’s Gemini CLI OAuth credentials still matches the current FAQ. The FAQ text is about calling backend services with those credentials. It does not mention a desktop tool that only copies `oauth_creds.json` and reads local transcripts.
- The ban is not limited to the three named products. The sentence is “third-party software, tools, or services.”

### Gaps

- Google does not say, in this FAQ, whether swapping the local credential file between accounts the user already signed in is itself a violation when the switcher never calls Google.

## Which adjacent tools have a stable local credential file, and do they fit Keyhop?

### Takeaway

Amp, Devin CLI, and Cline document a local credential file a desktop switcher can own. Antigravity’s normal desktop login is the OS keyring, so it does not. Factory’s official docs only name an API-key environment variable. Aider, Zed, and Continue store provider keys in env, keychain, or a config file, not an account session. Augment’s credential path was not found.

Included only where a vendor doc names a file, or names a first-party account switch. Third-party path claims are marked.

### Cited Findings

#### Amp

- Amp’s security reference: the CLI stores credentials in `~/.local/share/amp/secrets.json` on Linux and macOS, and `%USERPROFILE%\.local\share\amp\secrets.json` on Windows. — [Security reference](https://ampcode.com/security)
- `amp login` adds an account. `amp account list` shows saved accounts. `amp account switch <name>` selects the account used by future CLI processes. A running process keeps the account it started with. `amp logout` removes saved CLI accounts and does not sign out browser or native-app sessions. `AMP_API_KEY`, if set, overrides saved accounts. — [CLI](https://ampcode.com/docs/cli)
- Settings are a different file: `~/.config/amp/settings.json`. — [Settings](https://ampcode.com/docs/cli/settings)

Fit: Amp fits. It has a documented local secrets file and a documented account switch that does not log out other Amp sessions; Keyhop could swap that file or invoke `amp account switch`, and a running `amp` process would not follow the switch until restart.

#### Devin CLI

- After `devin auth login`, the token is in `credentials.toml`: `$XDG_DATA_HOME/devin/credentials.toml` if `XDG_DATA_HOME` is set, otherwise `~/.local/share/devin/credentials.toml`. Windows is `%APPDATA%\devin\credentials.toml`. The docs say the token does not expire by default and that you can copy the file between your own machines. `devin auth logout` removes it. — [Devin auth](https://docs.devin.ai/cli/enterprise/devin-auth)
- User settings, which are not the token, are `~/.config/devin/config.json` (`%APPDATA%\devin\config.json` on Windows). — [Config file](https://docs.devin.ai/cli/reference/configuration/config-file)

Fit: Devin fits the file-swap model. One documented credentials file is the whole login, the vendor says copying it reuses the session, and logout is a separate delete; no local transcript path was found, so usage would stay empty unless a later doc names one.

#### Cline

- Official config layout: `~/.cline/data/settings/providers.json` is “API keys and provider configuration.” Sessions are `~/.cline/data/sessions/`. `CLINE_DATA_DIR` replaces `~/.cline/data/`. — [Config](https://docs.cline.bot/getting-started/config)
- A 24 March 2026 commit treats `providers.json` as the current file and `secrets.json` as legacy. A 28 April 2026 commit says `providers.json` holds API keys and OAuth tokens. — [commit 9b29903](https://github.com/cline/cline/commit/9b299038e4911148239edcef228eb85349f6a997), [commit 89e5cb7](https://github.com/cline/cline/commit/89e5cb7f63d0981e887e429bbf243cf37e7588aa)

Fit: Cline fits the OpenCode pattern, not the Windsurf one-key swap. One `providers.json` can hold several providers, so Keyhop would save and restore the whole file, and `~/.cline/data/sessions/` is the place to look for a transcript if those files record usage.

#### Google Antigravity CLI

- On a local machine, `agy` reads a token profile from the OS keyring (Apple Keychain, Linux Secret Service, Windows Credential Manager). `/logout` purges those profiles from the keyring. — [Install and auth](https://www.antigravity.google/docs/cli/install)
- Account login is not a documented file. The Gemini API-key mode is `modelProvider: gemini` in `~/.gemini/antigravity-cli/settings.json` plus `GEMINI_API_KEY`. That mode “never establishes an account session,” and `/logout` does nothing for it. — [Install and auth](https://www.antigravity.google/docs/cli/install)
- Headless mode uses “cached credentials” from an earlier interactive `agy` session and does not name the cache file. — [Headless](https://antigravity.google/docs/cli/headless/)
- A third-party note, not Google’s docs, claims SSH sessions write `~/.gemini/antigravity-cli/antigravity-oauth-token` and conversations under `~/.gemini/antigravity-cli/conversations/`. — [auth-internals.md](https://github.com/oaustegard/claude-skills/blob/main/plugins/ai-and-reasoning/skills/invoking-antigravity/references/auth-internals.md)

Fit: Antigravity does not fit the normal desktop model. The vendor’s desktop credential is the OS keyring, and the only documented non-keyring login is an API key in the environment, which Keyhop is set up to leave alone.

#### Factory (Droid)

- Official CLI auth instructions name `FACTORY_API_KEY` only. They do not name an OAuth file. — [Droid CLI reference](https://docs.factory.ai/droid-cli/cli-reference)
- Official settings path is `~/.factory/settings.json` (Windows `%USERPROFILE%\.factory\settings.json`). That page describes preferences, not the login token. — [Settings](https://docs.factory.ai/droid-cli/settings)
- Third-party usage docs, not Factory, name `~/.factory/auth.v2.file` plus `~/.factory/auth.v2.key`, legacy `~/.factory/auth.encrypted` and `~/.factory/auth.json`, and a macOS keychain entry. — [OpenTokenUsage factory.md](https://github.com/PowerUserZ/OpenTokenUsage/blob/main/docs/providers/factory.md)

Fit: Factory does not yet fit as a confirmed file switch. The vendor documents an environment API key, and the local OAuth path is undocumented in Factory’s own CLI reference, so a switcher would be guessing at an encrypted store.

#### Aider

- Aider takes provider keys from the command line, environment variables, a `.env` file, or `.aider.conf.yml` (`openai-api-key`, `anthropic-api-key`, or `api-key:` entries). No account-login file or account-switch command is documented. — [API keys](https://aider.chat/docs/config/api-keys.html)

Fit: Aider does not fit. It has no local account session to swap; keys are env or project config, and there is no documented switch that keeps another login alive.

#### Zed

- Keys saved in Zed are stored in the system keychain, not `settings.json`. Non-empty provider environment variables override the keychain. The AI settings page can also “sign in to supported subscription-backed providers,” and the docs do not name a credential file for that sign-in. — [API access](https://zed.dev/docs/ai/use-api-access.html), [Agent settings](https://zed.dev/docs/ai/agent-settings)

Fit: Zed does not fit a file switcher. The documented secret store is the OS keychain, so swapping a settings file would not change the account.

#### Continue

- The `cn` CLI reads `~/.continue/config.yaml` unless `--config` or a saved config is used. `/config` switches configuration files. Secrets are `${{ secrets.NAME }}` references, resolved from a project `.env` or `~/.continue/.env`. — [CLI configuration](https://docs.continue.dev/cli/configuration), [Models, rules, and tools](https://docs.continue.dev/guides/configuring-models-rules-tools)

Fit: Continue is a weak fit. It has a local config and a secrets env file, and `/config` switches configs rather than logged-in accounts, so there is no account session to restore without revoking.

#### Augment

- No official local credential path or account-switch command was found in this pass.

Fit: Augment is not a candidate until a vendor page names a login file or a switch command.

### Inferences

- The three tools worth a Keyhop design pass are Amp (file plus `amp account switch`), Devin CLI (single copyable `credentials.toml`), and Cline (whole `providers.json`, sessions beside it).
- Antigravity is the closest Google-family neighbor and the one most likely to be requested next. Building it as another `oauth_creds.json` swap would contradict the current install doc, which puts the desktop token in the keyring.
- Factory may already have a local OAuth store, but treating the OpenTokenUsage paths as stable would repeat the Windsurf problem: a third-party path with no vendor page.

### Gaps

- Amp: the official docs name `secrets.json` and `amp account switch`, but they do not show whether several accounts live in that one file or how usage transcripts are stored.
- Devin CLI: no usage or transcript path in the auth and config pages fetched.
- Cline: `sessions/` is documented as “Session data,” not as a token ledger. Whether those files contain usage totals was not checked in source.
- Antigravity: Google does not document the SSH token-file path. The third-party path should stay unused until an official page names it.
- Factory: no official OAuth filename.
- Augment: no credential file found.
- Not searched deeply enough to add or reject: Kiro, Amazon Q Developer CLI, Goose, and other CLIs outside the list in the assignment.
