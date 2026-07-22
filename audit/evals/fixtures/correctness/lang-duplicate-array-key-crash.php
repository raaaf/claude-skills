<?php

// Laravel translation file. PHP keeps the LAST value when an array literal
// repeats a key, and says nothing about it: no notice, no warning, and `php -l`
// reports a clean syntax check.
//
// Here 'queue' is declared twice. The string on line 12 is silently discarded,
// so __('admin.queue') returns an array. Every caller that renders it as text
// crashes — but only once a code path actually reaches it, which is why the
// real incident surfaced in the admin failed-jobs view only when failed jobs
// existed.

return [
    'title' => 'Administration',
    'queue' => 'Warteschlange',
    'users' => 'Benutzer',

    'stats' => [
        'total' => 'Gesamt',
        'active' => 'Aktiv',
        // Same key at a DIFFERENT nesting level is fine — not a duplicate.
        'queue' => 'In der Warteschlange',
    ],

    'queue' => [
        'pending' => 'Ausstehend',
        'failed' => 'Fehlgeschlagen',
        'retry' => 'Erneut versuchen',
    ],
];
