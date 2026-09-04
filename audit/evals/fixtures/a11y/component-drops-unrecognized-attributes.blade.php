{{-- resources/views/components/icon-link.blade.php --}}
@props(['href', 'label', 'icon'])
<a href="{{ $href }}" class="inline-flex items-center gap-2">
    <x-icon :name="$icon" class="size-4" />
    <span>{{ $label }}</span>
</a>

{{-- Call sites in templates/partials/social-bar.blade.php. A previous a11y
     round added aria-hidden and tabindex to the decorative duplicates; the
     diffs looked right, but the component never merges $attributes, so none
     of these attributes reach the rendered <a>. --}}
<x-icon-link :href="$profile['url']" :label="$profile['label']" :icon="$profile['icon']" />
<x-icon-link :href="$profile['url']" label="" :icon="$profile['icon']" aria-hidden="true" tabindex="-1" />
<x-icon-link href="#top" label="" icon="arrow-up" aria-hidden="true" tabindex="-1" />
