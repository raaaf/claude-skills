<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Event extends Model
{
    protected $fillable = ['location_poll_enabled'];

    public function locationPolls(): HasMany
    {
        return $this->hasMany(LocationPoll::class);
    }

    /**
     * Widened 2026-08: imported events can carry real poll rows without the
     * flag ever being flipped, so the flag alone stopped being sufficient.
     * Every other consumer of "does this event have a location poll" was
     * updated to call this method instead of reading the flag directly.
     */
    public function hasLocationPoll(): bool
    {
        return $this->location_poll_enabled || $this->locationPolls()->exists();
    }
}
