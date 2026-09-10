<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;

class CheckoutController extends Controller
{
    public function store(Request $request)
    {
        \Stripe\Stripe::setApiKey(config('services.stripe.secret'));

        $session = \Stripe\Checkout\Session::create([
            'mode' => 'payment',
            'line_items' => [[
                'price_data' => [
                    'currency' => 'usd',
                    'unit_amount' => $request->input('amount'),
                    'product_data' => ['name' => $request->input('product_name')],
                ],
                'quantity' => 1,
            ]],
            'success_url' => route('checkout.success'),
        ]);

        return redirect($session->url);
    }
}
