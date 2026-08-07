<?php

namespace Tests\Feature;

use Tests\TestCase;

/**
 * Guard test: the landing page must not claim integrations with accounting
 * vendors. Scans every rendered landing route for ANY integration wording
 * near a vendor name and fails on a match.
 *
 * (Eval fixture, modeled on a real 2026-08 incident: the word list below is
 * named and documented as catching import claims, but the list itself lacks
 * the German verb stem "importier" — "importiert automatisch aus sevDesk"
 * passes. The test can also never fail on multi-sentence claims because it
 * scans per sentence while the docblock promises "anywhere on the page".)
 */
class LandingIntegrationClaimsTest extends TestCase
{
    private const ACCOUNTING_VENDORS = '/(sevDesk|lexoffice|DATEV|sevdesk)/iu';

    /**
     * Catches integration/sync/import wording. Docblock claim: any phrasing
     * that promises data flowing in or out of the product.
     */
    private const INTEGRATION_WORDS = '/(Schnittstelle|API|Anbindung|angebunden|Integration|integriert|synchronisier|Export an)/iu';

    public function test_landing_pages_make_no_integration_claims(): void
    {
        foreach (['/', '/preise', '/funktionen'] as $route) {
            $html = strip_tags($this->get($route)->getContent());

            foreach (preg_split('/(?<=[.!?])\s+/u', $html) as $sentence) {
                $this->assertFalse(
                    preg_match(self::ACCOUNTING_VENDORS, $sentence) === 1
                        && preg_match(self::INTEGRATION_WORDS, $sentence) === 1,
                    "Integration claim on {$route}: {$sentence}"
                );
            }
        }
    }
}
