---
applies_to: \.(jsx|tsx|js|ts|mjs|cjs|vue|svelte|astro|html?)$|\.blade\.php$|\.(twig|erb|hbs|ejs|liquid)$|\.(css|scss|sass|less|styl)$|tailwind\.config|\.(swift|kt|kts|dart)$|\.(storyboard|xib)$|/values[^/]*/strings\.xml$|/components?/|/pages/|/views?/
priority: recommended
---
# Accessibility Guidelines

Accessibility is not a checklist you run before launch — it is a design constraint that shapes every decision from the first wireframe to the last line of CSS. When you build for accessibility, you build better software for everyone: keyboard users, screen reader users, people with low vision, motor impairments, cognitive differences, and situational limitations like a broken arm or bright sunlight.

The target is WCAG 2.2 Level AA compliance (section XI lists the criteria added over 2.1). This is both a legal baseline in many jurisdictions and a practical standard that catches the most impactful issues.

## Contents
- I. Semantic HTML
- II. ARIA Attributes
- III. Form Accessibility
- IV. Keyboard Navigation
- V. Color & Contrast
- VI. Images & Media
- VII. Interactive Element Sizing
- VIII. Motion & Animation
- IX. Screen Reader Patterns
- X. Tables
- XI. WCAG 2.2 — New Success Criteria (2023, canonical since 2024)

## I. Semantic HTML

HTML elements carry meaning that assistive technologies rely on. A `<button>` announces as a button and responds to Enter and Space. A `<div>` announces as nothing and responds to nothing. Using the correct element is always less work than recreating its behavior.

| Purpose | Correct Element | Common Mistake |
|---------|----------------|----------------|
| Clickable action | `<button>` | `<div onclick>`, `<a href="#">` |
| Navigation link | `<a href="/path">` | `<button>` used for navigation |
| Page region | `<main>`, `<nav>`, `<header>`, `<footer>`, `<aside>` | Generic `<div>` wrappers |
| List of items | `<ul>`, `<ol>`, `<li>` | Paragraphs or divs with bullets |
| Data grid | `<table>`, `<th>`, `<td>` | CSS grid with divs |
| Form field label | `<label for="id">` | Placeholder text as label |

**Heading hierarchy must be logical and unbroken.** One `<h1>` per page (the page title). Headings must not skip levels — do not jump from `<h2>` to `<h4>`. Screen reader users navigate by heading level to understand page structure; a broken hierarchy is like a book with missing chapter numbers.

```html
<!-- BAD — skips h2, uses heading for styling -->
<h1>Dashboard</h1>
<h3>Recent Activity</h3>  <!-- skipped h2 -->
<h3 class="small-text">Tip of the day</h3>  <!-- heading used for styling, not structure -->

<!-- GOOD — logical nesting -->
<h1>Dashboard</h1>
<h2>Recent Activity</h2>
<h2>Quick Tips</h2>
```

**Landmarks** give screen reader users a map of the page. Every page should have at minimum: `<header>` (site banner), `<nav>` (primary navigation), `<main>` (primary content), and `<footer>`. If you have multiple `<nav>` elements, distinguish them with `aria-label`:

```html
<nav aria-label="Primary">...</nav>
<nav aria-label="Breadcrumb">...</nav>
```

## II. ARIA Attributes

ARIA (Accessible Rich Internet Applications) supplements HTML semantics for dynamic and custom components. The first rule of ARIA: **do not use ARIA if a native HTML element achieves the same result.** ARIA does not add behavior — it only adds meaning. A `<div role="button">` announces as a button but does not get keyboard handling, focus management, or form submission for free.

**Essential ARIA patterns:**

- **Icon-only buttons** must have `aria-label` describing the action, not the icon:
  ```html
  <!-- BAD — no accessible name -->
  <button><x-icon-trash /></button>

  <!-- GOOD — action described -->
  <button aria-label="Delete comment"><x-icon-trash /></button>
  ```

- **Decorative elements** must be hidden from the accessibility tree:
  ```html
  <x-icon-decorative-swirl aria-hidden="true" />
  <img src="divider.svg" alt="" aria-hidden="true">
  ```

