# Cookie-Consent

**Pflicht:**
- Banner erscheint VOR dem Setzen nicht-essentieller Cookies
- "Ablehnen" genauso prominent wie "Akzeptieren" — kein Dark Pattern
- Scripts laden technisch ERST nach Einwilligung (nicht nur Cookie gesetzt)
- Consent widerrufbar (Link "Cookie-Einstellungen" im Footer)
- Einwilligung für jeden Zweck separat (Analytics ≠ Marketing ≠ Funktional)

**Essentiell (kein Consent nötig):**
- Session-Cookie, Login-Cookie, Warenkorb, CSRF-Token, Load-Balancing

**Nicht-essentiell (Consent nötig):**
- Analytics (Google Analytics, Matomo mit Tracking), Hotjar, Facebook Pixel
- Marketing/Retargeting
- Personalisierung

**Impressum + Datenschutz:**
- Müssen ohne Interaktion mit dem Banner erreichbar sein
- Entweder: Links im Banner selbst, oder: Banner lässt Footer sichtbar/scrollbar
