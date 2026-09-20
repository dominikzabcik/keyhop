# Checks: every screen, every run

This walks every page of the website and every section of Keyhop's window, presses what can be
pressed, and reports what is wrong. Then, if a key is configured, it asks Jev what it thinks of
what each screen says.

```
npm install && npx playwright install chromium

node run.mjs --site          # the website, from a local wrangler
node run.mjs --app           # Keyhop's window, from `keyhop dashboard --sample`
node run.mjs --cli           # the commands, including the tools `keyhop mcp` serves
node run.mjs                 # all three
node run.mjs --review        # all three, then ask Jev
```

`--app` needs the debug binary, so run `swift build` first. Pictures of every screen at every width
and a full `report.json` land in `checks/report/`.

## What fails a run

These are decidable, so they fail:

- A page answers the wrong status, or logs an error in the console.
- A screen doesn't say what it must say (`mustSay` in `screens.mjs`), or says something it must
  never say: `undefined`, `NaN`, `[object Object]`, an em dash.
- Anything sticks out sideways, so the page scrolls horizontally.
- Text is cut off by its own box.
- An image has no text alternative, or a button has no name.
- A page has no first-level heading, or more than one.
- A link on any screen leads to a 404.
- A control does nothing at all when pressed: the page doesn't change, the address doesn't change,
  and no message appears.
- A command exits non-zero, prints something `--json` can't parse, leaves a key out of its JSON, or
  prints a value that never resolved. `keyhop mcp` is asked for its tools the way an agent asks,
  and has to offer `keyhop_status`, `keyhop_usage` and `keyhop_recommendation`.

Only commands that read are run, each with its own empty data folder, so a check can never reach a
real login, a real database or the real keyhop.app.

Destructive controls are left alone. `LEAVE_ALONE` in `checks.mjs` lists what is never pressed.

## What Jev is asked

Jev is TypeSafe's System One model: it answers typed questions about text or structured data and
returns numbers, not prose. It takes no images, so it is never asked how a screen looks. It is
asked what a picture wouldn't settle anyway:

- `own_voice` — is every sentence written in the house voice?
- `says_its_purpose` — from this screen alone, is it clear what the screen is for?
- `agrees_with_itself` — do the words on it agree with each other?
- `next_step_is_clear` — is the one thing to do next obvious?
- `empty_or_waiting_explains` — does an empty, loading or failing part say what to do?
- `clarity` — a 0 to 3 score against a rubric.
- `weakest_part` — which of headings, body, controls or nothing would confuse a first-time reader.

Every answer goes in the report. **None of them fail the run.** A judgement is a second opinion, and
a build that fails on one teaches everybody to ignore it. An answer Jev isn't sure about (confidence
below 0.75) is reported as unsure rather than as a fault.

To run the review, set a key from https://console.typesafe.ai/settings/keys:

```
export TYPESAFE_API_KEY="…"
```

In CI it runs only when the repository has a `TYPESAFE_API_KEY` secret, and it cannot fail the
build.

## Adding a screen

Put it in `screens.mjs`. A screen needs a name and a path (website) or section (window); `mustSay`
lists text that has to be there, and `expect.status` covers pages that aren't meant to answer 200.
Everything in "What fails a run" then applies to it without another line of code.

## What this does not cover

The menu bar panel and the iOS app are native, not web, so this harness cannot drive them. They are
covered by `swift test`, `xcodebuild test`, and the snapshot images from
`Keyhop --snapshot` and `scripts/ios-screenshots.sh`.
