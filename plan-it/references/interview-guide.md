# Phase 1 Interview Guide (Detail)

Detail fuer Phase 1 (Verstehen). Wird vom Orchestrator gelesen wenn die Einschaetzung schwierig ist.

## Schritt B: Codebase-Scan-Tabelle

Was scannen, abhaengig vom Thema:

| Thema | Scan-Aktion |
|---|---|
| Daten-Umbau / Schema-Migration | Grep alle Schreib- und Lesestellen des Felds, pruefe Cache-Layer, Trait-Mixins |
| Multi-Kanal / Multi-Service | `ls` der Channel-/Service-Klassen, Reliability-Status (deprecated? in Tests?), Monitoring-Stellen |
| Neues Feature | Grep nach aehnlichen Features (Naming-Suche), bestehende Patterns fuer Lifecycle/Permission/UI |
| Refactoring / Umbenennung | Aufrufer-Liste mit Grep, Test-Coverage pruefen, Doku-Erwaehnungen |
| Performance / Caching | Bestehende Cache-Keys finden, Invalidation-Pattern, N+1-Hotspots |

**Ausgabe-Format:** Kurze Codebase-Map (3-8 Bulletpoints) als Faktenbasis vor den Fragen:

```
Vor den Fragen — Codebase-Stand:
- {Fakt 1, z.B. "Push-Channels: APNs, FCM, NativePushChannel — letzterer ist die einzige aktive Implementation"}
- {Fakt 2}
- {Fakt 3}
```

## Fragen-Format mit Eigener Einschaetzung

Nicht nur fragen — direkt die beste Antwort auf Basis von Codebase, Kontext, typischen Patterns vorschlagen. User korrigiert oder bestaetigt nur.

```
{Frage}
→ Meine Einschaetzung: {konkrete Annahme/Empfehlung, begruendet in 1 Satz}
```

Beispiele:
- "Wer ist der User hier? → Meine Einschaetzung: Admin — weil die Route hinter Auth liegt und kein Onboarding-Flow existiert."
- "Wie soll mit Fehlern umgegangen werden? → Meine Einschaetzung: Toast-Notification, da das der bestehende Pattern in der App ist."
- "Brauchen wir eine Migration? → Meine Einschaetzung: Nein — das neue Feld ist optional und hat einen Default."

## Abhaengigkeiten erkennen

Bevor du eine Frage stellst, pruefe:
- Haengt die Antwort von einer noch offenen Entscheidung ab? → Erst die Abhaengigkeit klaeren.
- Oeffnet die Antwort einen neuen Ast? → Nach der Antwort sofort dort weiterfragen.
- Sind mehrere Fragen unabhaengig voneinander? → Dann in derselben Runde stellen.

Beispiel-Baum:
```
Wer ist der User? (blockiert alles)
├── Admin → Welche Berechtigungen? → Braucht es Audit-Logging?
├── Endnutzer → Onboarding noetig? → Welcher Flow?
└── Beide → Rollenbasierte Views? → Shared Components oder getrennt?
```

## Tonfall

Der Skill redet wie ein kluger Kollege:

Gut: "Mir faellt auf dass der Plan keine Fehlerbehandlung fuer X hat. Was passiert wenn Y schiefgeht?"
Schlecht: "Re-grounding context: The user's plan lacks error handling. Completeness: 3/10."

Gut: "Das klingt nach einem simplen Feature-Flag statt dem ganzen Umbau. Was spricht dagegen?"
Schlecht: "Alternative approach detected. Please evaluate tradeoffs."

Gut: "Wer ist eigentlich der User hier? Admin oder Endnutzer? Das aendert den ganzen Ansatz."
Schlecht: "Target user persona not specified. Please select: A) Admin B) End user C) Both."
