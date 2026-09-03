---
applies_to: \.(css|scss|sass|less|styl)$|tailwind\.config|\.(jsx|tsx|vue|svelte|astro|html)$|\.blade\.php$|/fonts?/|\.(swift|kt|dart)$
priority: recommended
---
# Typography Guidelines

Typography is often the foundation of great design. Make sure to pay the attention it deserves.

## Contents
- I. Body Text Is Everything
- II. Font Selection & Pairing
- III. Emphasis & Formatting
- IV. Spacing & Layout
- V. Type Composition Details
- VI. Screen-Specific Considerations
- VII. Tables & Numeric Typography
- VIII. OpenType Features
- IX. Font Rendering & Loading
- X. Text Wrapping & Decoration
- XI. Properties Over Raw Feature Tags (2026)
- XII. Mobile Inputs and Text Scaling (2026)
- XIII. Structure, Direction, Truncation (2026)

## I. Body Text Is Everything

The typographic quality of any interface is determined primarily by the body text — there's simply more of it than anything else. Start every project by making body text beautiful, then work outward to headings, captions, and UI chrome.

Four properties control body text appearance:

| Property | Web Value | CSS Implementation |
|----------|-----------|-------------------|
| Font size | 16-22px (15px minimum) | `font-size: clamp(1rem, 1.125rem, 1.375rem)` |
| Line height | 120-145% of font size | `line-height: 1.35` (adjust per font) |
| Line length | 45-90 characters | `max-width: 36em` on text container |
| Font family | Professional, distinctive | Avoid Arial, Inter, Roboto, Times, system defaults |

Fonts that have a tall x-height look larger at the same point size and may need less line spacing. Fonts with a small x-height need more. Always test visually — the numbers are starting points, not absolutes.

## II. Font Selection & Pairing

The fastest, most visible upgrade is replacing a default font with a professional one. A well-designed font embeds the expertise of a type designer into every document.

**Audit guard: a typography review never requires a new typeface.** The font-family row above informs new projects; it is NOT an audit finding. Use the product's existing type system, never propose swapping in a paid or different face to satisfy this guideline. Rendering details (smoothing, wrapping, tabular numbers) do not override the project's chosen family.

When mixing fonts, give each a consistent role (e.g., one for body, one for headings; or one for content center, one for UI periphery). You CAN pair serif+serif or sans+sans — the myth that you must mix serif with sans is false. What matters is that the two fonts are identifiably different. Lower contrast between paired fonts can actually be more effective than high contrast. Look at newspapers: serif body + different serif headlines is the norm.

## III. Emphasis & Formatting

**Bold or italic — pick one, not both.** These are tools for emphasis. Overuse neutralizes their effect: if everything screams, nothing is heard. Italic is for subtle emphasis within running text; bold creates more visual weight and works better for headings. Text that is neither bold nor italic is called "roman." It should be the overwhelmingly dominant style.

**All caps & small caps:** Fine for labels, short headings, navigation items — anything under one line. Always add letter-spacing: `letter-spacing: 0.05em` to `0.12em`. Capitals are designed to sit next to lowercase; when grouped together they appear too tight. ALL-CAPS paragraphs are self-defeating: harder to read (we recognize words by their varied vertical contour — caps flatten everything into rectangles), and readers fatigue fast. If you use CSS `font-variant: small-caps`, ensure the font has real small-cap glyphs. Faked small caps (browser-scaled regular caps) have wrong weight and proportions.

**Underlining:** On the web, underlines mean links. Don't use underline for emphasis — it creates false affordance.

## IV. Spacing & Layout

**Line spacing (leading):** 120-145% of font size. Single-spaced is too tight, double-spaced is too loose — both are typewriter-era relics. Fonts with tall x-heights or heavy strokes need more spacing. Light or small-x-height fonts need less. Line spacing affects document length more than font size does.

**Line length (measure):** 45-90 characters including spaces. This is the single most important layout constraint for readability. Quick test: you should fit 2-3 lowercase alphabets on one line. On the web, control line length with `max-width` on text containers, NOT by relying on viewport edges.

**Paragraph spacing:** Use first-line indents (1-4x the font size) OR space between paragraphs (50-100% of body text size). Never both. On the web, `margin-bottom` on paragraphs is more practical than indents.

**Page margins / padding:** Generous whitespace is a feature, not a waste. The edges of the screen are not the boundaries of your text block. Professional typography never fills edge-to-edge. Set `max-width` and center the text block for comfortable reading.

**Centered text:** Both edges are ragged, making blocks hard to read and hard to align with other elements. Reserve centering for short headings, hero text, or single-line labels.

## V. Type Composition Details

- One space between sentences. Always.
- Curly quotes `""` `''`, not straight `""` `''`. CSS: `quotes: '"' '"' ''' ''';`
- Proper dashes: Hyphen `-` for compound words. En dash `–` for ranges. Em dash `—` for parenthetical statements. Never `--`.
- Ellipsis: Use the real character `...` (not three periods `...`).
- Kerning on: `font-kerning: normal` — always. Let the font's built-in spacing intelligence work.

