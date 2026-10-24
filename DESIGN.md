---
name: Keyhop 2.0
description: A warm-charcoal status board for the Mac window and notch; one stepped neutral ramp, color is state only, one hop.
colors:
  ground: "#0c0b0a"
  chrome: "#090807"
  surface: "#121110"
  surface-hover: "#181613"
  track: "#201d19"
  bezel: "#000000"
  line: "rgba(255,250,240,.06)"
  line-strong: "rgba(255,250,240,.11)"
  ink: "#eceae5"
  ink-2: "#a8a49b"
  ink-3: "#8b8780"
  ok: "#4fae72"
  low: "#d9a03a"
  out: "#e05746"
  out-wash: "rgba(224,87,70,.06)"
  ok-wash: "rgba(79,174,114,.08)"
  brand: "#2f5fd9"
typography:
  body:
    fontFamily: "-apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui, sans-serif"
    fontSize: "13px"
    fontWeight: 400
    lineHeight: 1.45
  verdict:
    fontFamily: "-apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui, sans-serif"
    fontSize: "15px"
    fontWeight: 500
    lineHeight: 1.45
    letterSpacing: "-0.01em"
  figure:
    fontFamily: "ui-monospace, 'SF Mono', SFMono-Regular, Menlo, monospace"
    fontSize: "20px"
    fontWeight: 600
    lineHeight: 1.2
    letterSpacing: "-0.02em"
    fontFeature: "'tnum'"
  value:
    fontFamily: "ui-monospace, 'SF Mono', SFMono-Regular, Menlo, monospace"
    fontSize: "12px"
    fontWeight: 500
    lineHeight: 1
    fontFeature: "'tnum'"
  meta:
    fontFamily: "-apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui, sans-serif"
    fontSize: "12px"
    fontWeight: 400
    lineHeight: 1.45
rounded:
  inner: "5px"
  outer: "8px"
  pill: "99px"
  notch-closed: "0 0 14px 14px"
  notch-open: "0 0 20px 20px"
spacing:
  xs: "6px"
  sm: "8px"
  md: "14px"
  lg: "16px"
  xl: "20px"
components:
  button-primary:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.surface}"
    rounded: "{rounded.inner}"
    height: "32px"
    padding: "0 14px"
  button-primary-hover:
    backgroundColor: "#fffdf8"
  button-ghost:
    backgroundColor: "transparent"
    textColor: "{colors.ink-2}"
    rounded: "{rounded.inner}"
    height: "32px"
  button-ghost-hover:
    backgroundColor: "{colors.surface-hover}"
    textColor: "{colors.ink}"
  login-row:
    backgroundColor: "{colors.surface}"
    height: "47px"
    padding: "0 20px"
  login-row-critical:
    backgroundColor: "{colors.out-wash}"
  runway:
    backgroundColor: "{colors.track}"
    rounded: "{rounded.pill}"
    height: "4px"
  tag-no-spare:
    textColor: "{colors.ink-3}"
    rounded: "{rounded.inner}"
    padding: "1.5px 6px"
---

# Design System: Keyhop 2.0

Scope note: recorded from two throwaway HTML comps, `design/keyhop-2.0/window.html` and `design/keyhop-2.0/notch.html`, both finish-reviewed and shipped as comps. They are pending the owner's approval for the Swift rebuild of `Sources/Keyhop/Dashboard`. This file describes the comps, not the current Swift/HTML dashboard under `Sources/Keyhop/Dashboard/Page/`, which still carries the incumbent world until the rebuild lands. Vocabulary follows `CONTEXT.md`: login, hop, runway, window (never "account").

## Overview

**Creative North Star: "The Instrument Panel"**

Keyhop 2.0 answers one question, "can I keep working?", and everything else yields. The world is a warm charcoal status board at Linear/Raycast craft with opencode.ai restraint: a single stepped neutral ramp, hairline dividers, one system face, and a state triad. A page is recognizable with its content removed by its ramp, hairlines, and green/amber/red.

The window is one verdict sentence with one button, a ranked list of logins, and one figure for today. The notch is the same world folded into the device silhouette: it is the notch, widened and dropped, in true black because it extends the bezel.

The Coss Blue incumbent world and stock blue-charcoal dark palettes are rejected. Never reintroduce them.

**Key Characteristics:**
- One warm neutral ramp (ground, chrome, surface, hover, track); depth is tonal, never shadowed.
- Color is state only: ok, low, out. Brand blue appears in exactly three places.
- Actions are paper-on-ink; rows carry no controls.
- Mono is for figures only; everything else is system sans with tabular numerals.
- Motion is short opacity and transform moves, one property each, all collapsing under reduced motion.

