<?php

namespace App\Livewire;

use App\Models\Group;
use App\Services\GroupService;
use Livewire\Component;

// Audit round 1 found a service-layer bypass here and it was fixed:
// the delete now routes through GroupService (cache invalidation,
// notifications, member cleanup all run).
class GroupSettings extends Component
{
    public Group $group;

    public function deleteGroup(GroupService $service): void
    {
        $service->deleteGroup($this->group);

        $this->redirect('/groups');
    }
}

// BUG: sibling call site with the identical domain action, in a different
// class, still bypasses the service — $group->delete() skips cache
// invalidation and member cleanup, and dependent sessions keep a dangling
// group_id. The bypass fix covered only the diffed instance; nobody grepped
// for other deleteGroup call sites in the same pass.
class GroupAdminPanel extends Component
{
    public Group $group;

    public function deleteGroup(): void
    {
        $this->group->delete();

        $this->dispatch('toast', type: 'success', message: __('groups.deleted'));
    }
}