## VI. Screen-Specific Considerations

- A pixel on desktop ≠ a pixel on mobile (different viewing distances, different DPI). Text may need to be slightly larger on mobile despite smaller screens.
- Consider dark gray body text (`#333`) over pure black on screens — emitted light creates harsher contrast than reflected light on paper.
- Typography rules don't change with screen size. In responsive design, line length is the hardest to manage — make it the priority.
- A well-constrained `max-width` solves most responsive typography problems.
- Suppress hyphenation on headings. Use `hyphens: auto` on justified body text only if your language/browser supports good hyphenation.

## VII. Tables & Numeric Typography

- Start with no borders. Turn them on selectively only where the data needs visual separation. Cell borders create clutter — the text itself forms an implied grid. Favor whitespace over lines.
- Use thin borders (0.5-1px) when needed. Heavy borders create noise that upstages the data.
- Use tabular (monospaced-width) figures for number columns: `font-variant-numeric: tabular-nums`.
- For data-heavy tables (dashboards, pricing, financial), combine lining and tabular figures: `font-variant-numeric: lining-nums tabular-nums`.
- Use oldstyle figures for numbers in running prose — they blend with lowercase letterforms: `font-variant-numeric: oldstyle-nums`.
- Use proper typographic fractions where applicable: `font-variant-numeric: diagonal-fractions` turns `1/2` into a stacked fraction glyph.

```css
/* Data table — aligned columns */
.data-table td { font-variant-numeric: tabular-nums lining-nums; }

/* Body text — numbers blend with prose */
.prose { font-variant-numeric: oldstyle-nums; }

/* Recipes, measurements */
.fraction { font-variant-numeric: diagonal-fractions; }
```

## VIII. OpenType Features

Modern fonts contain advanced features that most interfaces leave unused. Enable them deliberately.

**Slashed zero** — distinguishes `0` from `O` in code-adjacent UIs (IDs, codes, tokens):

```css
.code, .mono, .id-display {
  font-variant-numeric: slashed-zero;
}
```

**Contextual alternates** — adjusts glyphs based on surrounding characters. Keep enabled (on by default in most browsers, but explicit is better):

```css
body {
  font-feature-settings: "calt" 1;
}
```

**Disambiguation stylistic set** — some fonts (e.g., Inter) offer `ss02` to distinguish `I`/`l`/`1` and `0`/`O`:

```css
.ui-text {
  font-feature-settings: "ss02" 1;
}
```

**Disable font synthesis** — prevents browsers from faking bold/italic when the font file is missing. Faux bold adds uniform stroke weight (looks wrong), faux italic slants glyphs mechanically (looks worse):

```css
body {
  font-synthesis: none;
}
```

## IX. Font Rendering & Loading

**Optical sizing** — variable fonts with an `opsz` axis adjust stroke contrast and spacing based on size. Leave auto (the default), do not disable it:

```css
body {
  font-optical-sizing: auto;
}
```

**Antialiased smoothing** — on retina displays, use antialiased (thinner, lighter) over auto (subpixel, which can look heavy):

```css
body {
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
}
```

**font-display: swap** — prevents invisible text during font loading. The browser shows a fallback immediately, then swaps when the custom font loads:

```css
@font-face {
  font-family: 'CustomFont';
  src: url('/fonts/custom.woff2') format('woff2');
  font-display: swap;
}
```

**Variable font weight** — use continuous values (100-900) instead of jumping between fixed weights. This enables fine-tuned weight control for different text sizes:

```css
h1 { font-weight: 720; }
h2 { font-weight: 680; }
body { font-weight: 400; }
caption { font-weight: 340; }
```

## X. Text Wrapping & Decoration

**text-wrap: balance** — distributes text evenly across lines in headings, preventing orphans and widows. Use on headings only (performance cost on long text):

```css
h1, h2, h3 {
  text-wrap: balance;
}
```

**text-wrap: pretty** — reduces orphans in body text (last line with a single word). Less aggressive than `balance`, suitable for paragraphs:

```css
p {
  text-wrap: pretty;
}
```

**Underline offset** — push underlines below descenders so they do not cut through `g`, `p`, `y`:

```css
a {
  text-underline-offset: 0.15em;
  text-decoration-thickness: 1px;
}
```

**Justified text with hyphens** — if using `text-align: justify`, always pair with `hyphens: auto` to prevent rivers of whitespace:

```css
.justified-text {
  text-align: justify;
  hyphens: auto;
  -webkit-hyphens: auto;
}
```

**Letter spacing on uppercase** — uppercase and small-caps text appears too tight because capitals are designed to sit next to lowercase. Always add spacing:

```css
.uppercase, .small-caps {
  letter-spacing: 0.05em;
  /* Already mentioned in Section III, reinforced here with CSS */
}
```

## XI. Properties Over Raw Feature Tags (2026)

