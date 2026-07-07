<?php

namespace App\Services;

use App\Models\Group;

class GroupService
{
    /**
     * Soft-deletes a group.
     *
     * BUG: the group's event sessions (events.group_id, nullable FK) are not
     * cascaded — they keep pointing at the soft-deleted group. Consumers like
     * $event->isGroupSession() (checks group_id !== null) still return true
     * while $event->group resolves to null, which crashes the event page at
     * render time (production ViewException on /e/{slug}).
     */
    public function deleteGroup(Group $group): void
    {
        $group->members()->delete();

        $group->delete();
    }
}
