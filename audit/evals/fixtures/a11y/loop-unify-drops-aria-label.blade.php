{{-- Gallery thumbnails were consolidated from two branches (a color branch
     and a generic branch) into one loop. Each $thumb still carries its color,
     but the unified aria-label now uses only the index, so color thumbnails
     lost their color name in the accessible name. --}}
<div class="flex flex-wrap gap-2" role="group" aria-label="weitere ansichten">
    @foreach ($imageThumbs as $thumb)
        <button
            type="button"
            @click="current = @js($thumb['url']); mode = 'image'"
            aria-label="ansicht {{ $loop->iteration }}"
            class="size-16 overflow-hidden border focus:outline focus:outline-2"
        >
            <img src="{{ $thumb['url'] }}" alt="" loading="lazy" class="size-full object-cover">
        </button>
    @endforeach
</div>
