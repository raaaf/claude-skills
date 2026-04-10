# Agent: Externe Dienste

- **subagent_type:** `general-purpose`
- **model:** `haiku`
- **maxTurns:** `5`

## Aufgabe

Prüfe jeden erkannten externen Dienst auf DSGVO-Konformität. Das sind die häufigsten Abmahnfallen.

Lies `references/externe-dienste.md` für Details.

## Eingabe

Du erhältst:
- `GEFUNDENE_DIENSTE` — Liste erkannter externer Ressourcen/Dienste
- `COOKIE_BANNER_VORHANDEN` — ja/nein
- `HTML_SNIPPET` — HTML inkl. Script-Tags und externen Ressourcen
- `FRAMEWORK` — Projekttyp

## Was du für jeden Dienst prüfst

Gehe jeden erkannten Dienst durch und bewerte ihn:

### Google Fonts

- Lädt von `fonts.googleapis.com` oder `fonts.gstatic.com`?
  → **Kritisch** — IP-Übertragung ohne Einwilligung. Seit LG München I (2022) bekannte Abmahngrundlage.
  → Fix: Fonts lokal einbinden. Google Fonts hat einen "Download"-Button für alle Font-Familien.

- Lädt von eigenem Server (`/fonts/`, `public/fonts/`, etc.)?
  → Sauber.

### Google Analytics / GTM

- Im `<head>` ohne Consent-Wrapper?
  → **Kritisch** — Tracking ohne Einwilligung.
  → Fix: Script hinter Consent-Check verschieben. GTM erst nach Einwilligung initialisieren.

- Mit funktionierendem Consent-Check?
  → Wichtig prüfen ob IP-Anonymisierung aktiv: `anonymize_ip: true` (UA) bzw. in GA4 in den Einstellungen.

### Google Maps

- Lädt beim Seitenaufruf (iframe oder API)?
  → **Kritisch** — IP-Übertragung ohne Einwilligung.
  → Fix: Zwei-Klick-Lösung — statisches Kartenbild zeigen, erst nach Klick Maps laden. Oder: OpenStreetMap als Alternative.

### YouTube-Embeds

- Lädt `youtube.com/embed/` direkt?
  → **Kritisch** — IP-Übertragung auch ohne Abspielen.
  → Fix: Zwei-Klick-Embed (Vorschaubild, erst nach Klick laden). `youtube-nocookie.com` reicht nicht.

### Facebook Pixel / Meta Pixel

- Im `<head>` ohne Consent?
  → **Kritisch** — Tracking ohne Einwilligung.
  → Fix: Hinter Consent-Check verschieben.

### Hotjar

- Ohne Consent?
  → **Kritisch** — Session-Recording ohne Einwilligung.
  → Fix: Hinter Consent-Check verschieben.

### Externe CDNs (jQuery, Bootstrap, Font Awesome etc.)

- Von `cdnjs.cloudflare.com`, `jsdelivr.net`, `unpkg.com`, `stackpath.bootstrapcdn.com`, `maxcdn.bootstrapcdn.com`?
  → **Wichtig** — IP-Übertragung an CDN-Provider.
  → Fix: Lokal einbinden. Einmalig herunterladen, in `/public` oder `/assets` ablegen.

### reCAPTCHA

- Im Formular ohne Consent?
  → **Wichtig** — Google erhält Verhaltens- und IP-Daten.
  → Fix: Consent einholen, oder Alternative nutzen (hCaptcha, Honeypot-Methode, Turnstile von Cloudflare).

### Mailchimp / HubSpot / Newsletter-Embeds

- Formular eingebettet?
  → **Wichtig** — Datenübertragung an US-Dienst, AVV nötig.
  → In DSE aufführen, AVV abschließen, Drittlandtransfer erwähnen.

### WordPress-spezifisch

- Gravatar (Kommentare): IP geht an Automattic/US-Server
  → **Wichtig** — Gravatar deaktivieren oder lokal hosten.
  → Fix: `remove_filter('get_avatar', ...)` oder in WordPress-Einstellungen Avatare deaktivieren.

- WordPress-Emojis: laden von `twemoji.maxcdn.com`
  → **Wichtig** — Externe Ressource.
  → Fix in `functions.php`:
  ```php
  remove_action('wp_head', 'print_emoji_detection_script', 7);
  remove_action('wp_print_styles', 'print_emoji_styles');
  ```

## Output

Für jeden gefundenen Dienst ein Finding oder Sauber-Vermerk. Format:

```
[{Dienst}] {Problem} — {Konkreter Fix}
Schwere: Kritisch / Wichtig / Nice-to-have
```

Nur erkannte Dienste ausgeben — keine hypothetischen Findings für Dienste die nicht gefunden wurden.

Wenn keine problematischen externen Dienste erkannt: `Externe Dienste: Keine Findings.`
