---
name: produktvideo
description: "Erstellt ein KI-Lifestyle-Video eines punktundpause Produkts (Statement-Poster) in einem realistischen Wohnraum via Runway Gen-4. Zwei-Schritt: Poster per gen4_image als Reference in den Raum rendern, dann mit Kamerafahrt animieren. Loopbar (Boomerang) und web-optimiert (HandBrake). - /produktvideo, produktvideo erstellen, lifestyle video, runway, poster in wohnraum"
argument-hint: "[pfad/zur/produktbild.jpg]"
model: sonnet
effort: medium
allowed-tools:
  - Bash
  - AskUserQuestion
  - Read
---

# Produktvideo: Statement-Poster in Wohnraum (Runway Gen-4)

Erstelle ein kurzes Lifestyle-Video eines punktundpause Statement-Posters in einem realistischen Wohnraum. Ergebnis ist nahtlos loopbar und web-optimiert.

## Architektur: zwei Schritte (wichtig)

NICHT das flache Poster direkt als Startframe animieren. Sobald die Kamera zurueck- oder seitwaerts faehrt, ersetzt Runway das Posterdesign durch ein generisches Motiv (z.B. Sonnenuntergang) und es entsteht ein "Intro"-Morph plus Rahmenglitch. Stattdessen:

1. **gen4_image** (`/v1/text_to_image`): Poster als `referenceImages` mit Tag in einen Raum rendern. Das Design bleibt exakt erhalten, weil das Poster ein kleines, fixes Wandelement ist.
2. **gen4_turbo** (`/v1/image_to_video`): dieses Standbild mit Kamerafahrt animieren. Bild definiert die Szene, Prompt beschreibt NUR die Bewegung.

Danach Boomerang-Loop (ffmpeg) und Web-Optimierung (HandBrake).

Kosten ca. 0,33 USD pro Video (0,08 Bild + 0,25 Video).

## Prompt-Regeln (Runway Gen-4, aus Praxis + Docs)

- KEINE Negativ-Prompts. Gen-4 ignoriert "no X" oder macht das Gegenteil. Alles positiv formulieren.
- Bei image_to_video: Szene NICHT wiederholen (steht im Bild), nur Kamera/Bewegung beschreiben.
- Fuer Loops: ruhige, minimale Bewegung. Phrase `Continuous seamless shot.` voranstellen.

## Ablauf

### 1. API-Key pruefen

```bash
echo "${RUNWAY_API_SECRET:0:6}..."
```

Falls leer: Abbrechen mit klarer Fehlermeldung:
> `RUNWAY_API_SECRET` ist nicht gesetzt. Bitte als Umgebungsvariable exportieren: `export RUNWAY_API_SECRET=...`

### 2. Bilddatei ermitteln

Falls `$ARGUMENTS` nicht leer ist (`/produktvideo pfad/zum/bild.jpg`): diesen Pfad nutzen. Sonst per `AskUserQuestion` nach dem absoluten Pfad fragen (Freitext/Other). Datei per `Read` pruefen.

Unterstuetzte Formate: JPEG, PNG, WebP.

### 3. Raumstil waehlen

Per `AskUserQuestion`, Frage "Welcher Raumstil?" (single):

- `skandinavisch-hell` — Helles Holz, weisse Waende, Morgenlicht, klare Linien
- `warm-boho` — Warme Erdtoene, Rattan, Textilien, weiches Abendlicht, Pflanzen
- `urban-modern` — Dunkle Akzente, Beton-Optik, gerichtetes Licht, Geometrie
- `ueberrasch mich` → passend zur Posterfarbe waehlen (warm → warm-boho, hell/luftig → skandinavisch-hell, dunkel/kontrastreich → urban-modern)

### 4. Web-Optimierung abfragen

Per `AskUserQuestion`, Frage "Video nach der Generierung mit HandBrake fuers Web optimieren?" (single):
- `ja` — zusaetzliche `_web.mp4`, faststart, RF23, volles Seitenverhaeltnis (empfohlen)
- `nein` — nur Roh-Loop behalten

