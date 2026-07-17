<?php

namespace App\Http\Middleware;

use App\Models\Guest;
use Closure;
use Illuminate\Http\Request;

/**
 * False-positive regression fixture: "plaintext token storage".
 *
 * The token is hashed once near the top of handle(); the session write near
 * the bottom stores that HASHED value. An auditor that only reads the write
 * line flags plaintext storage — that is the 2026-07-09 false positive
 * (pending_guest_token, ResolveEventAccess.php:153/208 hash, :227 write).
 * Expected: NO security finding.
 */
class ResolvePendingGuestToken
{
    public function handle(Request $request, Closure $next)
    {
        $token = (string) $request->query('guest_token', '');

        if ($token === '') {
            return $next($request);
        }

        // Source of truth: the token is hashed exactly once, here.
        $hashedToken = hash('sha256', $token);

        $guest = Guest::where('token_hash', $hashedToken)->first();

        if (! $guest) {
            return $next($request);
        }

        if ($guest->event === null || $guest->event->isReadOnly()) {
            return $next($request);
        }

        if ($guest->trashed()) {
            return $next($request);
        }

        // In the real file this write sits ~70 lines below the hash() call.
        // Read in isolation it looks like a plaintext token being persisted.
        session()->put('pending_guest_token', $hashedToken);

        $request->attributes->set('guest', $guest);

        return $next($request);
    }
}
