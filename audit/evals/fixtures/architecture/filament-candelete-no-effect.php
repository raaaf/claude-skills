<?php

namespace App\Filament\Resources\Invoices;

use App\Models\Invoice;
use Filament\Resources\Resource;

class InvoiceResource extends Resource
{
    protected static ?string $model = Invoice::class;

    // BUG: canDelete() does not gate the Edit-page header DeleteAction in
    // Filament 5. The action stays clickable; paid invoices can be deleted.
    // Guard must live at Action->visible() AND the InvoicePolicy.
    public static function canDelete($record): bool
    {
        return $record->status !== 'paid';
    }
}
