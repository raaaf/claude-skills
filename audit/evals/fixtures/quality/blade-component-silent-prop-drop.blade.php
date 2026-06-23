{{-- Target resources/views/components/stat-card.blade.php declares: @props(['label', 'value', 'trend']) --}}
<x-stat-card
    :label="$title"
    :value="$amount"
    :trendDirection="$dir"
/>