- **Dynamic content** that updates without page reload must announce changes with live regions:
  ```html
  <!-- Polite: announces when screen reader is idle -->
  <div aria-live="polite" aria-atomic="true">
      {{ $statusMessage }}
  </div>

  <!-- Assertive: interrupts immediately (use sparingly — errors, critical alerts) -->
  <div role="alert">
      {{ $errorMessage }}
  </div>
  ```

- **Expanded/collapsed state** for disclosure widgets:
  ```html
  <button aria-expanded="false" aria-controls="panel-1">Details</button>
  <div id="panel-1" hidden>...</div>
  ```

- **Current page** in navigation:
  ```html
  <a href="/dashboard" aria-current="page">Dashboard</a>
  ```

**New-view checklist (run on every newly added view/page).** These gaps recur in fresh markup — verify each before the view ships:

- [ ] Every icon-only button (edit, delete, close, toggle, expand) has an `aria-label` describing the *action*, not the icon
- [ ] Every interactive non-`<button>`/`<a>` element (clickable `<div>`/`<span>`/`<li>`) has `role`, `tabindex="0"`, and a keyboard handler — or is converted to a real `<button>`
- [ ] Decorative icons/images carry `aria-hidden="true"` (or `alt=""`)
- [ ] One `<h1>`, no skipped heading levels
- [ ] Modals/toasts: focus is trapped while open and returned on close; the dismiss control has an accessible name

**DRY-refactoring repeated markup must preserve every label variant.** When you unify repeated blocks (gallery items, thumbnails, tabs, cards) into one loop or template, each original branch often carried its *own* `aria-label`/`alt`/`aria-*`. A shared loop must reproduce all of them — collapsing a specific label (`aria-label="view {color}"`) onto a generic one (`aria-label="view {n}"`) silently drops the accessible name with no syntax error to catch it. Before and after such a refactor, grep the label-bearing attributes in the block and confirm none were lost:

```bash
grep -nE 'aria-label|aria-[a-z]+|\balt=' {file}
```

This is a self-regression introduced *by* the cleanup itself, so it is easy to miss — the diff looks like a tidy simplification.

## III. Form Accessibility

Forms are where accessibility fails most often — and where it matters most, because forms are how users accomplish tasks.

**Every input needs a visible, associated label.** Placeholder text is not a label — it disappears on focus and has insufficient contrast in most browsers:

```html
<!-- BAD — placeholder as label -->
<input type="email" placeholder="Email address">

<!-- GOOD — proper label association -->
<label for="email">Email address</label>
<input type="email" id="email" name="email">
```

**Error messages must be programmatically linked** to their field so screen readers announce them in context:

```html
<label for="email">Email address</label>
<input
    type="email"
    id="email"
    name="email"
    aria-describedby="email-error"
    aria-invalid="true"
>
<p id="email-error" class="text-red-600" role="alert">
    Please enter a valid email address.
</p>
```

**Required fields** need both visual and programmatic indication:

```html
<label for="name">
    Full name <span aria-hidden="true" class="text-red-500">*</span>
</label>
<input type="text" id="name" name="name" required aria-required="true">
```

**Group related fields** with `<fieldset>` and `<legend>`:

```html
<fieldset>
    <legend>Shipping address</legend>
    <label for="street">Street</label>
    <input type="text" id="street" name="street">
    <!-- more fields -->
</fieldset>
```

**Form submission feedback** must be announced. After a Livewire form submission, set focus to a success/error message or use `aria-live` to announce the result.

## IV. Keyboard Navigation

Every interactive element must be operable with a keyboard alone. This is non-negotiable — it serves not only screen reader users but also power users, users with motor impairments, and anyone whose mouse just stopped working.

**Focus order must follow visual order.** Do not use `tabindex` values greater than 0 — they create a parallel, confusing tab order. Use `tabindex="0"` only to make a non-interactive element focusable when necessary, and `tabindex="-1"` to make an element programmatically focusable but not in the tab sequence:

