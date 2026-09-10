<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;

class AddonPurchaseController extends Controller
{
    public function store(Request $request)
    {
        $user = $request->user();

        \Stripe\Stripe::setApiKey(config('services.stripe.secret'));

        \Stripe\PaymentIntent::create([
            'amount' => 500,
            'currency' => 'usd',
            'customer' => $user->stripe_id,
            'description' => 'Extra export credits',
            'confirm' => true,
        ]);

        $user->increment('export_credits', 10);

        return response()->json(['status' => 'ok']);
    }
}
