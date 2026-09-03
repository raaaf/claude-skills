<div class="attendance-actions">
    <button
        type="button"
        x-on:click="$wire.confirm('{{ __('events.confirm_hint') }}')"
        class="btn btn-primary"
    >
        {{ __('events.confirm_action') }}
    </button>

    <button type="button" x-on:click="$wire.cancel()" class="btn btn-ghost">
        {{ __('events.cancel_action') }}
    </button>
</div>
