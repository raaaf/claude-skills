{{-- Card shown for a single occurrence of a recurring series. --}}
<div class="occurrence-card">
    <p>{{ $occurrence->title }}</p>

    @if($isSeriesMember)
        <button wire:click="proposeSwap" wire:loading.attr="disabled">
            Vorschlagen
        </button>
    @endif
</div>
