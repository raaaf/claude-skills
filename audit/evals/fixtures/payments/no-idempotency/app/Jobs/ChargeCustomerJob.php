<?php

namespace App\Jobs;

use App\Models\Order;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;

class ChargeCustomerJob implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    public $tries = 3;

    public function __construct(private Order $order)
    {
    }

    public function handle(): void
    {
        \Stripe\Stripe::setApiKey(config('services.stripe.secret'));

        \Stripe\PaymentIntent::create([
            'amount' => $this->order->total_cents,
            'currency' => 'usd',
            'customer' => $this->order->stripe_customer_id,
            'confirm' => true,
        ]);

        $this->order->update(['status' => 'charged']);
    }
}
