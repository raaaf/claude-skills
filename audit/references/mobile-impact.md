# Mobile-App Impact-Matrix

Nur relevant wenn `bin/detect-mobile.sh` eine Mobile-App im Repo erkennt.

| Änderung | Mobile-Relevanz | Einstufung |
|----------|-----------------|------------|
| API-Endpunkte geändert/entfernt | Breaking Change — App muss aktualisiert werden | Important |
| API-Response-Format geändert | Breaking Change — App-Parsing bricht | Important |
| Neue API-Felder hinzugefügt | Kein Breaking Change, aber App nutzt sie nicht ohne Update | Minor |
| Auth-Flow geändert | Breaking Change — Login in App bricht | Important |
| Push-Notification-Payload geändert | App empfängt falsche Daten | Important |
| Deep-Link-Routen geändert | App-Navigation bricht | Important |
| Shared Code geändert (Monorepo) | Direkt betroffen — prüfe ob App-Build noch funktioniert | Important |
| Nur Frontend/Web geändert | Keine Mobile-Auswirkung (außer WebView/Capacitor) | — |

Findings als **Important** einstufen wenn Breaking Changes erkannt werden, als **Minor** wenn nur neue Felder/Endpunkte hinzukommen.
