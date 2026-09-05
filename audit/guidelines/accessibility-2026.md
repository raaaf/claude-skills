---
applies_to: \.(jsx|tsx|js|ts|mjs|cjs|vue|svelte|astro|html?)$|\.blade\.php$|\.(twig|erb|hbs|ejs|liquid)$|\.(css|scss|sass|less|styl)$|tailwind\.config|\.(swift|kt|kts|dart)$|\.(storyboard|xib)$|/values[^/]*/strings\.xml$|/components?/|/pages/|/views?/
priority: recommended
---
# Accessibility: 2026 Additions

Continuation of accessibility.md (section XII). Always read together with accessibility.md.


## XII. Preference Queries and Feedback Channels (2026)

**Beyond `prefers-reduced-motion`** — two more preference queries that translucent/high-polish UI must honor:

```css
@media (prefers-reduced-transparency: reduce) {
  .toolbar { background: white; backdrop-filter: none; } /* frosted -> solid */
}
@media (prefers-contrast: more) {
  .card { background: var(--surface-solid); border: 1px solid var(--border-strong); }
}
```

Any `backdrop-filter` surface without a `prefers-reduced-transparency` fallback is a finding (Minor). Also: avoid slow looping oscillations near 0.2 Hz (one cycle per ~5s, vestibular trigger) and abrupt full-screen brightness jumps — ease dark/light theme changes.

**Paste must never be blocked** on any input or textarea (`onpaste="return false"`, `e.preventDefault()` in paste handlers). Section 3.3.8 covers password fields; the rule is general — blocking paste breaks password managers, screen readers, and motor-impaired users everywhere.

**Disabled submit buttons must explain why.** A disabled primary action with no visible reason (missing field hint, validation summary) leaves keyboard and screen-reader users stranded. Prefer enabled-but-validating over silently disabled.

**Toasts are never the only channel for critical information.** They time out and are easy to miss with a screen reader. Errors and state changes that matter must also appear persistently (inline error, status region with `aria-live`).

## XIII. Input Typing and Mobile Keyboards (2026)

Every input needs three things, and `inputmode` is the one most often missing:

| Attribute | Decides |
|---|---|
| `<label for>` | whether the field is announced at all |
| `type` | validation, autofill, and the semantic role |
| `inputmode` | which on-screen keyboard a touch device opens |

`type` alone does not settle the keyboard. `type="text"` on a one-time-code, a postcode, or a card's last four digits opens a full QWERTY keyboard and makes the user hunt for digits; `inputmode="numeric"` opens the number pad while keeping text semantics and leading zeros intact. The pairing matters because `type="number"` is the wrong fix for these: it strips leading zeros, exposes a spinner nobody wants on a postcode, and in several browsers silently discards non-numeric input the user cannot see they typed.

Useful values: `numeric` (digits only, e.g. OTP, PIN, postcode), `decimal` (prices, quantities), `tel`, `email`, `url`, `search`.

```html
<label for="otp">Verification code</label>
<input id="otp" type="text" inputmode="numeric" autocomplete="one-time-code" maxlength="6">
```

Finding (Minor) when a numeric-only field on a project with any mobile surface has no `inputmode`. Not a finding on a desktop-only internal tool, where the attribute has no effect. A missing `<label>` or a wrong `type` stays the more severe finding of the three.

## XIV. Contrast Findings Against the Effective Cascade, Not Raw Tokens (2026)

**Compute colors from what the browser renders, never from the token file.** A `tokens.css` (or Figma export) value is the start of a cascade, not its end: `app.css` overrides the same custom property later in the file, `:root` is redefined several times (light, `data-theme="dark"`, `prefers-color-scheme`, `prefers-contrast: more`), and a `@theme` block can shadow the token again. A contrast finding that quotes the raw token as the rendered color is wrong whenever any later rule redefines the property. Two workers in two rounds reported the same refuted dark-mode elevation claim from raw `tokens.css` values (2026-08-13).

Before any contrast, elevation, or focus-ring finding:

1. Resolve the property through every `:root`/`[data-theme]`/media block in the compiled or authored CSS, last matching declaration wins per scheme state (there are usually three states, not two).
2. When a browser is available, read `getComputedStyle()` in the target scheme; wait ~600ms after a `data-theme` switch, the first two frames still carry the previous scheme's colors.
3. State in the finding which resolved values (hex or OKLCH) and which scheme state the ratio was computed from. A finding without the resolved pair is `low confidence` and not fixable.

**Exclusion and gating lists use exact class names, never `[class*=]` substrings.** A contrast or security gate that skips elements via `[class*="btn"]` or `className.includes('badge')` also skips `btn-link`, `no-btn-style`, `badge-count` and every future class that happens to contain the substring, on the trigger AND on all its descendants. Two of four Critical findings of one run were caused by such substring exclusions (2026-08-13). Finding (Important) when an allow/skip list matches on a substring; the fix is an explicit class list (`:is(.btn, .btn-primary)`, `classList.contains()`), applied to the trigger element and, when descendants are meant to be covered, to an explicit descendant selector rather than an inherited substring match.
