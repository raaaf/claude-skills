{{-- templates/flexible/two-columns.blade.php --}}
@php
    $heading = get_sub_field('heading');
    $column_1 = get_sub_field('column_1');
    $column_2 = get_sub_field('column_2');
    $footnote = get_sub_field('footnote');
    $background = get_sub_field('background_color') ?: 'primary';
@endphp

<x-section :background="$background">
    @if($heading)
        <h2 class="text-3xl font-bold">{{ $heading }}</h2>
    @endif

    <div class="grid gap-8 md:grid-cols-2">
        <div class="prose">
            {!! $column_1 !!}
        </div>

        <div class="prose">
            {!! $column_2 !!}
        </div>
    </div>

    @if($footnote)
        <p class="mt-6 text-sm">{!! wp_kses_post($footnote) !!}</p>
    @endif
</x-section>