### 5. Poster vorbereiten (Rand trimmen + skalieren)

Weisser Posterrand verursacht Rahmenglitches, deshalb wegtrimmen. Skalieren gegen das Runway-Limit (Data-URI < 5242880 Base64-Zeichen). `sips` reicht nicht zum Trimmen, dafuer ImageMagick:

```bash
PREP="/tmp/runway_poster_prep.jpg"
magick "$BILDPFAD" -fuzz 8% -trim +repage -resize "x1280>" -quality 82 "$PREP"
echo "Base64-Laenge: $(base64 -i "$PREP" | tr -d '\n' | wc -c)  (Limit 5242880)"
```

### 5b. Kosten bestaetigen (Pflicht, vor dem ersten bezahlten Call)

Schritt 6 (gen4_image, Standbild) und Schritt 7 (gen4_turbo, Video) kosten beide echtes Geld, zusammen ca. 0,33 USD pro Video (0,08 Bild + 0,25 Video, siehe oben). Mit dieser Bestaetigung committet sich der User auf den ganzen Lauf, nicht nur auf einen Schritt. Bevor Schritt 6 laeuft, per `AskUserQuestion` bestaetigen lassen, Summe genannt (z.B. "Standbild ~0,08 USD + Video ~0,25 USD = ~0,33 USD gesamt"). Optionen: "Ja, generieren (~0,33 USD)" und "Abbrechen". Nur bei Ja weiter zu Schritt 6; bei Abbrechen hier stoppen, es wird nichts abgerechnet. Diese Bestaetigung nie ueberspringen, auch wenn der Skill automatisch ausgeloest wurde. Ersetzt NICHT die Standbild-Bestaetigung in Schritt 6 (dort geht es um Design/Raum, nicht ums Geld — die verhindert nur, dass der teure Video-Schritt auf einem falschen Standbild aufbaut).

### 6. Schritt 1 — Poster in den Raum rendern (gen4_image)

Raum-Beschreibung je Stil (positiv, kein "no ..."):

`skandinavisch-hell`:
> hanging on the wall of a bright Scandinavian living room, white walls, light oak furniture, a cozy armchair, morning light through large windows, clean and airy

`warm-boho`:
> hanging on the wall of a warm bohemian living room, terracotta and cream tones, a rattan armchair, hanging plants, woven textiles, soft warm evening light from a side window

`urban-modern`:
> hanging on the wall of a modern urban living room, dark accent wall, concrete textures, minimal geometric furniture, directional pendant lighting, sophisticated mood

```bash
PREP="/tmp/runway_poster_prep.jpg"
BASE64=$(base64 -i "$PREP" | tr -d '\n')
DATA_URI="data:image/jpeg;base64,${BASE64}"
PROMPT="@poster as a framed art print in a thin frame [RAUM-BESCHREIBUNG]. The framed poster is a modest size on the wall, sharp and clearly legible. Photorealistic interior photography, shallow depth of field, cozy atmosphere."

PAYLOAD=$(cat <<EOF
{
  "model": "gen4_image",
  "promptText": "$PROMPT",
  "ratio": "720:1280",
  "referenceImages": [ { "uri": "$DATA_URI", "tag": "poster" } ]
}
EOF
)
# Retry mit Backoff bei 429/5xx (gleiches Muster wie /mockup)
for attempt in 1 2 3 4; do
  code=$(echo "$PAYLOAD" | curl -s -o /tmp/runway_img_resp.json -w '%{http_code}' -X POST "https://api.dev.runwayml.com/v1/text_to_image" \
    -H "Authorization: Bearer $RUNWAY_API_SECRET" \
    -H "X-Runway-Version: 2024-11-06" \
    -H "Content-Type: application/json" \
    --data-binary @-)
  [ "$code" = "200" ] && break
  case "$code" in 429|500|502|503|529) sleep $((attempt*attempt*3)); echo "retry text_to_image ($code), Versuch $attempt";; *) break;; esac
done
RESPONSE=$(cat /tmp/runway_img_resp.json)
echo "$RESPONSE"
IMG_TASK_ID=$(echo "$RESPONSE" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
[ -n "$IMG_TASK_ID" ] || { echo "Runway-Fehler (HTTP $code): $RESPONSE"; exit 1; }
```

