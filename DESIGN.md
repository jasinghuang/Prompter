---
name: 提词器 (Perhaps)
description: A mobile teleprompter PWA for short-video creators — dark, quiet, and purposeful.
colors:
  amber-lit: "#eab308"
  amber-glow: "#eab308"
  darkroom-black: "#000000"
  surface-nearblack: "#050505"
  surface-card: "#1c1c1c"
  surface-hover: "#2a2a2a"
  border-default: "#3d3d3d"
  text-placeholder: "#6b6b6b"
  text-secondary: "#8e8e8e"
  text-body: "#b0b0b0"
  text-heading: "#cccccc"
  text-on-accent: "#000000"
  text-white: "#ffffff"
  danger: "#ef4444"
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
    fontFamily: 'ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace'
    fontWeight: 400
    fontSize: "0.6875rem"
rounded:
  pill: "9999px"
  card: "0.75rem"
  control: "0.5rem"
spacing:
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "24px"
components:
  button-primary:
    backgroundColor: "{colors.amber-lit}"
    textColor: "{colors.text-on-accent}"
    rounded: "{rounded.pill}"
    padding: "12px 16px"
  button-primary-hover:
    backgroundColor: "{colors.amber-lit}"
  card-interactive:
    backgroundColor: "{colors.surface-card}"
    rounded: "{rounded.card}"
    padding: "16px"
---

# Design System: 提词器 (Perhaps)

## Overview

**Creative North Star: "The Darkroom"**

Like a photographer's darkroom, every surface is black because the work demands it. Color is not decoration — it is functional light. Yellow appears only where guidance is needed: the reading line, the active control, the one button you should press. Everything else stays in shadow.

This is a teleprompter, not a portfolio piece. The design's single job is to disappear. The text is the only thing that matters; the interface exists in peripheral vision, present when needed, invisible when not. No gradients, no decorative borders, no ornament. Just black, yellow, and precision.

**Key Characteristics:**

- Palettes: single accent (yellow) on infinite black; neutral grays only for layered depth
- Typography: one Chinese-optimized sans-serif family, restrained scale, no italics
- Layout: single-column, full-height viewports, safe-area-aware on mobile
- Motion: a single well-placed transition — controls fade in when paused, buttons activate with scale

## Colors

A darkroom palette: black is the room, yellow is the safelight, grays are the developing trays.

