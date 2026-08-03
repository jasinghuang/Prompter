---
name: 提词器 (Perhaps)
description: A mobile teleprompter PWA for short-video creators — dark, quiet, and purposeful. Evolved with spring-physics motion, calibrated amber accent, and premium anti-slop design.
colors:
  amber-lit: "#D4A432"
  darkroom-black: "#0A0A0B"
  elevated-surface: "#131316"
  raised-panel: "#1A1A1F"
  border-subtle: "#26262B"
  text-primary: "#F5F5F5"
  text-secondary: "#A1A1AA"
  text-muted: "#71717A"
  text-on-accent: "#0A0A0B"
  danger: "#DC2626"
typography:
  body:
    fontFamily: '"Noto Sans SC", -apple-system, "PingFang SC", sans-serif'
    fontWeight: 400
    fontSize: "0.875rem"
    lineHeight: 1.625
  heading:
    fontFamily: '"Noto Sans SC", -apple-system, "PingFang SC", sans-serif'
    fontWeight: 600
    fontSize: "1.125rem"
  display:
    fontFamily: '"Noto Sans SC", -apple-system, "PingFang SC", sans-serif'
    fontWeight: 700
    fontSize: "1.25rem"
  label:
    fontFamily: '"Noto Sans SC", -apple-system, "PingFang SC", sans-serif'
    fontWeight: 400
    fontSize: "0.75rem"
    letterSpacing: "0.05em"
  caption:
    fontFamily: '"Noto Sans SC", -apple-system, "PingFang SC", sans-serif'
    fontWeight: 400
    fontSize: "0.625rem"
  mono:
    fontFamily: '"SF Mono", "JetBrains Mono", "Cascadia Code", "Consolas", monospace'
    fontWeight: 400
    fontSize: "0.6875rem"
rounded:
  pill: "9999px"
  card: "1rem"
  control: "0.5rem"
  modal: "1.5rem"
spacing:
  "2xs": "4px"
  xs: "8px"
  sm: "12px"
  md: "16px"
  lg: "24px"
  xl: "32px"
  "2xl": "48px"
motion:
  spring-default: "spring(stiffness: 100, damping: 20, mass: 1)"
  spring-soft: "spring(stiffness: 80, damping: 22, mass: 1)"
  spring-snappy: "spring(stiffness: 150, damping: 18, mass: 0.8)"
components:
  button-primary:
    backgroundColor: "{colors.amber-lit}"
    textColor: "{colors.text-on-accent}"
    rounded: "{rounded.pill}"
    padding: "10px 18px"
    minHeight: "44px"
  button-ghost:
    backgroundColor: "transparent"
    textColor: "{colors.text-muted}"
    rounded: "{rounded.pill}"
    padding: "8px"
    minHeight: "44px"
  card-interactive:
    backgroundColor: "{colors.elevated-surface}"
    rounded: "{rounded.card}"
    padding: "16px"
    border: "1px solid {colors.border-subtle}"
  slider:
    trackHeight: "3px"
    thumbSize: "16px"
    filledColor: "{colors.amber-lit}"
    unfilledColor: "{colors.border-subtle}"
---
# Design System: 提词器 — The Darkroom 2.0

## 1. Visual Theme & Atmosphere

**North Star:** The Darkroom — a precision tool for creators. Like a photographer's darkroom, every surface is black because the work demands it. Color is not decoration — it is functional light. A single amber accent appears only where guidance is needed: the reading line, the active control, the one button you should press. Everything else stays in shadow.

The interface exists in peripheral vision — present when needed, invisible when not. The text is the only thing that matters.

- **Density:** 5/10 — Daily App Balanced. Information-rich but never cluttered. Generous whitespace around the reading area; denser information zones in list and settings views.
- **Variance:** 3/10 — Predictable Symmetric. This is a tool, not a portfolio. Consistency builds muscle memory. The same button always looks and behaves the same way.
- **Motion:** 5/10 — Fluid Spring. All interactive elements use spring physics (`stiffness: 100, damping: 20`) for a premium, weighty feel. Staggered cascade reveals on list mounts. Perpetual micro-pulses on active indicators. No linear easing — ever.

## 2. Color Palette & Roles