```html
<!-- Programmatically focusable (for JS focus management), not in tab order -->
<div tabindex="-1" id="modal-title">Edit Profile</div>

<!-- In natural tab order (only needed for custom interactive elements) -->
<div role="button" tabindex="0" @keydown.enter="activate" @keydown.space.prevent="activate">
    Custom Action
</div>
```

**Focus must be visible.** Never remove focus outlines without providing an alternative. The `:focus-visible` pseudo-class lets you show outlines only for keyboard users, not mouse clicks:

```css
/* Remove default outline for mouse users */
:focus:not(:focus-visible) {
    outline: none;
}

/* Strong visible focus for keyboard users */
:focus-visible {
    outline: 2px solid var(--color-focus);
    outline-offset: 2px;
}
```

**Skip links** let keyboard users bypass repetitive navigation. Place a skip link as the first focusable element on the page:

```html
<a href="#main-content" class="sr-only focus:not-sr-only focus:absolute focus:top-4 focus:left-4 focus:z-50 focus:bg-white focus:px-4 focus:py-2">
    Skip to main content
</a>
<!-- ...navigation... -->
<main id="main-content" tabindex="-1">
```

**Focus trapping in modals:** When a modal is open, Tab and Shift+Tab must cycle within the modal. Focus must move to the modal on open and return to the triggering element on close.

**Never hand-roll a modal with manual `role="dialog"`/`aria-modal` attributes.** Use the project's existing modal component (`x-modal` or equivalent) instead — it already solves focus trapping, Escape-to-close, backdrop click, and return-focus in one place. A hand-rolled `<div role="dialog" aria-modal="true">` reintroduces every one of those bugs from scratch, and inconsistently across occurrences. Only skip the component when it genuinely cannot express the required structure — document the reason inline next to the markup.

## V. Color & Contrast

Color contrast is a hard requirement, not a design preference. Insufficient contrast makes text illegible for users with low vision — and uncomfortable for everyone in bright environments.

| Element | Minimum Contrast Ratio | Notes |
|---------|----------------------|-------|
| Normal text (< 18px / < 14px bold) | 4.5:1 | Most body text, labels, captions |
| Large text (>= 18px / >= 14px bold) | 3:1 | Headings, large UI text |
| UI components and graphical objects | 3:1 | Borders, icons, form controls |
| Disabled elements | No requirement | But should still be visually distinguishable |

**Do not convey information through color alone.** A red border on an invalid field is meaningless to a colorblind user. Pair color with text, icons, or patterns:

```html
<!-- BAD — only color indicates error -->
<input class="border-red-500" type="email">

<!-- GOOD — color + icon + text -->
<input class="border-red-500" type="email" aria-describedby="email-error" aria-invalid="true">
<p id="email-error" class="text-red-600">
    <x-icon-exclamation class="inline" aria-hidden="true" />
    Please enter a valid email address.
</p>
```

Test with a color blindness simulator. Roughly 8% of men have some form of color vision deficiency — your interface will be used by many of them.

## VI. Images & Media

**Content images need descriptive alt text** that conveys the image's purpose in context, not just what it depicts:

```html
<!-- BAD — describes appearance, not purpose -->
<img src="chart.png" alt="Bar chart">

<!-- GOOD — describes what the chart communicates -->
<img src="chart.png" alt="Monthly revenue grew 23% from January to March 2026">

<!-- Decorative — empty alt, not missing alt -->
<img src="decorative-border.svg" alt="">
```

Missing `alt` attributes are always a failure. An image without `alt` causes screen readers to announce the filename, which is worse than announcing nothing. Every `<img>` must have an `alt` attribute — set it to `""` for decorative images.

**SVG icons** used as content need accessible names:

```html
<svg role="img" aria-label="Warning">
    <path d="..." />
</svg>
```

**Video and audio** content needs captions (for deaf/hard-of-hearing users) and transcripts (for deafblind users and search engines). Auto-generated captions are a starting point, not a finish line — they must be reviewed for accuracy.