### Primary
- **Amber Lit** (#eab308 / yellow-500): The reading guide line. The primary CTA. The active tab. Used in exactly one place per screen. Its rarity is the point.

### Neutral
- **Darkroom Black** (#000 / black): Page background. The void the text scrolls through.
- **Surface Near-Black** (#050505): Slightly lighter page bg, used when pure black needs a subtle lift.
- **Surface Card** (#1c1c1c / neutral-900): Card, input, and panel backgrounds. One step out of the void.
- **Surface Hover** (#2a2a2a / neutral-800): Hover state, secondary button, active chip.
- **Border Default** (#3d3d3d / neutral-700): Borders, dividers, the ghost line.
- **Text Placeholder** (#6b6b6b / neutral-600): Input placeholders. Faint, present, ignorable.
- **Text Secondary** (#8e8e8e / neutral-500): Descriptions, icons, disabled states.
- **Text Body** (#b0b0b0 / neutral-400): Body text, toolbar labels, reading text.
- **Text Heading** (#cccccc / neutral-300): Headings, prominent labels.
- **Text White** (#ffffff): Body text on black backgrounds, active button labels.

### Semantic
- **Danger** (#ef4444 / red-500): Deletion, destructive actions.
- **Danger Hover** (#f87171 / red-400): Danger hover state.

### Named Rules
**The One Light Rule.** Amber-lit (#eab308) appears on at most one interactive element per surface. When two buttons need it, only the primary action gets it; the other defaults to ghost.

**The No-Line Rule.** On dark surfaces, depth comes from tonal contrast (Surface Card over Near-Black), not from borders. A border appears only when necessary: inputs, dividers, and the one-pixel frame around interactive cards.

## Typography

**Display/Heading/Body Font:** Noto Sans SC (with PingFang SC and system sans-serif fallback)
**Mono Font:** System monospace stack (ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas)

**Character:** A single Chinese-optimized sans-serif carries the entire application. Weight — not size — is the primary differentiator. Bold for hierarchy, regular for reading, mono for data.

### Hierarchy
- **Display** (bold, 1.25rem, 1.75 line-height): Page titles and primary headings. Used once per screen.
- **Headline** (semibold, 1.125rem, 1.75 line-height): Card titles, section headers.
- **Title** (semibold, 1rem): Secondary headings, button labels.
- **Body** (regular, 0.875rem, 1.625 line-height): Content text, descriptions, teleprompter reading text.
- **Label** (regular, 0.75rem, 0.05em letter-spacing): Metadata, timestamps, secondary hints.
- **Caption** (regular, 0.625rem): Micro-descriptions, hints below section titles.
- **Mono Data** (regular, 0.6875rem, tabular-nums): Timer display, speed values, numeric readouts.

## Layout

**Grid model:** Single-column, centered, capped at 56rem (max-w-5xl) for lists, 48rem (max-w-3xl) for the editor. No sidebar, no multi-column. The teleprompter viewport is full-bleed.

**Spacing rhythm:** Built on a 4px base unit (xs=4, sm=8, md=12, lg=16, xl=24). Cards use lg (16px) internal padding. Gaps between sections use lg or xl. Controls use sm (8px) and md (12px) for tight adjacency.

**Safe areas:** All screens respect `env(safe-area-inset-*)` on notched devices. Headers pad-top, footers pad-bottom, side content pads left/right.

**Responsive behavior:** Mobile-first. The only breakpoint change is collapsing the script grid from 2 columns to 1 below 640px (sm).

## Elevation & Depth

This system is **flat by default**. No drop shadows on cards or surfaces. Depth comes from tonal contrast: darker surfaces recede, lighter surfaces advance.

The only transparent overlays use `backdrop-blur-xl` on headers. Backdrops (modals, confirmations) use black at 80% opacity with no blur.

**The Flat-At-Rest Rule.** Surfaces are flat in their default state. The single exception is the teleprompter's reading guide line, which carries a subtle yellow glow (0 0 12px rgba(234,179,8,0.4)) — the one place where atmospheric light is permitted.

## Shapes

**Corner strategy:** Pills (rounded-full, 9999px) for action buttons and switches. Cards (rounded-xl, 12px) for containers. Controls (rounded-lg, 8px) for inner buttons, inputs, and chips. No sharp corners anywhere — the darkroom is gentle at every edge.

**Border language:** One-pixel borders only. Color: Border Default (#3d3d3d) for structural borders, amber-lit at 50% opacity for focus rings.

**Form silhouette:** All containers are rounded rectangles. Buttons are rounded pills. Inputs follow the same rounding as their containing surface. No circles, no diamonds, no angled edges.

## Components

### Buttons
- **Shape:** Rounded pill (9999px radius)
- **Primary:** Solid Amber Lit fill, black text, bold weight. Used for high-priority actions ("New Script", "Smart Split").
- **Primary Hover:** Same fill, subtle scale-down on press (active:scale-95).
- **Ghost:** No fill, no border. Neutral-400 text, darkens to white on hover. Used for toolbar actions and secondary navigation.
- **Danger:** Red-500 fill, white text. Used only in confirmation dialogs.
- **Disabled:** 30% opacity, cursor-not-allowed. No hover effects.

### Cards / Containers
- **Interactive Card (Script List):** Surface Card bg at 40% opacity, 16px padding, 12px corners. Border: Border Default at 60% opacity. Hover: bg steps to full Surface Card, border tint shifts to amber-lit at 30% opacity.
- **Static Card (Settings, Auto-Pause):** Surface Hover bg, 16px padding, 12px corners. No border. Contains section header with icon + label + description, followed by controls.
- **Row Card (Editor toolbar):** No background, no padding wrapper. A single horizontal bar: bottom border (Border Default) separating it from adjacent content.

### Inputs / Fields
- **Underline Input (Title):** Transparent background, bottom border (Border Default), bold text. Focus: border color shifts to amber-lit at 50% opacity.
- **Box Input (Search, Keyword):** Surface Card bg, full rounding (pill or lg), Border Default stroke. Focus: border shifts to amber-lit at 50% opacity.
- **Textarea (Editor):** Transparent background, no border. Body font, Body Text color, Placeholder Text for empty state. Fills available vertical space.

### Navigation
- **Header bar:** Sticky top, semi-transparent black (70% opacity) with backdrop-blur-xl. Contains back button (ghost), title/branding (white, bold), and action buttons (ghost or primary).
- **Bottom toolbar (Teleprompter Controls):** Surface Card at 80% opacity, backdrop-blur-xl. Single horizontal row of thin sliders with amber accent. Visible only when playback is paused; fades out during scroll.

### Signature Component: Reading Guide
- Two vertical amber-lit bars (2px wide, 112px tall, 40% opacity) positioned at screen left and right edges, vertically centered. Subtle yellow glow (0 0 12px rgba(234,179,8,0.4)). These mark the reader's focal line. They are the only atmospheric element in the entire system.

## Do's and Don'ts

### Do:
- **Do** use the single amber accent in at most one primary-interaction role per screen.
- **Do** prefer tonal contrast over borders for separating surfaces.
- **Do** use the full safe-area-aware padding on every screen.
- **Do** keep the reading guide bars visible but subtle — they are wayfinding, not decoration.
- **Do** use bold weight, not larger size, to differentiate hierarchy levels.

### Don't:
- **Don't** add a second accent color. Amber-lit is the only accent.
- **Don't** use drop shadows on cards or surfaces. Flat tonal layering only.
- **Don't** decorate the teleprompter viewport. The only visual element beyond text is the reading guide.
- **Don't** use italic, underline (except as input style), or all-caps for emphasis.
- **Don't** exceed the max-width constraints (56rem for lists, 48rem for editor) even on wide screens.