### Neutral Foundation
- **Darkroom Black** (#0A0A0B) — Primary background canvas. Never pure `#000000`. The deepest surface in the app.
- **Elevated Surface** (#131316) — Card background, modal panel background. Slightly lifted from the canvas.
- **Raised Panel** (#1A1A1F) — Settings drawer, search input, chip backgrounds. The lightest dark surface.
- **Border Subtle** (#26262B) — Structural 1px borders, input borders, dividers. Tonal, not decorative.
- **Text Primary** (#F5F5F5) — All primary content text, headings. Near-white for maximum readability.
- **Text Secondary** (#A1A1AA) — Descriptions, metadata, placeholder text, body content.
- **Text Muted** (#71717A) — Micro-text, timestamps, disabled labels, icon defaults.

### Accent — The Single Light
- **Amber Lit** (#D4A432) — The one accent. Used for: primary CTA buttons, active state indicators, focus rings, the reading guide line. Saturation below 80%. No neon glow.
- **Amber Muted** (rgba(212, 164, 50, 0.15)) — Subtle accent for: selected chip backgrounds, card hover borders, slider filled track portion.
- **Amber Dim** (rgba(212, 164, 50, 0.08)) — Ghost accent for: subtle active state backgrounds, hover tint on ghost buttons.

### Semantic States
- **Danger** (#DC2626) — Deletion confirmations, destructive action text. Used sparingly.
- **Danger Muted** (rgba(220, 38, 38, 0.15)) — Destructive hover backgrounds.
- **Success** (#22C55E) — Positive feedback indicators (reserved, rarely used).

### Named Rules
**The One Light Rule.** Amber Lit (#D4A432) appears on at most one interactive element per surface. When two buttons need it, only the primary action gets it; the other defaults to ghost.

**The No-Line Rule.** On dark surfaces, depth comes from tonal contrast (Elevated Surface over Darkroom Black), not from borders. A border appears only when necessary: inputs, dividers, and the one-pixel frame around interactive cards.

**The Flat-At-Rest Rule.** Surfaces are flat in their default state. The one exception is the teleprompter's reading guide line, which carries a subtle amber tint. No drop shadows, no outer glows on interactive elements.

## 3. Typography Rules

### Typeface Selection
- **Display & Body:** `Noto Sans SC` — Best freely available Chinese sans-serif. Optimized for screen reading. Loaded from Google Fonts with `font-display: swap`.
- **Mono Data:** `"SF Mono", "JetBrains Mono", "Cascadia Code", "Consolas", monospace` — For timer display, speed values, character counts. All numeric data uses `font-variant-numeric: tabular-nums`.
- **Banned:** Inter, generic system serif fonts (`Times New Roman`, `Georgia`, `Garamond`).

### Typographic Scale
| Role | Size | Weight | Use |
|------|------|--------|-----|
| Caption | 0.625rem (10px) | 400 | Micro-descriptions, hints |
| Mono Data | 0.6875rem (11px) | 400 | Timer, speed, metadata |
| Body Small | 0.75rem (12px) | 400 | Button labels, chip text |
| Body | 0.875rem (14px) | 400 | Card previews, setting labels |
| Body Large | 1rem (16px) | 400/500 | Card titles, navigation |
| Subtitle | 1.125rem (18px) | 600 | Section headers, editor text |
| Title | 1.25rem (20px) | 700 | Page titles, modal headers |

### Typography Rules
- Hierarchy through **weight** (400 → 500 → 600 → 700) and **color**, not just size
- Max line length: 65 characters for body text
- Line height: 1.5 for body, 1.375 for headings, 1.6 for reading area
- Letter spacing: -0.01em for headings (track-tight), normal for body
- No italic, underline (except input style), or all-caps for emphasis
- Numbers always monospace with tabular-nums

## 4. Component Stylings

### Primary Button
- **Shape:** Fully rounded pill (`border-radius: 9999px`), minimum 44px tap target height
- **Rest:** Amber Lit (#D4A432) fill, Darkroom Black (#0A0A0B) text, font-weight 700. No shadow, no glow.
- **Hover:** Scale 1.02 via spring physics.
- **Active/Press:** Scale 0.97, translateY(1px) — tactile push feedback. Spring animation.
- **Focus:** 2px amber ring with 2px offset.
- **Disabled:** Opacity 0.3, cursor not-allowed, no hover effects.

### Ghost Button (Toolbar Actions)
- **Shape:** Circular (`border-radius: 9999px`), minimum 44px tap target
- **Rest:** Text Muted (#71717A), transparent background, no border
- **Hover:** Text Primary (#F5F5F5), background Amber Dim (rgba(212, 164, 50, 0.08))
- **Active:** Scale 0.95, text shifts to Amber Lit
- **Focus:** 2px amber ring

### Interactive Card
- **Shape:** Rounded 1rem (16px), 1px Border Subtle border
- **Rest:** Elevated Surface (#131316), border Border Subtle (#26262B). No shadow.
- **Hover:** Border Amber Muted (rgba(212, 164, 50, 0.15)), background #1A1A1F
- **Active:** Scale 0.985
- **Content:** Title in Text Primary, preview clamped to 2 lines in Text Secondary
- **Footer:** Border-top divider, metadata in Text Muted, CTA in Amber Lit

### Search Input
- **Shape:** Rounded pill (`border-radius: 9999px`)
- **Rest:** Raised Panel (#1A1A1F) background, Border Subtle (#26262B) border
- **Focus:** Border Amber Lit, subtle ring of Amber Dim
- **Icon:** Search icon inside left, Text Muted color, non-interactive

### Underline Input (Title)
- **Shape:** Full width, transparent background, bottom border only
- **Rest:** Border Border Subtle, text Text Primary
- **Focus:** Border Amber Lit, no ring
- **Placeholder:** Text Muted

### Textarea (Content Editor)
- **Shape:** Full width, no border, no background
- **Rest:** Text Secondary (#A1A1AA), transparent
- **Focus:** No visual change — content-first editing
- **Placeholder:** Text Muted

### Slider (Range Input)
- **Track:** Height 3px, rounded full. Unfilled: Border Subtle. Filled: Amber Lit.
- **Thumb:** 16px circle, white fill, subtle shadow. No border.
- **Hover:** Thumb scales to 18px
- **Active:** Thumb scales to 14px (press-in feedback)
- **Focus:** 2px amber ring on thumb

### Toggle Switch
- **Off:** Border Subtle background, white thumb at left
- **On:** Amber Lit background, white thumb at right
- **Transition:** Spring physics, 300ms
- **Size:** 48px × 24px track, 20px thumb

### Active Indicator Dot
- **Idle:** 6px circle, Text Muted color. No glow.
- **Active:** Amber Lit color, subtle perpetual pulse (opacity 100% ↔ 70%, 2s cycle)
- **No box-shadow, no neon glow**

### Reading Guide Lines
- **Shape:** 2px wide, 112px tall, rounded full
- **Color:** Amber Dim (rgba(212, 164, 50, 0.25))
- **Position:** Left and right edges, vertically centered on reading line
- **No glow shadow** — subtle guidance without distraction

### Modal / Confirmation Dialog
- **Overlay:** Darkroom Black at 80% opacity, backdrop-blur 8px
- **Panel:** Elevated Surface (#131316), rounded 1.5rem (24px), 1px Border Subtle border
- **Animation:** Spring scale entrance (0.95 → 1.0), fade overlay
- **Actions:** Cancel = Ghost Button, Confirm = Primary Button (destructive variant for delete)

### Settings Panel (Slide-in Drawer)
- **Width:** 320px (20rem), max 85vw on mobile
- **Background:** Elevated Surface (#131316)
- **Border:** 1px left Border Subtle
- **Animation:** Slide from right with soft spring physics
- **Overlay:** Darkroom Black at 60% opacity

### Toast / Transient Notification
- **Shape:** Rounded full pill
- **Background:** Elevated Surface at 90% opacity, backdrop-blur
- **Border:** 1px Amber Muted
- **Text:** Amber Lit, 12px
- **Animation:** Spring slide-up entrance, fade exit after duration
- **Position:** Top center, below safe area

### Empty State
- Icon in a 64px rounded-3xl Raised Panel container, Text Muted color
- Descriptive Text Secondary text, centered
- Not just "No data" — explains what to do

## 5. Layout Principles

### Grid System
- **Max-width containment:** 1120px (70rem) for list, 720px (45rem) for editor, 896px (56rem) for teleprompter
- **Gutters:** 16px mobile, 24px desktop
- **Script list grid:** 1 column mobile, 2 columns from 640px (never 3)
- **CSS Grid over Flexbox** for layout math — no calc() percentage hacks
- **No absolute-positioned overlapping** — each element occupies its own clean spatial zone

### Spacing Scale (4px base)
| Token | Size | Use |
|-------|------|-----|
| 2xs | 4px | Icon gaps, tight clusters |
| xs | 8px | Related elements |
| sm | 12px | Card padding, group spacing |
| md | 16px | Section internal padding |
| lg | 24px | Section gaps |
| xl | 32px | Major section separation |
| 2xl | 48px | Page-level spacing |

### Safe Area Protocol
- Every screen: `env(safe-area-inset-*)` for padding
- Full-height viewports: `min-h-[100dvh]` (never `h-screen`)
- Bottom controls respect `safe-area-inset-bottom`
- Top headers respect `safe-area-inset-top`

### Responsive Collapse
- **< 640px:** All multi-column grids → single column. Search narrows. Settings drawer full-width.
- **640px+:** 2-column card grid. Full controls visible.
- **1024px+:** Max-width containment with generous side margins.

## 6. Motion & Interaction

### Spring Physics Engine
All interactive elements use CSS spring() easing:
- **Default:** `spring(stiffness: 100, damping: 20, mass: 1)` — buttons, toggles, chips
- **Soft:** `spring(stiffness: 80, damping: 22, mass: 1)` — drawers, modals, panels
- **Snappy:** `spring(stiffness: 150, damping: 18, mass: 0.8)` — micro-interactions, dots

### Perpetual Micro-Interactions
- **Active Recording Dot:** Gentle pulse (opacity 100% ↔ 70%, 2s cycle, ease-in-out)
- **Reading Guide Lines:** Subtle breathing opacity wave (4s cycle)
- **Loading skeleton:** Shimmer sweep across surface (2s cycle)

### Staggered Cascade Reveals
- Script list items: 50ms stagger per item, spring slide-up from 16px below
- Settings panel rows: 30ms stagger per row
- Primary CTA: appears last at 200ms delay

### Performance Mandates
- Animate exclusively via `transform` and `opacity` (GPU-composited)
- Never animate `top`, `left`, `width`, `height`, `margin`, `padding` (triggers layout)
- `prefers-reduced-motion`: disable all animations, instant transitions
- Use `will-change` only on actively animating elements

### Keyboard Interaction
- **Space:** Play/pause toggle (preventDefault on repeat)
- **↑ ↓:** Speed adjustment (±20 normally, ±5 with Shift held)
- **Escape:** Close settings panel, dismiss modals
- All interactive elements must have visible 2px amber focus rings

## 7. Anti-Patterns (Banned)

### Color
- ❌ Pure black `#000000` — always use #0A0A0B
- ❌ Neon/outer glow shadows on any element  
- ❌ Oversaturated accents (saturation > 80%)
- ❌ Purple or blue neon aesthetics
- ❌ Gradient text on headers
- ❌ More than one accent color per surface

### Typography
- ❌ Inter font in any context
- ❌ Generic serif fonts (Times New Roman, Georgia, Garamond)
- ❌ Italic, underline, or all-caps for emphasis
- ❌ Emojis anywhere in UI text

### Layout
- ❌ 3-column equal card grids (use 2-column asymmetric or single column)
- ❌ Centered hero sections or content blocks
- ❌ Overlapping elements via absolute positioning
- ❌ Horizontal scroll on any viewport
- ❌ `h-screen` (use `min-h-[100dvh]` to prevent iOS Safari jumps)

### Motion
- ❌ Linear easing on any transition — always spring or ease-in-out
- ❌ Animating layout-inducing properties (width, height, top, left)
- ❌ Custom mouse cursors
- ❌ Auto-playing media

### Content
- ❌ Generic placeholder names ("John Doe", "Acme", "Nexus")
- ❌ Fake round numbers ("99.99%", "50%")
- ❌ AI copywriting clichés ("Elevate", "Seamless", "Unleash", "Next-Gen")
- ❌ Filler UI text: "Scroll to explore", "Swipe down", scroll arrow icons
- ❌ Broken image links

### Interaction
- ❌ Buttons without 44px minimum tap target
- ❌ Missing focus indicators on interactive elements
- ❌ Disabled buttons without clear visual distinction (at minimum 30% opacity)
- ❌ Floating labels on inputs