Polling (alle 5s) bis `SUCCEEDED`, dann Still laden:

```bash
for i in $(seq 1 20); do
  sleep 5
  SR=$(curl -s "https://api.dev.runwayml.com/v1/tasks/$IMG_TASK_ID" -H "Authorization: Bearer $RUNWAY_API_SECRET" -H "X-Runway-Version: 2024-11-06")
  ST=$(echo "$SR" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
  echo "[img $i] $ST"
  if [ "$ST" = "SUCCEEDED" ]; then
    IMG_URL=$(echo "$SR" | grep -o '"output":\["[^"]*"' | cut -d'"' -f4)
    curl -s -L "$IMG_URL" -o /tmp/runway_room_still.png
    break
  elif [ "$ST" = "FAILED" ]; then echo "FAILED: $SR"; exit 1; fi
done
```

**Standbild dem User per `Read` zeigen und bestaetigen lassen**, dass Design und Raum stimmen, bevor Schritt 2 (sonst Video-Generation verschwendet). Bei Nein: Prompt anpassen, Schritt 1 wiederholen.

### 7. Schritt 2 — Standbild animieren (image_to_video)

```bash
magick /tmp/runway_room_still.png -quality 88 /tmp/runway_room_still.jpg
BASE64=$(base64 -i /tmp/runway_room_still.jpg | tr -d '\n')
DATA_URI="data:image/jpeg;base64,${BASE64}"
MPROMPT="Continuous seamless shot. The camera slowly glides sideways through the room with a smooth dolly movement, gentle parallax as the foreground furniture and plants drift past the framed poster. Soft light, leaves sway subtly. Calm, cinematic, photorealistic."

PAYLOAD=$(cat <<EOF
{
  "model": "gen4_turbo",
  "promptImage": "$DATA_URI",
  "promptText": "$MPROMPT",
  "ratio": "720:1280",
  "duration": 5
}
EOF
)
# Retry mit Backoff bei 429/5xx (gleiches Muster wie /mockup)
for attempt in 1 2 3 4; do
  code=$(echo "$PAYLOAD" | curl -s -o /tmp/runway_vid_resp.json -w '%{http_code}' -X POST "https://api.dev.runwayml.com/v1/image_to_video" \
    -H "Authorization: Bearer $RUNWAY_API_SECRET" \
    -H "X-Runway-Version: 2024-11-06" \
    -H "Content-Type: application/json" \
    --data-binary @-)
  [ "$code" = "200" ] && break
  case "$code" in 429|500|502|503|529) sleep $((attempt*attempt*3)); echo "retry image_to_video ($code), Versuch $attempt";; *) break;; esac
done
RESPONSE=$(cat /tmp/runway_vid_resp.json)
echo "$RESPONSE"
TASK_ID=$(echo "$RESPONSE" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
[ -n "$TASK_ID" ] || { echo "Runway-Fehler (HTTP $code): $RESPONSE"; exit 1; }
```

Ratio nur aus Runways fixer Liste: `1280:720`, `720:1280`, `1104:832`, `832:1104`, `960:960`, `1584:672`. Hochformat = `720:1280`.

Polling alle 8s, max 25 Versuche:

```bash
OUTDIR=$(dirname "$BILDPFAD")
BASENAME=$(basename "$BILDPFAD" | sed 's/\.[^.]*$//')
RAW="$OUTDIR/${BASENAME}_lifestyle_${RAUMSTIL}.mp4"
for i in $(seq 1 25); do
  sleep 8
  SR=$(curl -s "https://api.dev.runwayml.com/v1/tasks/$TASK_ID" -H "Authorization: Bearer $RUNWAY_API_SECRET" -H "X-Runway-Version: 2024-11-06")
  ST=$(echo "$SR" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
  echo "[vid $i] $ST"
  if [ "$ST" = "SUCCEEDED" ]; then
    VIDEO_URL=$(echo "$SR" | grep -o '"output":\["[^"]*"' | cut -d'"' -f4)
    curl -s -L "$VIDEO_URL" -o "$RAW"; break
  elif [ "$ST" = "FAILED" ]; then echo "FAILED: $SR"; exit 1; fi
done
```

