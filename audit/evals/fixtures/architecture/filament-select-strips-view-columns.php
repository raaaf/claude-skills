<?php

namespace App\Filament\Resources\Subscriptions;

use App\Models\Subscription;
use Filament\Resources\Resource;
use Illuminate\Database\Eloquent\Builder;

class SubscriptionResource extends Resource
{
    protected static ?string $model = Subscription::class;

    // BUG: this select() list feeds both the table AND the record used by
    // ViewSubscription's infolist and the acceptance-letter PDF. It was
    // written for the table columns only and drops personal_data and
    // depot_data (used by the sensitive-data infolist section) and the
    // related product's bond_terms (used by the acceptance letter). Rows
    // hydrated through this scope render the infolist section as dashes and
    // the PDF prints "[...]" instead of the bond terms, with no error.
    public static function getEloquentQuery(): Builder
    {
        return parent::getEloquentQuery()
            ->select([
                'id',
                'reference_number',
                'state',
                'amount',
                'product_id',
                'created_at',
            ])
            ->with(['product:id,name']);
    }
}
