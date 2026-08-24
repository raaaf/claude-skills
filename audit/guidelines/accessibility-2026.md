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