## VII. Interactive Element Sizing

Small touch targets cause errors for users with motor impairments and frustrate everyone on mobile devices. WCAG 2.2 requires a minimum target size of 24x24 CSS pixels (Level AA), but 44x44 pixels is the recommended practical minimum:

```css
/* Minimum interactive target size */
button,
a,
input,
select,
[role="button"] {
    min-height: 44px;
    min-width: 44px;
}

/* For inline links in text, padding provides the target area */
a {
    padding-block: 0.25em;
}
```

Ensure sufficient spacing between adjacent interactive elements so that touching one does not accidentally trigger another. A gap of at least 8px between clickable targets prevents most mis-taps.

## VIII. Motion & Animation

Animations that users cannot control are a barrier — they cause discomfort for people with vestibular disorders, distract users with attention-related disabilities, and drain battery on mobile.

**Respect `prefers-reduced-motion`** for every animation:

```css
/* Default: enable animation */
.fade-in {
    animation: fadeIn 300ms ease-out;
}

/* Reduced motion: instant or no animation */
@media (prefers-reduced-motion: reduce) {
    .fade-in {
        animation: none;
    }

    * {
        animation-duration: 0.01ms !important;
        transition-duration: 0.01ms !important;
        scroll-behavior: auto !important;
    }
}
```

**No auto-playing content** that moves, blinks, or scrolls for more than 5 seconds without a pause mechanism. Carousels, animated banners, and auto-advancing slideshows must have pause/stop controls. Better yet — do not auto-play at all.

**No content that flashes** more than 3 times per second. This can trigger seizures in users with photosensitive epilepsy. This is a Level A requirement — the strictest level.

## IX. Screen Reader Patterns

**Visually hidden text** provides context for screen reader users without affecting visual layout. Use a utility class, never `display: none` (which hides from screen readers too):

```css
.sr-only {
    position: absolute;
    width: 1px;
    height: 1px;
    padding: 0;
    margin: -1px;
    overflow: hidden;
    clip: rect(0, 0, 0, 0);
    white-space: nowrap;
    border-width: 0;
}
```

```html
<button>
    <x-icon-trash aria-hidden="true" />
    <span class="sr-only">Delete comment by {{ $author }}</span>
</button>
```

**Live regions** announce dynamic content changes. Use them for:
- Flash messages and toast notifications (`role="status"` or `aria-live="polite"`)
- Error summaries after form validation (`role="alert"`)
- Loading states (`aria-busy="true"` on the updating container)
- Real-time data updates (stock prices, chat messages)

```html
<!-- Loading state -->
<div aria-busy="true" aria-live="polite">
    <span class="sr-only">Loading results...</span>
    <x-spinner aria-hidden="true" />
</div>

<!-- After load completes -->
<div aria-busy="false" aria-live="polite">
    <span class="sr-only">{{ $count }} results loaded.</span>
    <!-- results -->
</div>
```

**Live regions must stay in the DOM — never `hidden`/`display:none`.** Screen readers only announce changes inside a region that is already present and rendered when the change happens. A region that is toggled into existence (or unhidden) together with its message announces nothing.

```html
<!-- BEFORE (broken): region enters the DOM with the message — no announcement -->
@if ($saved)
    <div aria-live="polite">Gespeichert.</div>
@endif

<!-- AFTER (correct): region is always rendered, only the content changes -->
<div aria-live="polite">
    @if ($saved) Gespeichert. @endif
</div>
```

The same applies to `x-show`/`hidden` on the region itself: hide or empty the *content*, never the live region container. (Recurring bug class: aria-live regions rendered conditionally, 2026-06-14.)

**Before adding a new live region, check existing announcement channels.** If a success toast (`role="status"`) or error container (`role="alert"`) already announces the same event, a second `aria-live` wrapper double-announces it in screen readers. Wire the message into the existing channel instead; add a new `aria-live` region only when no existing channel carries the information.

## X. Tables

Data tables need structural markup so screen readers can navigate cells and understand their relationship to headers.

