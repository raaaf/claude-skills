<?php

namespace Database\Seeders;

use App\Models\Page;
use Illuminate\Database\Seeder;

class PageSeeder extends Seeder
{
    public function run(): void
    {
        $defaults = [
            'hero_title' => 'ein kleiner shop fuer grosse worte',
            'hero_subtitle' => 'handgemachte poster',
            // story_title and story_body were added after the first deploy
            'story_title' => 'unsere geschichte',
            'story_body' => 'angefangen hat alles am kuechentisch.',
        ];

        // BUG: firstOrCreate sets `data` only on first insert. Existing prod rows
        // seeded before story_* existed never receive the new keys, so the admin
        // form renders empty story fields while the frontend masks it with a
        // fallback. Needs a merge step (array_replace_recursive) to backfill
        // missing keys without overwriting admin edits.
        Page::firstOrCreate(
            ['slug' => 'home'],
            ['data' => $defaults],
        );
    }
}
