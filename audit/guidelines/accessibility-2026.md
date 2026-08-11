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