When a dedicated CSS property exists, use it instead of the raw OpenType tag or variation axis. Properties keep working when a non-variable fallback font renders; raw tags silently do nothing on fallbacks.

| Raw tag (finding) | Property (fix) |
|---|---|
| `font-variation-settings: "wght" 650` | `font-weight: 650` |
| `font-variation-settings: "opsz" auto` | `font-optical-sizing: auto` |
| `font-feature-settings: "tnum" 1` | `font-variant-numeric: tabular-nums` |
| `font-feature-settings: "zero" 1` | `font-variant-numeric: slashed-zero` |
| `font-feature-settings: "smcp" 1` | `font-variant-caps: small-caps` |

Reserve `font-feature-settings` for tags with no property of their own (stylistic sets `ss01`-`ss20`, character variants `cv01`-`cv99`) and `font-variation-settings` for custom axes (`"GRAD" 80`). Section VIII's `ss02` usage is therefore correct; a `"tnum"` usage is not.

Web font format: `.ttf`/`.otf` served on the web is a finding; use `.woff2`.

## XII. Mobile Inputs and Text Scaling (2026)

**iOS input zoom:** focusing an input with text below `16px` zooms the whole page in iOS Safari. Inputs need `16px` on mobile viewports (`text-base sm:text-sm` in Tailwind). The `maximum-scale=1` viewport meta is NOT a reliable fix either way: Safari and modern Chrome/Firefox mostly ignore it for pinch zoom, but some browsers and WebViews still honor it and block zooming, which fails WCAG 1.4.4 wherever it is honored — flag `maximum-scale=1` as Important wherever it appears.

**Layout must scale with text.** Users change text size (browser setting, Dynamic Type). Spacing that must track text (line boxes, gaps inside text components, max-width of text columns) belongs in `rem`/`em`, not fixed px, so a larger base font does not break the layout.

## XIII. Structure, Direction, Truncation (2026)

**Heading sizes descend with level.** Compare computed sizes across the page: an `h3` rendering larger than an `h2` on the same page is a finding. Deep levels may share a size if weight or letter-spacing keeps them distinct. Pick the tag from the document outline, control size with CSS — never choose a lower level because it "looks right" (heading-level semantics themselves are covered in the accessibility guideline).

**Logical properties for direction.** In any codebase with RTL ambitions (i18n present, `dir` attribute anywhere): `margin-left`/`padding-right`/`text-align: left` are findings; use `margin-inline-start`, `padding-inline-end`, `text-align: start`. Set `lang` so browsers pick correct quotes and hyphenation.

**Truncation must not destroy content.** `truncate`/`line-clamp` on values that matter (names, IDs, amounts) needs the full value reachable somewhere — tooltip, title attribute, or expanded view. Truncation with no escape hatch is a finding.

## XIV. Overflow and Descender-Safe Underlines (2026)

**Unbreakable strings need an explicit escape.** A long word, URL, file path, hash, or user-supplied ID has no break opportunity, so it overflows its container or forces a horizontal scrollbar on the whole page. Any container that can receive such a value needs `overflow-wrap: break-word` (the modern name; `word-wrap` is the legacy alias). This is a finding wherever user-generated or machine-generated strings render into a fixed-width box: comment bodies, email addresses in table cells, breadcrumb paths, error messages carrying a stack frame.

```css
.comment-body, .breadcrumb, .cell-id {
  overflow-wrap: break-word;
}
```

The mirror image is just as common: **labels, badges, chips and buttons that must never wrap.** A two-word badge breaking onto a second line silently changes row heights and breaks alignment across a list. Use `white-space: nowrap` there, and pair it with a truncation strategy if the value can grow (see section XIII, truncation must stay reachable).

Do not apply `overflow-wrap: break-word` globally at `:root`. It also breaks ordinary prose at awkward points once a line is tight, and hides the layout bug instead of fixing it.

**Descender-safe underlines, the precise form.** Section X gives `text-underline-offset` as the blunt instrument: it pushes every underline down by a fixed amount, whether the line contains descenders or not. Two properties do it properly:

```css
a {
  text-underline-position: from-font;   /* use the font's own underline metric */
  text-decoration-skip-ink: auto;       /* interrupt the line around g, p, y, j */
}
```

`from-font` reads the position the type designer specified instead of guessing, and `skip-ink: auto` (the default in current browsers, worth stating explicitly so a reset cannot silently disable it) breaks the stroke around descenders rather than striking through them. Prefer these over a hand-tuned offset; keep `text-underline-offset` only where a specific design calls for more air than the font metric gives.

## XV. Token Classes Over Raw Utilities (2026)

When the project defines typographic token classes (`.heading-1`, `.text-body`, `@apply`-composed or CSS-variable-based scales), a heading or body element styled with raw size/weight/leading utilities (`text-2xl font-semibold leading-tight`) is an anti-pattern: it forks the scale, drifts on the next token change, and is invisible to a design-token audit. Report the raw utility stack on any element the token system covers as Minor (Important when the values differ from the token they imitate). A project without a token system is out of scope for this rule (2026-08-29).
