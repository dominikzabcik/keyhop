# Keyhop for iPhone: App Store listing

Everything App Store Connect asks for, ready to paste. Signing, the App Store Connect record and
the submission itself need the Apple Developer account, so they are not scripted here.

## App information

| Field | Value |
| --- | --- |
| Name | Keyhop |
| Subtitle (30) | AI coding limits and seasons |
| Bundle ID | app.keyhop.ios |
| SKU | keyhop-ios |
| Primary category | Developer Tools |
| Secondary category | Productivity |
| Age rating | 4+ (no questionnaire items apply) |
| Price | Free |
| Encryption | Uses only exempt encryption (HTTPS). `ITSAppUsesNonExemptEncryption` is already `false`. |
| Support URL | https://github.com/dominikzabcik/keyhop/issues |
| Marketing URL | https://keyhop.app |
| Privacy Policy URL | https://keyhop.app/privacy |
| Copyright | 2026 dominikzabcik (as in LICENSE) |

## Version text

**Promotional text (170)**

> See how much room each AI coding account has left, and get told the moment a limit comes back.

**Description (4000)**

> Keyhop keeps your AI coding tools moving between the accounts you own. This app is its
> companion: it reads what Keyhop on your computer already knows and puts it on your phone.
>
> Limits
> See where every account stands against its five-hour and weekly limits, with a countdown to
> each reset. Turn on alerts and your phone tells you when a nearly spent account is ready again.
>
> Seasons
> Follow your monthly season, your tier and the gap to the next one, today's quests and the badges
> you have earned.
>
> Leaderboard
> See this week's standings next to the people you code with.
>
> Private by design
> This phone only reads. Your computer sends daily totals per tool, and current limits if you
> turn that on. Prompts, code, provider tokens and email addresses never leave your computer.
> Alerts are scheduled on the phone itself; nothing is pushed to you.
>
> Keyhop for macOS, Linux and Windows is free and open source at keyhop.app. Link this phone
> with the same GitHub account you use there.

**Keywords (100)**

> claude,codex,cursor,gemini,copilot,ai coding,usage limits,tokens,leaderboard,developer

**What's New**

> The first release on the App Store.

## Screenshots

`bash scripts/ios-screenshots.sh` writes three 1320 x 2868 images (6.9-inch display) to
`ios/build/screenshots/`. App Store Connect scales them down for the smaller iPhone sizes.

1. `1-season.png`: limits, season and quests
2. `2-leaderboard.png`: badges and this week's standings
3. `3-link.png`: linking with a code

## App privacy (the questionnaire)

- **Data collection:** Yes.
- **User ID:** collected, linked to the user, used for App Functionality, not used for tracking.
  The phone's session identifies its Keyhop account to keyhop.app.
- Nothing else is collected by the app. The daily totals and limits it shows are sent by the
  user's computer, not by the phone.
- **Tracking:** No.

`ios/Resources/PrivacyInfo.xcprivacy` declares the same thing, plus the one required-reason API
the app uses (UserDefaults, reason CA92.1).

## Review notes

App Review can't use the app without a linked Keyhop account, and linking needs a GitHub sign-in
in the browser. Before submitting:

1. Create a GitHub account for review and sign in to keyhop.app with it.
2. Give it data: link a computer running Keyhop, or leave it empty (the app still shows the
   season, quests and board).
3. Put the GitHub username and password in **Sign-in required** in App Review Information, with
   this note:

> Tap "Link with GitHub". Safari opens keyhop.app with a code; sign in with the GitHub account
> above and approve the code. The app moves on by itself. Keyhop reads usage from a companion
> app on the user's computer (keyhop.app/download); this phone only displays it.

## Before the first upload

- Set `DEVELOPMENT_TEAM` (and automatic signing) for the Keyhop target in `ios/project.yml`,
  then run `bash scripts/generate-ios-project.sh`.
- `CFBundleVersion` is `1` in `ios/project.yml`; raise it for every upload.
- Archive in Xcode (Product > Archive) and upload from the Organizer.
