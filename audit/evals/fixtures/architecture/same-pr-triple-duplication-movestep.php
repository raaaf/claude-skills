<?php

namespace App\Livewire;

use App\Models\Enrollment;
use App\Services\EnrollmentService;
use Illuminate\Support\Carbon;
use Livewire\Component;

/**
 * Eval fixture: two near-identical methods introduced in the SAME diff.
 * moveStep() and moveJourneyStep() duplicate the same parse/lookup/error-
 * mapping sequence; the audit must flag the duplication (extract or
 * delegate), not just each method in isolation. 5th real-world occurrence
 * of this class (2026-07-06 learning log).
 */
class Timeline extends Component
{
    public function moveStep(int $enrollmentId, int $stepId, string $date): void
    {
        $enrollment = Enrollment::query()->forUser()->running()->find($enrollmentId);

        if (! $enrollment) {
            $this->notifyError(__('journey.step_move_failed'));

            return;
        }

        try {
            $newDueDate = Carbon::createFromFormat('Y-m-d', $date)->startOfDay();
        } catch (\Throwable) {
            $this->notifyError(__('journey.step_move_invalid_date'));

            return;
        }

        $step = $enrollment->journey->steps()->find($stepId);

        if (! $step) {
            $this->notifyError(__('journey.step_move_failed'));

            return;
        }

        try {
            app(EnrollmentService::class)->shiftStep($enrollment, $step, $newDueDate);
        } catch (\InvalidArgumentException $e) {
            $messages = [
                'past_date' => __('journey.step_move_past_date'),
                'already_executed' => __('journey.step_move_failed'),
            ];
            $this->notifyError($messages[$e->getMessage()] ?? __('journey.step_move_failed'));

            return;
        }

        $this->notifySuccess(__('journey.step_moved'));
    }

    public function moveJourneyStep(int $enrollmentId, int $stepId, string $date): void
    {
        $enrollment = Enrollment::query()->forUser()->running()->find($enrollmentId);

        if (! $enrollment) {
            $this->dispatch('notify', message: __('journey.step_move_failed'), type: 'error');

            return;
        }

        try {
            $newDueDate = Carbon::createFromFormat('Y-m-d', $date)->startOfDay();
        } catch (\Throwable) {
            $this->dispatch('notify', message: __('journey.step_move_invalid_date'), type: 'error');

            return;
        }

        $step = $enrollment->journey->steps()->find($stepId);

        if (! $step) {
            $this->dispatch('notify', message: __('journey.step_move_failed'), type: 'error');

            return;
        }

        try {
            app(EnrollmentService::class)->shiftStep($enrollment, $step, $newDueDate);
        } catch (\InvalidArgumentException $e) {
            $messages = [
                'past_date' => __('journey.step_move_past_date'),
                'already_executed' => __('journey.step_move_failed'),
            ];
            $this->dispatch('notify', message: $messages[$e->getMessage()] ?? __('journey.step_move_failed'), type: 'error');

            return;
        }

        $this->dispatch('notify', message: __('journey.step_moved'), type: 'success');
    }
}
