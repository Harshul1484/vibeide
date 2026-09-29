# VibeIDE — Mockup Prompts

Prompts for regenerating or extending the presentation images in [`docs/mockups/`](mockups/) with an image-generation or compositing tool. Each one is written for VibeIDE's actual screens in [`docs/screenshots/`](screenshots/).

## Ground rules (apply to every prompt)

- **The supplied screenshot is the source of truth.** Place it pixel-accurately. Don't redraw, re-typeset, recolour, crop into, extend, or "clean up" any UI.
- Don't invent UI elements, text, icons, notifications, status-bar content, or data.
- Don't add logos, product names, taglines, or other typography to the image unless asked.
- Frames are **generic**: no manufacturer branding, logos, or recognisable flagship shapes.
- Palette comes from the app: background `#1E1E1E`, sidebar `#252526`, accent `#0078D4` (status bar `#007ACC`). Use the accent only as a faint ambient glow.
- Avoid: neon, cyberpunk, glassmorphism, lens flares, heavy 3D, floating decorative objects, stock illustrations, fake reflections across the UI, and heavy drop shadows.
- The output must read well on **both** GitHub light and dark themes. Give it its own dark, rounded-corner background (≈28 px radius at 1600 px wide) rather than a transparent cut-out.

**Screen sources**

| File | Size | What it is |
|---|---|---|
| `tablet-workspace.png` | 1920×1200 | Explorer + 3 editor tabs + terminal running `git log --graph` |
| `tablet-ai-agent.png` | 1920×1200 | AI Assistant in Agent mode with "Proposed changes (1 file)" |
| `tablet-source-control.png` | 1920×1200 | SCM with AI commit message, file groups, commit graph |
| `tablet-pull-request.png` | 1920×1200 | Compare changes: `main ← fix/audio-cue`, diff, AI PR title/body |
| `tablet-search.png`, `tablet-command-palette.png` | 1920×1200 | Search results; command palette |
| `phone-editor.png`, `phone-extensions.png`, `phone-source-control.png`, `phone-projects.png`, `phone-welcome.png`, `phone-settings.png` | 720×1555 | Real-device captures (status bar cropped) |
| `phone-onboarding.png` | 720×1554 | First onboarding slide |

---

## 01 — Hero product mockup → `mockups/hero.png`

Create a premium product hero image for **VibeIDE**, an Android IDE, using `tablet-workspace.png` and `phone-editor.png` as exact UI references.

- **Composition:** a large landscape tablet on the left two-thirds, slightly above centre, showing `tablet-workspace.png` edge to edge. A portrait phone on the right showing `phone-editor.png`, overlapping the tablet's right edge by about 5% and sitting slightly lower. Generous negative space on all sides; the tablet takes about 70% of the width.
- **Camera / view:** straight-on and orthographic. At most a 2–3° perspective, only if every line of code stays sharp and legible.
- **Device / frame:**
  - **Tablet:** a generic near-black bezel (`#0B0C0E`), 1 px `#2C2F36` edge, ~34 px corners.
  - **Phone:** a realistic modern Android phone, upright with no tilt. It has a graphite metal rim (a subtle diagonal gradient `#6B6F78 → #1A1B1F → #767A83`), a thin, even black glass bezel, and volume + power buttons on the right edge. Above each screenshot, add a **clean, generic Android status bar**: `12:00` on the left; Wi-Fi, signal and a full battery on the right; no notification icons. Its background matches the real colour from each capture (`#323233` on the Projects screen, `#1E1E1E` elsewhere). The front camera is a small punch-hole centred in that status bar. The screen runs edge to edge, with corners (~6% of phone width) small enough not to clip the app's `main · vibecli` bar.
  - No brand marks or recognisable flagship shapes on either device.
