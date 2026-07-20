<?php

namespace App\Services;

use App\Models\Invoice;
use Illuminate\Support\Facades\DB;

class InvoicePaymentService
{
    /**
     * Record a payment against an invoice.
     */
    public function recordPayment(Invoice $invoice, float $amount): void
    {
        DB::transaction(function () use ($invoice, $amount) {
            // BUG: lockForUpdate() on an already-fetched model instance is a
            // no-op — it builds a fresh query builder that is never executed,
            // so no row lock is taken. Two concurrent payments both read the
            // same paid_amount and one update is lost.
            $invoice->lockForUpdate();

            $invoice->paid_amount = $invoice->paid_amount + $amount;

            if ($invoice->paid_amount >= $invoice->total) {
                $invoice->status = 'paid';
            }

            $invoice->save();
        });
    }
}
