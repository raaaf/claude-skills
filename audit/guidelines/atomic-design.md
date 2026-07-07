---
applies_to: \.(jsx|tsx|vue|svelte|astro)$|\.blade\.php$|/components?/|\.(swift|kt|dart)$
priority: mandatory
---

# Atomic Design & Component Composition Checklist

A lens for component architecture: tokens (atoms) to components to composed blocks to pages.
The goal is reuse and consistency, not "atomic for purity's sake". Only flag on a concrete,
detectable signal (see Must-verify). Subjective "could be more atomic" findings are not allowed.

## Scope

- Applies to component frameworks (React, Vue, Svelte, Blade/Livewire, Astro) and declarative
  native UI (SwiftUI, Jetpack Compose, Flutter).
- Skip files without UI components (pure backend, CLI, config, data).
- Overlaps with `architecture.md` XII (raw HTML instead of a component): that rule owns the
  single-element case; this file owns the layering (tokens, composition, variants, god-components).

## I. Atoms = design tokens

| Signal | Severity |
|---|---|
| Raw hex/rgb color, px spacing, font-size, radius, or shadow that has a named token | Important |
| Same raw value repeated where a token would centralize it | Important |
| One-off value with no matching token, or no token system exists at all | not a finding |

Detect: locate the token source (`tailwind.config`, `:root` CSS vars, `tokens.*`, theme file),
then grep the diff against it. Example: `color: #1a1a1a` where `--color-ink` / `text-ink` exists.
This is the atom layer of the design system; a raw value bypassing it is the highest-signal finding.

## II. Components instead of duplicated composition

| Signal | Severity |
|---|---|
| Same markup/view block appears 3+ times (greppable) and should be one component | Important |
| Same block appears 2x | Minor |
| Variant sprawl: same UI function with divergent props/classes/naming (e.g. three "Badge"s) | Important |

## III. Organisms = god-components

- A component doing too much: very long file, many responsibilities, deep prop-drilling chains
  (props only passed through). Heuristic, no hard threshold: flag with concrete evidence
  (line count, prop count, passed-through props), never a blanket claim. Usually Minor/Important.
- Composition over configuration: a component with many boolean mode-props is a smell;
  slot/children composition is usually better. Flag only with the prop list as evidence.

## IV. Layering / layer break

- An atom/molecule that fetches data or holds business logic (atoms should be presentational).
  Detect: an API call or store access inside a purely presentational component. Important.
  Overlaps `architecture.md` layer rules; consolidate into one finding when both apply.

## Must-verify BEFORE flagging

- **Token really exists:** open the token source and name the matching token before any
  "raw value vs token" finding. No token found means no violation (it is an architecture
  suggestion at most, not a breach).
- **Component really exists:** grep the repo for the component (name + path) before
  "should use component X". Hallucinated components are not allowed.
- **Count duplicates:** actually grep the "3+ times" and cite the locations, do not estimate.
- **Prove god-components:** give the line count / prop count / passed-through props as evidence.

## Severity guide

- Important: token break with an existing token system, 3+ duplicate block, data fetch in an atom.
- Minor: 2x duplicate, mild variant drift, moderate god-component.
- Never Critical: atomic design is maintainability, not a correctness or security problem.