- **Background:** charcoal radial gradient (`#1A1D23` top → `#0C0D10` edges), a faint dot grid fading out toward the edges, and a soft `#0078D4` glow (≈20% opacity) behind the devices.
- **Lighting & shadows:** soft, diffuse, top-down light. One long, low-opacity contact shadow under each device. No specular glare over the screens.
- **Aspect ratio:** 16:9 (e.g. 2400×1350).
- **Don't include:** text, logos, hands, desks, plants, coffee cups, keyboards, extra app windows.

## 02 — Feature showcase → `mockups/feature-git.png`

A layered showcase of VibeIDE's git workflow using `tablet-source-control.png` (primary), `tablet-pull-request.png` (secondary) and `phone-source-control.png` (accent).

- **Hierarchy:** the primary tablet sits lower-left at ~55% width, fully visible and on top. The secondary tablet sits upper-right at ~49% width, partly behind the primary. Its "Compare changes" header, branch pickers and green "Ready to compare" bar must stay visible. The phone sits lower-right at ~12% width, on top.
- **Perspective:** identical for all three devices (flat or the same slight tilt).
- **Message:** these are parts of one product: stage & commit → compare branches → open a PR.
- Same frame, background, lighting and exclusions as Prompt 01. **Aspect ratio:** 16:9.

## 03 — Workflow mockup → `mockups/workflow.png`

Three tablet screens in chronological order, left to right: `tablet-workspace.png` → `tablet-ai-agent.png` → `tablet-pull-request.png` (edit → ask the agent and review → ship a PR).

- Equal size (~29.5% of the width each), vertically centred, evenly spaced.
- Between screens, a thin horizontal connector: a 2 px line fading in from transparent to `#0078D4`, ending in a small arrowhead. No numbers or labels.
- Flat view, minimal shadows, same background as Prompt 01.
- **Aspect ratio:** ~3:1 (e.g. 2400×816), because a 16:9 canvas leaves the screens too small to read.

## 04 — Device mockup (mobile lineup) → `mockups/mobile.png`

VibeIDE is phone-first and has a separate wide layout at ≥720 dp. Show four portrait phones in a row: `phone-onboarding.png`, `phone-projects.png`, `phone-editor.png`, `phone-extensions.png`.

- Equal widths (~17.5% of the canvas). The outer two sit ~2% lower than the inner two for a gentle arc.
- Screens are real device captures. Use only the generic status bar described in Prompt 01, and don't add notifications or a navigation bar.
- Don't imply layouts the app doesn't have (for example, don't put the phone UI on a tablet frame, or the reverse).
- Same frame, background and exclusions as Prompt 01. **Aspect ratio:** 16:9.

## 05 — Dark / cinematic mockup → `mockups/feature-ai-agent.png`

A calm, technical presentation of the **AI Agent review** screen, `tablet-ai-agent.png`.

- One tablet, centred, ~79% of the width. A straight-on view keeps the chat text and the "Approve all / Reject all" controls legible.
- Background: very dark neutral (`#0C0D10` → `#121418`) with a single soft `#0078D4` ambient glow behind the device (≤20% opacity, wide falloff).
- Soft shadow and slight depth. No rim lights, bloom, scan lines, particles, or glowing outlines on the UI.
- **Aspect ratio:** 16:9.

## 06 — GitHub README wide banner → `mockups/github-banner.png`

A wide banner that reads well at GitHub's README width (~880 px rendered).

- `tablet-workspace.png` centred at ~56% width and slightly above centre, on top.
- Two upright phones (no rotation) flank it: `phone-source-control.png` on the left and `phone-extensions.png` on the right. Each is ~14.5% of the width, vertically centred on the tablet.
- Generous margins; nothing within ~5% of the edges.
- Minimal decoration: background, glow, and shadows as in Prompt 01. No typography.
- **Aspect ratio:** 2:1 (e.g. 1920×960).

---

### Reproducing the current mockups exactly

The committed images were made by placing the screenshots in HTML/CSS frames (the values above) and rendering with headless Chrome at 1.2–1.5× device scale. Any compositor that keeps the screenshots unscaled-then-downsampled (no generative fill over the UI) gives the same result.
