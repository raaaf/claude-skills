<?php

namespace App\Http\Controllers;

use App\Models\User;
use Illuminate\Http\Request;

class StripeWebhookController extends Controller
{
    public function handle(Request $request)
    {
        $payload = json_decode($request->getContent(), true);

        if ($payload['type'] === 'checkout.session.completed') {
            $userId = $payload['data']['object']['client_reference_id'];
            $user = User::findOrFail($userId);
            $user->update(['plan' => 'pro', 'entitled_until' => now()->addYear()]);
        }

        return response()->json(['received' => true]);
    }
}
