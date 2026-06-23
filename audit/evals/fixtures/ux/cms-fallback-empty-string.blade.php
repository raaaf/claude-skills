{{--
  CMS page with admin-editable hero text and a default fallback.
  $page['hero_title'] is editable in the admin and stored as a string column.
--}}
<section class="hero">
    {{-- BUG: `??` only catches null. When the admin clears the field it is
         stored as '' (empty string), which passes through `??` and renders
         an empty <h1>. Should use filled()/truthiness, not null-coalescing. --}}
    <h1>{{ $page['hero_title'] ?? 'ein kleiner shop fuer grosse worte' }}</h1>

    <p>{{ $page['hero_subtitle'] ?? 'handgemachte poster' }}</p>
</section>
