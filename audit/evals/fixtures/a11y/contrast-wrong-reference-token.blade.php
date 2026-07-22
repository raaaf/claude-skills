{{-- Fixture: dark-mode contrast must be computed against the PROJECT's theme
     tokens, not Tailwind's default palette. The @theme excerpt below mirrors the
     project's app.css: gray-900 is overridden to a much darker, achromatic OKLCH
     value than Tailwind's default #101828. A focus ring of brand red on
     dark:bg-gray-900 reaches ~3.2:1 against the DEFAULT gray-900 (passes the 3:1
     non-text minimum) but only ~2.6:1 against the PROJECT token — the finding
     exists ONLY when the ratio is resolved from the real token. --}}

{{-- app.css (project theme source, verbatim excerpt):
@theme {
    --color-brand: oklch(0.55 0.22 29);          /* scarlet #E7301C-ish */
    --color-gray-900: oklch(0.16 0 0);           /* achromatic, darker than Tailwind default */
    --color-gray-950: oklch(0.11 0 0);
}
--}}

<button
    type="button"
    class="rounded-lg bg-white px-4 py-2 text-sm font-medium text-gray-700 focus:outline-hidden focus-visible:ring-3 focus-visible:ring-brand dark:bg-gray-900 dark:text-gray-200"
>
    {{ __('shared.save') }}
</button>
