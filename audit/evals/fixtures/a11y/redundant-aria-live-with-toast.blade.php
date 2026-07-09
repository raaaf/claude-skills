{{-- An invoice summary toggle was added. The component already notifies via
     the global success toast (role="status" in the layout, triggered by
     $this->notify()), but the change ALSO added a dedicated aria-live wrapper
     announcing the same confirmation, so screen readers hear it twice. --}}
<div>
    <x-toggle
        wire:model.live="useSummaryLine"
        :label="__('invoicing.summary_line_toggle')"
    />

    <div aria-live="polite" class="sr-only">
        @if($summaryLineConfirmation)
            {{ __('invoicing.summary_line_enabled') }}
        @endif
    </div>
</div>

@php
    // Component excerpt for context:
    // public function updatedUseSummaryLine(): void
    // {
    //     $this->summaryLineConfirmation = true;
    //     $this->notify(__('invoicing.summary_line_enabled')); // global toast, role="status"
    // }
@endphp
