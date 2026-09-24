<?php

// FixedClockDateTime.php: /screens server-side fixed clock for Faker (repo
// CLAUDE.md "Isolation and lifecycle", added after stage (b) STOP 3:
// TimeEntryFactory/ExpenditureFactory call Faker's dateTimeBetween(...,
// 'now'), which resolves via PHP's native strtotime(), not Carbon, so
// Carbon::setTestNow() (fixed-clock.php) never reaches it and reseeding
// at a different real minute produced different demo data every run).
//
// Instantiated verbatim into `<project>/.screens/web/php/FixedClockDateTime.php`
// by the Phase 2 scaffold (no project source file changes: neither the
// factories nor fakerphp/faker's vendor code are touched). ScreensDemoSeeder
// requires this file and registers it on the shared Faker generator(s)
// before calling the project's own seeders:
//
//   require_once __DIR__.'/../../.screens/web/php/FixedClockDateTime.php';
//   fake()->addProvider(new FixedClockDateTime(fake()));
//
// Faker's Generator checks providers in reverse-registration order and
// dispatches a called method to the first provider that defines it, so a
// later-registered provider shadows an earlier one's method of the same
// name without editing fakerphp/faker's vendor source.
//
// Overrides only getMaxTimestamp/dateTimeBetween/dateTimeInInterval
// (verified against the installed apps/zeit/app/vendor/fakerphp/faker/src/Faker/Provider/DateTime.php,
// lines 16-26, 146-182): every other method that reads real wall-clock
// time (dateTime, unixTime, dateTimeAD, iso8601, date, time, amPm,
// dayOfMonth, dayOfWeek, month, monthName, year, dateTimeThisMonth/Year/
// Decade/Century) delegates to these three through late static binding
// (Faker calls them on this subclass instance, so `static::` inside the
// inherited method bodies resolves back to this class), so covering the
// three is sufficient without re-implementing the rest.
//
// Inert (falls back to the parent's real-time behavior) unless
// SCREENS_FIXED_NOW is set, so this file is safe to leave registered
// between /screens runs.
class FixedClockDateTime extends \Faker\Provider\DateTime
{
    /**
     * The fixed instant (as a Unix timestamp) to resolve every relative
     * date string against, or null when SCREENS_FIXED_NOW is unset (the
     * provider is then fully inert). Reads Carbon::now() rather than the
     * env var directly so this always agrees with fixed-clock.php's
     * Carbon::setTestNow() call, the single source of truth for the fixed
     * instant.
     */
    private static function fixedBaseTimestamp(): ?int
    {
        $fixedNow = getenv('SCREENS_FIXED_NOW');
        if ($fixedNow === false || $fixedNow === '') {
            return null;
        }

        return \Carbon\Carbon::now()->getTimestamp();
    }

    /**
     * Mirrors the parent's getMaxTimestamp, except a relative/"now" string
     * resolves against the fixed instant (strtotime's second argument)
     * instead of real wall-clock time.
     */
    protected static function getMaxTimestamp($max = 'now')
    {
        $base = self::fixedBaseTimestamp();
        if ($base === null) {
            return parent::getMaxTimestamp($max);
        }

        if (is_numeric($max)) {
            return (int) $max;
        }

        if ($max instanceof \DateTime) {
            return $max->getTimestamp();
        }

        return strtotime(empty($max) ? 'now' : $max, $base);
    }

    /**
     * Mirrors the parent's dateTimeBetween, except a relative $startDate
     * string (e.g. "-1 month") resolves against the fixed instant instead
     * of real wall-clock time; $endDate goes through the overridden
     * getMaxTimestamp above.
     */
    public static function dateTimeBetween($startDate = '-30 years', $endDate = 'now', $timezone = null)
    {
        $base = self::fixedBaseTimestamp();
        if ($base === null) {
            return parent::dateTimeBetween($startDate, $endDate, $timezone);
        }

        $startTimestamp = $startDate instanceof \DateTime
            ? $startDate->getTimestamp()
            : strtotime($startDate, $base);
        $endTimestamp = static::getMaxTimestamp($endDate);

        if ($startTimestamp > $endTimestamp) {
            throw new \InvalidArgumentException('Start date must be anterior to end date.');
        }

        $timestamp = self::numberBetween($startTimestamp, $endTimestamp);

        return self::applyTimezone(new \DateTime('@'.$timestamp), $timezone);
    }

    /**
     * Mirrors the parent's dateTimeInInterval, except a relative $date
     * string resolves against the fixed instant instead of real
     * wall-clock time.
     */
    public static function dateTimeInInterval($date = '-30 years', $interval = '+5 days', $timezone = null)
    {
        $base = self::fixedBaseTimestamp();
        if ($base === null) {
            return parent::dateTimeInInterval($date, $interval, $timezone);
        }

        $datetime = $date instanceof \DateTime ? $date : new \DateTime('@'.strtotime($date, $base));
        $intervalObject = \DateInterval::createFromDateString($interval);
        $otherDatetime = clone $datetime;
        $otherDatetime->add($intervalObject);

        $begin = min($datetime, $otherDatetime);
        $end = $datetime === $begin ? $otherDatetime : $datetime;

        return static::dateTimeBetween($begin, $end, $timezone);
    }

    /**
     * `DateTime::setTimezone`/`resolveTimezone` are private in the parent
     * class (not accessible from a subclass), so this replicates their
     * behavior via the parent's public getDefaultTimezone() accessor
     * instead of reaching into private parent state.
     */
    private static function applyTimezone(\DateTime $dt, $timezone)
    {
        $resolved = $timezone ?? (static::getDefaultTimezone() ?: date_default_timezone_get());

        return $dt->setTimezone(new \DateTimeZone($resolved));
    }
}
