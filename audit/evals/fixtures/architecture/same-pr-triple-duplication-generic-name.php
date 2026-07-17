<?php

namespace App\Livewire;

use App\Models\Report;
use App\Services\ReportExportService;
use Illuminate\Support\Carbon;
use Livewire\Component;

/**
 * Eval fixture: THREE near-identical methods introduced in the SAME diff,
 * with generic names that do not appear in any earlier fixture or learning
 * log. Proves the fix-agent self-check generalizes structurally (same
 * parse/lookup/error-mapping sequence) instead of pattern-matching known
 * method names like moveStep. The audit must flag the triple duplication
 * (extract or delegate), not just each method in isolation.
 */
class ReportPanel extends Component
{
    public function queueWeeklyExport(int $reportId, string $date): void
    {
        $report = Report::query()->forUser()->published()->find($reportId);

        if (! $report) {
            $this->notifyError(__('reports.export_failed'));

            return;
        }

        try {
            $rangeStart = Carbon::createFromFormat('Y-m-d', $date)->startOfWeek();
        } catch (\Throwable) {
            $this->notifyError(__('reports.export_invalid_date'));

            return;
        }

        try {
            app(ReportExportService::class)->queue($report, $rangeStart, 'weekly');
        } catch (\InvalidArgumentException $e) {
            $messages = [
                'range_too_large' => __('reports.export_range_too_large'),
                'already_queued' => __('reports.export_failed'),
            ];
            $this->notifyError($messages[$e->getMessage()] ?? __('reports.export_failed'));

            return;
        }

        $this->notifySuccess(__('reports.export_queued'));
    }

    public function queueMonthlyExport(int $reportId, string $date): void
    {
        $report = Report::query()->forUser()->published()->find($reportId);

        if (! $report) {
            $this->notifyError(__('reports.export_failed'));

            return;
        }

        try {
            $rangeStart = Carbon::createFromFormat('Y-m-d', $date)->startOfMonth();
        } catch (\Throwable) {
            $this->notifyError(__('reports.export_invalid_date'));

            return;
        }

        try {
            app(ReportExportService::class)->queue($report, $rangeStart, 'monthly');
        } catch (\InvalidArgumentException $e) {
            $messages = [
                'range_too_large' => __('reports.export_range_too_large'),
                'already_queued' => __('reports.export_failed'),
            ];
            $this->notifyError($messages[$e->getMessage()] ?? __('reports.export_failed'));

            return;
        }

        $this->notifySuccess(__('reports.export_queued'));
    }

    public function queueQuarterExport(int $reportId, string $date): void
    {
        $report = Report::query()->forUser()->published()->find($reportId);

        if (! $report) {
            $this->dispatch('notify', message: __('reports.export_failed'), type: 'error');

            return;
        }

        try {
            $rangeStart = Carbon::createFromFormat('Y-m-d', $date)->startOfQuarter();
        } catch (\Throwable) {
            $this->dispatch('notify', message: __('reports.export_invalid_date'), type: 'error');

            return;
        }

        try {
            app(ReportExportService::class)->queue($report, $rangeStart, 'quarterly');
        } catch (\InvalidArgumentException $e) {
            $messages = [
                'range_too_large' => __('reports.export_range_too_large'),
                'already_queued' => __('reports.export_failed'),
            ];
            $this->dispatch('notify', message: $messages[$e->getMessage()] ?? __('reports.export_failed'), type: 'error');

            return;
        }

        $this->dispatch('notify', message: __('reports.export_queued'), type: 'success');
    }
}
