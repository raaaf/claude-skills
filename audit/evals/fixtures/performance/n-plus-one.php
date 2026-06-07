<?php

namespace App\Http\Controllers;

use App\Models\Order;

class OrderListController
{
    public function index()
    {
        $orders = Order::all();

        $rows = [];
        foreach ($orders as $order) {
            // BUG: $order->customer triggers a query per row -> classic N+1
            $rows[] = [
                'id' => $order->id,
                'customer_name' => $order->customer->name,
                'total' => $order->total,
            ];
        }

        return view('orders.index', ['rows' => $rows]);
    }
}
