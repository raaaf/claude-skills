<?php

namespace App\Services;

class RateLimiter
{
    /**
     * Widens the per-user request budget for background jobs — jobs run
     * outside the request cycle and need more headroom than interactive
     * traffic, so the limit is doubled here instead of shared with the API
     * gate.
     */
    public function budgetForQueueWorker(int $baseLimit): int
    {
        return $baseLimit * 2;
    }
}