## Colors

A warm charcoal ramp with paper-warm ink, and a green/amber/red state triad as the only chroma.

### Primary
- **Brand Blue** (#2f5fd9): lives only in the K mark, `::selection` (35% alpha), and the 2px focus ring. Nothing else is blue: no links, buttons, or chart series.

### Neutral
- **Ground** (#0c0b0a): page behind the window.
- **Chrome** (#090807): the visible step below the work surface; title bar and Today strip.
- **Work Surface** (#121110): window body, rows, verdict strip. Also the text color on paper buttons.
- **Hover** (#181613): row, icon button, and ghost-button hover wash.
- **Track** (#201d19): runway track, idle dots.
- **Bezel** (#000000): the notch only. The one extra ground, physically justified because the surface extends the device bezel. It never appears in the window.
- **Hairline** (rgba(255,250,240,.06)) and **Hairline Strong** (rgba(255,250,240,.11)): row and section dividers; window border, ghost-button border, and the "no spare" tag border.
- **Ink** (#eceae5), **Ink 2** (#a8a49b), **Ink 3** (#8b8780): primary text and fills, secondary text, tertiary meta.

### State
- **OK Green** (#4fae72), **Low Amber** (#d9a03a), **Out Red** (#e05746): dot, runway fill, and (for out) the percent value. Washes: out at 6% tints the critical row; ok at 8% holds the just-hopped row for about 2.2 s.
- Stale read-time turns Low Amber.

### Named Rules
**The State Only Rule.** Chroma means a state. If a color is not ok, low, or out, it is a neutral step or the brand blue in its three homes.

**The Paper-on-Ink Rule.** Primary actions are Ink fill with #121110 text. Ghost is bordered with Hairline Strong. No accent-filled buttons.

**The Bezel Rule.** True black exists only where a surface is the device bezel. Inside it, the ramp is unchanged.

## Typography

**Body Font:** system sans (-apple-system, BlinkMacSystemFont, Segoe UI, system-ui)
**Figure Font:** ui-monospace, SF Mono, SFMono-Regular, Menlo

**Character:** native and quiet; the mono face signals "this is a measured number".

### Hierarchy
- **Verdict** (500, 15px, -0.01em): the one sentence; its `.detail` clause is Ink 2 at 400.
- **Figure** (mono 600, 20px, -0.02em, tabular): today's tokens; the API value follows in Ink 2 at 500. Notch foot figure is 13px.
- **Value** (mono 500, 12px, tabular): the right-hand column in rows and the notch flanks; the critical row is 600 in Out Red.
- **Body** (400/600, 13px, 1.45): tool names at 600, logins in Ink 2.
- **Meta** (12px, Ink 3): read-time, subtitle, links. Small labels run 11 to 11.5px (tag, share key).

### Named Rules
**The Figures Only Rule.** Mono is for numbers and times, never labels or prose. All numerals are tabular.

## Layout

A single centered window, `min(860px, 100%)`, with 16px minimum side padding. Everything shares one five-column grid: `8px dot | 112px tool | 220px login | 1fr runway | 190px value`, 14px column gap, 20px edge padding, rows 47px tall. The Today strip reuses the same columns so figure, share bar, and links align with the list. Spacing in use: 6, 8, 14, 16, 20.

Order: title bar (44px), verdict strip, logins ranked by minutes to stop (critical first), Today strip. History and Teams are quiet links; Settings is the title bar gear.

At 640px and below, rows reflow to two lines (tool and value over login and runway), the "resets in " prefix is hidden, and Today stacks to one column. The notch stage drops to 380px and the open panel hides its share hairline (the "today" caption stays with the figure), tightens its padding to 16px and its row gap to 6px, and narrows the tool and window-label columns; the panel height stays 286px and the runway keeps at least 40px.

**Value column grammar.** "N% · resets in T". One meaning per column: the dot is state, the runway is quantity, the value is percent and time. A bordered "no spare" tag next to the login marks a login with no alternate to hop to. Idle (measured-only) rows show a Track dot, no runway, no value. The notch line drops "resets in " to "N% · T".

## Elevation & Depth

Flat, tonal. There are no shadows anywhere; depth is the ramp (chrome below surface below hover) plus 1px hairlines. The only outline-style emphasis is the focus ring (2px Brand Blue, 2px offset, 5px radius).

### Named Rules
**The No Shadow Rule.** Separation is a ramp step or a hairline, not a shadow, glow, or blur.

## Shapes

Radius 8px for the outer window, 5px for everything inside (buttons, tags, icon buttons, K mark, focus ring); runway and share bars are pills. The notch uses device geometry: bottom radii 14px closed and 20px open, outward top fillets (10px radial) where black meets the menu bar. The focus ring on the notch is drawn on the surface silhouette via `:has(.togglebtn:focus-visible)`, inset, not on the button box.

## Components

### Buttons
- **Shape:** 5px radius, 32px high, 600 weight, 13px, 14px side padding.
- **Primary:** Ink fill, #121110 text, optional 15px stroke arrow icon. Hover #fffdf8; active scale .98.
- **Ghost:** transparent, Ink 2 text, Hairline Strong border; hover lifts to Hover wash and Ink. Used for Undo.
- **Icon button:** 28px, 5px radius, Ink 2, hover wash.

### Login row
State dot (7px), tool name, login, 4px runway, value. Critical row is washed Out Red 6% (10% on hover). Rows carry no controls. Title attributes explain the pace in plain language.

### Runway
4px pill on Track; fill takes the state color and refills with a 200 ms width transition.

### Today strip
On Chrome. Mono figure, caption in Ink 3, a 2px six-step grey share bar (#cfcbc3 down to #3a3731; position encodes tool, not color) with an 8px square-keyed legend.

### Hop (signature interaction)
A single affordance: the verdict's button. One click swaps the critical row's login in place, refills the runway, rewrites the verdict, moves the button to Undo, and re-ranks. Each text swap is an opacity-only crossfade (90 ms out, 110 ms in). Re-rank is a 180 ms FLIP translateY after a 210 ms wait. The row holds the ok wash for ~2.2 s. After 7 s the verdict settles to a steady all-clear naming the next concern. Reduced motion makes every step instant.

### Notch
Collapsed: black, 348px by 37px, flanks with a 6px state dot plus the critical percent on the left and today's tokens on the right, mono 12px; the middle stays empty for the camera housing. Open: 420px by 286px, status only: one group per tool, ranked critical first, each group breaking the subscription into its limit windows (owner's revision, 2026-10-24 third pass: "aby to bylo jasný"). The tighter window leads at full weight (30px row); the others follow as quiet sub-rows (22px, 11px Ink 3 value, empty icon cell). Rows sit on a `16px icon | 80px tool | 38px window label | 1fr runway | 112px value` grid; window labels ("5 h", "week", "day", sans 11px Ink 3) right-align against the runway; every runway is 4px (one thickness everywhere, owner's call) and every track and value shares one right edge. The 112px value column fits the longest case, "100% · 4 h 59 m". Groups separate with a hairline (10px margin + hairline + 10px padding). The state dot on a main row is replaced by a 14px single-stroke tool glyph in the state color: ">_" for Codex, a three-line asterisk for Claude Code (an eight-dash burst reads as a spinner), a centered wave for Windsurf. Below, a hairline-topped foot: figure, "today" caption, the per-tool share hairline (2px, the window's grammar and greys, aria-label carries the real split), and a K-marked "Open Keyhop" link (8px vertical tap padding), the surface's one brand appearance. No verdict and no buttons here; the hop lives in the window (owner's revision, 2026-10-24 second pass). Expansion staggers width (.14s) then height (.16s) and the surface's corner radius transitions with it; closing reverses the order; flanks and panel crossfade, and the three groups cascade in one beat apart (.22/.27/.32s delays, opacity only). Rows take the Hover wash and carry title tooltips naming which window binds; tooltip times must be consistent with the staged clock. Each row is a `role="group"` with an aria-label reading "tool, window, N% left, resets in T" ("left", never the ambiguous "at N%"). A live mono read-time (11px, Ink 3, centered on the 37px bar axis, amber once stale past 2 min) sits at the panel's top right; no fleet-summary row (owner's call). A faint camera-lens disc sits in the housing as stage detail. The panel catches its own clicks: anywhere but the link closes it; Escape closes and refocuses the toggle; an outside click closes it. The panel is `inert` when closed.

## Do's and Don'ts

### Do:
- **Do** build every surface from the ramp: Chrome, Work Surface, Hover, Track, with Hairline dividers.
- **Do** keep one meaning per column and put the verdict's button as the only hop control.
- **Do** put numerals and times in tabular mono and hide the "resets in " prefix at 640px and below.
- **Do** crossfade text swaps with opacity alone, and collapse all motion under `prefers-reduced-motion`.
- **Do** use Bezel black only for surfaces that extend the device.

### Don't:
- **Don't** reintroduce Coss Blue or stock blue-charcoal dark palettes.
- **Don't** use Brand Blue outside the K mark, selection, and focus ring.
- **Don't** use color for anything but state, or fill buttons with an accent.
- **Don't** add row-level controls, shadows, or glows.
- **Don't** set mono labels or prose; mono is figures only.
- **Don't** call a login an "account" in UI copy.