### 8. Loopbar machen (Boomerang)

Vorwaerts + Rueckwaerts ergibt nahtlosen Loop (~10s). Doppeltes Randbild beim Reverse verwerfen.

```bash
LOOP="$OUTDIR/${BASENAME}_lifestyle_${RAUMSTIL}_loop.mp4"
ffmpeg -y -i "$RAW" -filter_complex \
  "[0:v]split[a][b];[b]reverse,trim=start_frame=1,setpts=PTS-STARTPTS[r];[a][r]concat=n=2:v=1[out]" \
  -map "[out]" -an -c:v libx264 -pix_fmt yuv420p -movflags +faststart "$LOOP"
```

Poster-Frame (erstes Bild) als WebP exportieren. Wird im Shop als `poster` angezeigt, bis das Video laedt. Im Filament-Admin ins Feld "Video-Poster" hochladen.

```bash
POSTER="$OUTDIR/${BASENAME}_lifestyle_${RAUMSTIL}_poster.webp"
# ffmpeg-Builds ohne libwebp: erst PNG-Frame, dann mit ImageMagick zu WebP
ffmpeg -y -i "$RAW" -frames:v 1 /tmp/poster_frame.png
magick /tmp/poster_frame.png -quality 85 "$POSTER"
```

### 9. Web-Optimierung (falls in Schritt 4 `ja`)

HandBrake mit faststart und RF23. NICHT die `Social ...`-Presets (beschneiden auf quadratisch, machen groesser).

```bash
WEB="$OUTDIR/${BASENAME}_lifestyle_${RAUMSTIL}_loop_web.mp4"
HandBrakeCLI -i "$LOOP" -o "$WEB" -e x264 -q 23 --optimize 2>/dev/null
```

### 10. Zusammenfassung ausgeben

```
Video erstellt:
  Eingabe:   pfad/zum/bild.jpg
  Stil:      warm-boho
  Still:     (gen4_image, Poster im Raum)
  Roh:       ..._lifestyle_warm-boho.mp4          (5s, Kamerafahrt)
  Loop:      ..._lifestyle_warm-boho_loop.mp4     (10s, nahtlos)
  Web:       ..._lifestyle_warm-boho_loop_web.mp4 (faststart, kleiner)
  Poster:    ..._lifestyle_warm-boho_poster.webp  (Standbild fuers Shop-video)
```

Fuer den Shop: im Filament-Admin am Produkt das `_loop_web.mp4` ins Feld "Lifestyle-Video" und das `_poster.webp` ins Feld "Video-Poster" hochladen.

## Fehlerbehandlung

- `RUNWAY_API_SECRET` fehlt: klar benennen, kein weiterer Schritt.
- Datei nicht gefunden: Pfad nochmal nachfragen.
- Validierungsfehler `too_big` bei promptImage/referenceImages: Bild zu gross, Trim/Resize pruefen.
- Validierungsfehler bei `ratio`: nur erlaubte Werte (siehe Schritt 7); die API listet sie im Fehler.
- Anderer API-Fehler: vollstaendigen Body inkl. `issues` ausgeben.
- Timeout: Task-ID ausgeben fuers Runway-Dashboard.
- `ffmpeg`/`HandBrakeCLI`/`magick` fehlt: `brew install ffmpeg handbrake imagemagick`.

## Hinweise

- Roh-Clip 5s, Loop 10s, 720x1280 (Hochformat, Reels/Pinterest/Produktseite).
- Voraussetzungen: ImageMagick (`magick`), ffmpeg, HandBrakeCLI, alle via Homebrew.
- Fuer mehrere Produkte: Skill mehrfach aufrufen (kein Batch).
- Das Zwischen-Standbild vor dem teuren Video-Schritt immer kurz zeigen lassen, spart Fehlversuche.
