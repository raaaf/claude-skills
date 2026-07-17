<?php

namespace App\Livewire;

use App\Models\Enrollment;
use App\Services\EnrollmentService;
use Livewire\Component;

/**
 * Eval fixture: identical guard/resolver BLOCK duplicated inside two
 * otherwise DIFFERENT method bodies of the same diff. Whole-method body
 * comparison does not fire (the methods do different things), and no
 * shared method name exists to grep for. The audit must flag the
 * duplicated resolver block (extract into a private resolver), not the
 * methods as a whole. Discovered as a gap 2026-07 (learning log): this
 * shape escaped both the method-body grep and the generalized self-check.
 */
class EnrollmentActions extends Component
{
    public function reschedule(int $enrollmentId, string $date): void
    {
        // --- duplicated resolver block, copy 1 ---
        $enrollment = Enrollment::query()
            ->forUser()
            ->whereIn('status', ['running', 'paused'])
            ->find($enrollmentId);

        if (! $enrollment) {
            $this->dispatch('notify', message: __('enrollment.not_found'), type: 'error');

            return;
        }

        if ($enrollment->customer->opted_out) {
            $this->dispatch('notify', message: __('enrollment.opted_out'), type: 'error');

            return;
        }
        // --- end duplicated block ---

        $shifted = app(EnrollmentService::class)->shiftAnchor($enrollment, $date);

        $this->dispatch('notify', message: trans_choice('enrollment.shifted', $shifted, ['count' => $shifted]), type: 'success');
    }

    public function escalate(int $enrollmentId, string $reason): void
    {
        // --- duplicated resolver block, copy 2 (identical statement sequence) ---
        $enrollment = Enrollment::query()
            ->forUser()
            ->whereIn('status', ['running', 'paused'])
            ->find($enrollmentId);

        if (! $enrollment) {
            $this->dispatch('notify', message: __('enrollment.not_found'), type: 'error');

            return;
        }

        if ($enrollment->customer->opted_out) {
            $this->dispatch('notify', message: __('enrollment.opted_out'), type: 'error');

            return;
        }
        // --- end duplicated block ---

        $task = app(EnrollmentService::class)->createEscalationTask($enrollment, $reason);
        $enrollment->update(['escalated_at' => now(), 'escalation_task_id' => $task->id]);

        $this->dispatch('notify', message: __('enrollment.escalated'), type: 'success');
    }
}
