<?php

namespace App\Settings\Sections;

use App\Models\Event;

class LocationPollSection
{
    public function key(): string
    {
        return 'location_poll';
    }

    public function label(): string
    {
        return __('settings.location_poll_label');
    }

    // Still reads the flag Event::hasLocationPoll() checked before it was
    // widened to also accept real poll rows. The settings drawer hides this
    // section for events that have polls but never had the flag flipped,
    // while the host dashboard CTA (built from hasLocationPoll()) still
    // renders and links here, so the host lands on a 404.
    public function isAvailableFor(Event $event): bool
    {
        return $event->location_poll_enabled;
    }
}
