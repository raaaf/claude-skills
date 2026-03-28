# Externe Dienste — Compliance-Status

| Dienst | Problem | Konforme Alternative |
|--------|---------|---------------------|
| Google Fonts (extern) | IP an Google-Server → Abmahnrisiko | Lokal hosten |
| Google Analytics (ohne Consent) | Tracking ohne Einwilligung | Consent einholen oder Matomo self-hosted |
| Google Maps (ohne Consent) | IP-Übertragung | Zwei-Klick-Lösung oder statisches Bild |
| YouTube-Embed (ohne Consent) | IP-Übertragung | Zwei-Klick-Embed (nocookie reicht nicht) |
| Facebook Pixel | Tracking ohne Einwilligung | Consent einholen |
| Hotjar | Tracking ohne Einwilligung | Consent einholen |
| Hotjar | Session-Recording + Heatmaps ohne Einwilligung | Consent einholen, in DSE aufführen |
| Gravatar (WordPress) | IP an US-Server | Lokal hosten oder deaktivieren |
| jQuery/Bootstrap von CDN | IP-Übertragung | Lokal einbinden |
| Font Awesome von CDN | IP-Übertragung | Lokal oder nur SVG-Icons verwenden |
| Mailchimp-Formular | Drittlandtransfer | AVV + in DSE aufführen |
| reCAPTCHA | IP + Verhaltensdaten an Google | Consent oder Alternative (hCaptcha, Honeypot) |
