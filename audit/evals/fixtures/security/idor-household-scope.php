<?php

namespace App\Http\Controllers;

use App\Models\Transaction;
use Illuminate\Http\Request;

class TransactionController
{
    public function applyCategories(Request $request)
    {
        $validated = $request->validate([
            'assignments' => ['required', 'array'],
            'assignments.*.transaction_id' => ['required', 'integer'],
            'assignments.*.category_id' => ['required', 'integer'],
        ]);

        foreach ($validated['assignments'] as $assignment) {
            // Transaction is household-scoped via a global scope, so findOrFail
            // already rejects other households' transactions.
            $transaction = Transaction::findOrFail($assignment['transaction_id']);

            // BUG: category_id comes straight from the request payload with no
            // check that it belongs to the current household -> IDOR. A user
            // can assign another household's category id to their own
            // transaction by guessing/enumerating ids.
            $transaction->update(['category_id' => $assignment['category_id']]);
        }

        return back();
    }
}
