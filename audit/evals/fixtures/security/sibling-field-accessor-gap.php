<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Fixture: sibling-field accessor gap (real case 2026-07-14).
 *
 * first_name and name carry a guard that prevents leaking the email local
 * part to other users (accounts created from an email address get their
 * name derived from it). last_name is structurally identical — same source,
 * same exposure — but never received the guard.
 *
 * Expected: security finding on getLastNameAttribute (missing sibling guard).
 */
class User extends Model
{
    public function getFirstNameAttribute(?string $value): ?string
    {
        // Guard: never expose a name derived from the email address.
        if ($value !== null && str_contains($this->email ?? '', strtolower($value))) {
            return null;
        }

        return $value;
    }

    public function getNameAttribute(?string $value): ?string
    {
        if ($value !== null && str_contains($this->email ?? '', strtolower($value))) {
            return null;
        }

        return $value;
    }

    // BUG: same derivation source and exposure as first_name/name, but no
    // email-leak guard — leaks the email local part via last_name.
    public function getLastNameAttribute(?string $value): ?string
    {
        return $value;
    }
}
