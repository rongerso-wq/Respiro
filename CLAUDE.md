# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**Respiro** — COPD daily-care companion app for elderly patients (target: 55–80+). Single-file prototype with a planned Supabase backend.

**Files:**
- `index.html` — the entire app (~1900 lines, React 18 UMD + Babel Standalone + Tailwind CDN, no build step)
- `respiro_schema.sql` — Supabase/Postgres DDL + RLS policies (not yet wired up; paste into the SQL editor once to initialise)

**Run:** Open `index.html` directly in Chrome (`file://` works). No server needed.

## Architecture

Everything lives inside a single `<script type="text/babel">` block compiled in-browser. No bundler, no imports.

### Screens & navigation

4-tab nav (`SCREEN_ORDER = { home, report, history, settings }`). Screen transitions use slide-direction classes (`.screen-right` / `.screen-left`) derived by comparing `SCREEN_ORDER` indexes. Three full-screen overlays rendered on top of the nav: `EmergencyModal`, `PacerOverlay`, `CATScoreModal`.

### Component map (top to bottom in the file)

| Component | Purpose |
|-----------|---------|
| `Header` | Branding, streak badge, stats strip, greeting |
| `CheckInCard` | Traffic-light daily check-in (green/yellow/red). Red tap requires 2-tap confirmation guard. |
| `ResponsePanel` | Action steps shown after a check-in; yellow zone shows "Call My Doctor" (`tel:doctorPhone`); includes SpO₂ disclaimer |
| `EmergencyModal` | Red-zone overlay — 911 call + emergency contact quick-dial; `role="alertdialog"`, focus trap, Escape key |
| `RescueCounter` | Rescue-inhaler puff counter (persisted per-day); warns at ≥2 puffs |
| `MedSection` | Medication list with Tip/Done buttons; adherence ring |
| `PanicButton` | Opens `PacerOverlay` |
| `PacerOverlay` | Pursed-lip breathing pacer: 2s inhale / 4s exhale (PLB 2:4 ratio), caps at 5 cycles, Web Audio tones at transitions, `aria-live` announcement |
| `ReportScreen` | 30-day doctor report (demo data + real check-ins) |
| `HistoryScreen` | 30-day calendar (buttons, not divs) + weekly trend bars |
| `OnboardingScreen` | 5-step first-run wizard: name → doctor → doctor phone → inhaler → emergency contact |
| `SettingsScreen` | Edit all profile fields post-onboarding |
| `CATScoreModal` | COPD Assessment Test (8 questions, score 0–40), GOLD 2025 |
| `MMRCCard` | Single mMRC dyspnea question (0–4), shown on home screen |
| `NavBar` | Fixed bottom glassmorphism bar |
| `App` | Root — holds all global state, routes between screens |

### State & persistence

All global state lives in `App` as `useState`. Every mutation writes to `localStorage` immediately (no async, no context). Keys are all prefixed `resp_`:

| Key | Value |
|-----|-------|
| `resp_onboarded` | `'1'` once wizard is complete |
| `resp_name`, `resp_doctor`, `resp_doctor_phone`, `resp_inhaler` | Profile strings |
| `resp_ec_name`, `resp_ec_phone` | Emergency contact |
| `resp_checkins` | JSON array of `{ dateKey, status, ts }` |
| `resp_rescue_<YYYY-MM-DD>` | Puff count for that day |
| `resp_cat` | `{ score, ts }` from last CAT session |
| `resp_mmrc_today` | `{ score, dateKey }` |

### Demo data

`DEMO_STATUSES` (30-element array) and `DEMO_NOTES` fill in gaps in the calendar where no real check-in exists. `buildHistoryData()` merges real localStorage data on top. The demo is always visible for days the user hasn't logged yet — this is intentional for prototype demos.

### Design tokens

CSS custom properties in `:root` — edit these to re-skin:
- `--hero-1/2/3` — blue gradient palette
- `--calm / --calm-bg` — green (good zone)
- `--caution / --caution-bg` — amber (yellow zone)
- `--alarm / --alarm-bg` — red (emergency zone)
- `--bg`, `--surface`, `--ink`, `--ink-soft`, `--line` — neutrals

Colorblind-safe calendar dots: circle = green, rotated square (diamond) = yellow, square = red.

## Clinical constraints — DO NOT change without medical review

- **SpO₂ for COPD = 88–92%**, not 95%+. Targeting higher causes CO₂ retention. Any SpO₂ display must include the disclaimer already in `ResponsePanel`.
- **PLB ratio: 2s inhale / 4s exhale** is clinically correct. Do not change the pacer timings.
- **Yellow zone → call doctor. Red zone → call 911.** The call routing is intentionally separated.
- **Rescue inhaler >2 puffs/day** is a warning threshold (GOLD guideline).

## Planned but not yet built (Phase D)

- Supabase auth + sync (schema ready in `respiro_schema.sql`)
- Pre-appointment PDF/print export from the Report screen
- The CAT and mMRC components are built but only partially wired into the home screen
