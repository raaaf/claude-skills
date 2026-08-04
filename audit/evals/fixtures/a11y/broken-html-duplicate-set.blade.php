{{-- templates/flexible/logo-slider.blade.php --}}
@php
    $logos = get_sub_field('logos') ?: [];
@endphp

<x-section>
    <div class="overflow-hidden" x-data="logoSlider">
        <ul class="flex animate-marquee gap-12">
            @foreach($logos as $logo)
                <li>
                    <a href="{{ $logo['link'] }}">
                        <img src="{{ $logo['image']['url'] }}" alt="{{ $logo['image']['alt'] }}" width="160" height="60">
                    </a>
                </li>
            @endforeach
        </ul>

        {{-- Duplicate set for the seamless marquee loop --}}
        <ul class="flex animate-marquee gap-12" aria-hidden="true" inert
            @foreach($logos as $logo)
                <li>
                    <a href="{{ $logo['link'] }}">
                        <img src="{{ $logo['image']['url'] }}" alt="{{ $logo['image']['alt'] }}" width="160" height="60">
                    </a>
                </li>
            @endforeach
        </ul>
    </div>
</x-section>
