# Live Audit Thresholds

Fingerprint-IDs sind deterministisch und enthalten keinen Messwert. Der Messwert kommt in den Issue-Body.

## PSI — Mobile (primär)

| Fingerprint-ID | Metrik | Important | Critical |
|---|---|---|---|
| `lcp-slow` | Largest Contentful Paint | > 2.5s | > 4.0s |
| `cls-high` | Cumulative Layout Shift | > 0.10 | > 0.25 |
| `fcp-slow` | First Contentful Paint | > 1.8s | — |
| `perf-score-low` | Performance Score | < 80 | < 50 |
| `seo-score-low` | SEO Score | < 90 (Minor) | — |
| `a11y-score-low` | Accessibility Score | < 90 | < 70 |

## PSI — Desktop (sekundär, nur Performance Score)

| Fingerprint-ID | Metrik | Important | Critical |
|---|---|---|---|
| `perf-score-low-desktop` | Performance Score Desktop | < 80 | < 50 |

## SSL

| Fingerprint-ID | Bedingung | Severity |
|---|---|---|
| `ssl-expiring` | Zertifikat läuft in < 14 Tagen ab | Important |
| `ssl-expired` | Zertifikat abgelaufen | Critical |

## Site-Erreichbarkeit

| Fingerprint-ID | Bedingung | Severity |
|---|---|---|
| `site-unreachable` | HTTP-Fehler oder Timeout bei WebFetch | Critical |

## Rollout-Filter (aus state.json)

| rollout_week | Welche Severities werden als Issues erstellt |
|---|---|
| 1 | Critical only |
| 2-3 | Critical + Important |
| 4+ | Critical + Important + Minor |

## Toleranz-Band

Ein Finding wird erst nach **2 aufeinanderfolgenden Runs** als Issue erstellt.

- Run N: Finding erscheint → in `pending_findings` eintragen
- Run N+1: Finding erscheint wieder → Issue erstellen
- Run N+1: Finding erscheint nicht mehr → aus `pending_findings` entfernen

Ausnahme: `site-unreachable` und `ssl-expired` werden sofort (ohne Toleranz-Band) als Issue erstellt.

## Suppression-Logik

Issues mit Label `suppress` → `fingerprint` in `suppressions.json` eintragen. Diese Findings werden in zukünftigen Runs übersprungen, auch wenn sie den Threshold überschreiten.

Suppression-Eintrag-Format:
```json
{
  "fingerprint": "site|metric-id",
  "reason": "Bewusst akzeptiert",
  "added": "YYYY-MM-DD",
  "issue": "#42"
}
```
