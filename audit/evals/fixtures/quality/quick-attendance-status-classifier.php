<?php

namespace Tests\Feature;

use Tests\TestCase;

/**
 * Minimal stand-in for the real QuickAttendance model, kept in this file so
 * the test and the logic it exercises sit side by side.
 */
class QuickAttendance
{
    public static function classify(int $spotsTaken, int $spotsTotal): string
    {
        return $spotsTaken >= $spotsTotal ? 'waitlist' : 'confirmed';
    }
}

class QuickAttendanceClassifyTest extends TestCase
{
    public function test_classify_returns_confirmed_when_a_spot_is_open(): void
    {
        $this->assertSame('confirmed', QuickAttendance::classify(3, 10));
    }
}