```html
<table>
    <caption>Q1 2026 Sales by Region</caption>
    <thead>
        <tr>
            <th scope="col">Region</th>
            <th scope="col">Revenue</th>
            <th scope="col">Growth</th>
        </tr>
    </thead>
    <tbody>
        <tr>
            <th scope="row">Europe</th>
            <td>$1.2M</td>
            <td>+15%</td>
        </tr>
    </tbody>
</table>
```

- Always use `<th>` for header cells with `scope="col"` or `scope="row"`
- Add `<caption>` to describe the table's purpose (can be visually hidden with `sr-only` if the design does not accommodate it)
- Never use tables for layout — only for tabular data
- For complex tables with multi-level headers, use `id` and `headers` attributes to explicitly associate data cells with their headers
- Responsive tables should remain accessible — do not replace the table with a visual card layout without providing an equivalent accessible structure

## XI. WCAG 2.2 — New Success Criteria (2023, canonical since 2024)

WCAG 2.2 added 9 new criteria over 2.1. All projects targeting AA should now meet 2.2 AA, not just 2.1.

### 2.4.11 Focus Not Obscured (Minimum) — AA

When an element receives keyboard focus, it must not be fully hidden by sticky headers, footers, or other overlays. Test by tabbing through a page with a fixed header — every focused control must remain at least partly visible.

Fix patterns:
```css
:target, :focus-visible {
  scroll-margin-top: 80px; /* match sticky header height */
}
```

### 2.4.12 Focus Not Obscured (Enhanced) — AAA

Like 2.4.11 but the focused element must be FULLY visible, not just partly. Hard to meet with sticky UI — usually AA is the practical target.

### 2.4.13 Focus Appearance — AA

The focus indicator must:
- Have a contrast ratio of at least 3:1 against the unfocused element
- Be at least as large as a 2px solid outline around the element
- Not be obscured by other content

`outline: none` without a replacement violates this. Custom focus styles MUST be visible against both light and dark backgrounds the element appears on.

### 2.5.7 Dragging Movements — AA

Any function that uses dragging must offer a single-pointer alternative (click, button, keyboard). Examples: drag-to-reorder lists need up/down arrow buttons; map drag needs zoom buttons; slider needs arrow-key support.

### 2.5.8 Target Size (Minimum) — AA

Interactive targets must be at least **24x24 CSS pixels**, unless one of:
- The target is in a sentence (inline link)
- The target's size is determined by the user agent (native form controls)
- The target is at least 24px AWAY from any other 24x24 target (spacing exception)

This is stricter than the previous 44x44 AAA criterion which still applies for AAA. Audit dense UI (icon-button toolbars, calendar cells, table action menus) carefully.

### 3.2.6 Consistent Help — A

If the page provides help (contact info, chat widget, FAQ link), it must appear in the same relative order across all pages where it exists. Help in footer on one page, top-right on another → fail.

### 3.3.7 Redundant Entry — A

Information the user already entered (in the same session) must not be asked for again, unless:
- Re-entry is essential (password confirmation)
- Information has expired
- Re-entry is required for security

For multi-step forms: pre-fill from prior steps. "Same as billing address" checkbox is the canonical pattern.

### 3.3.8 Accessible Authentication (Minimum) — AA

Auth must not require cognitive function tests (puzzles, CAPTCHA images, memorize-and-transcribe codes) UNLESS:
- An alternative method exists (passkeys, magic link, OAuth)
- A mechanism helps the user (paste enabled, password manager autofill works)

Concrete: password fields must allow paste (no `onpaste="return false"`). 2FA codes must be selectable/autofillable. CAPTCHAs require an audio or alternative track.

### 3.3.9 Accessible Authentication (Enhanced) — AAA

No cognitive-function test EVER, including object recognition or personal-content tests. Practical only when passkey + OAuth cover all users.

### Audit Implications

When auditing a new project, default expectation is WCAG 2.2 AA. If only 2.1 is met, flag as Important findings for each missing 2.2 criterion.

---

Continued: section XII (Preference Queries and Feedback Channels) lives in accessibility-2026.md.
