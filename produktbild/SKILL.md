---
name: produktbild
description: "Erstellt treue KI-Lifestyle-Produktbilder: ein beliebiges Motiv (Poster, Print, Design) wird unveraendert als gerahmtes Bild in 1-5 realistische Wohnraeume mit unterschiedlichen Stimmungen gesetzt. Nano Banana Pro (Gemini 3 Pro Image) via OpenRouter erhaelt Design und Text exakt. Output als WebP fuer die custom_images-Media-Collection. - /produktbild, produktbild erstellen, lifestyle bild, mockup, poster in wohnraum, produktfoto"
argument-hint: "[pfad/zum/motiv.jpg]"
disable-model-invocation: true
model: sonnet
effort: medium
allowed-tools:
  - Bash
  - AskUserQuestion
  - Read
---

# Produktbild: Motiv treu in Wohnraeume (Nano Banana Pro via OpenRouter)

Setzt ein beliebiges Motiv (Poster/Print/Design) **unveraendert** als gerahmtes Bild in 1-5 fotorealistische Wohnraeume mit waehlbaren Stimmungen. Ergebnis als WebP fuer die `custom_images`-Collection (ersetzt Printful-Bilder, sobald gesetzt).

## Warum dieser Ansatz

Frueher per Runway gen4_image getestet: regeneriert das Motiv aus der Referenz, Text verrutscht. Composite-Umweg (Poster in KI-Raum warpen) ist fragil (Eck-Erkennung kippt bei Schatten). **Nano Banana Pro** (Gemini 3 Pro Image) erhaelt das Referenz-Motiv pixel-treu inkl. Schrift und braucht nur einen API-Call. Runway bleibt fuer Video (`/produktvideo`), Bild laeuft ueber OpenRouter.

Kosten ca. 0,14 USD pro Bild (2K). Das Modell liefert oft 1-2 Varianten pro Call.

## Prompt-Regeln (aus Praxis)

- Motiv-Treue explizit fordern: "this exact poster, completely unchanged, colors, lettering and layout stay 100% identical to the reference".
- **Glas-Glare vermeiden** (sonst Spiegelung ueberm Druck, schlechte Lesbarkeit): "matte finish, the artwork fully visible and evenly lit, no glass glare or reflections".
- Stimmung/Licht/Moebel positiv beschreiben. Nano Banana folgt Instruktionen gut, Negativ-Prompts sind hier ok, aber positiv formulieren ist sicherer.

## Ablauf

### 1. API-Key laden

OpenRouter-Key. Meine Bash-Shell erbt nur das Environment vom Session-Start, ein nachtraeglich in `~/.zshrc` ergaenzter Key fehlt dort. Daher: env zuerst, sonst aus `~/.zshrc`/`~/.zshenv` lesen.

```bash
KEY="${OPENROUTER_API_KEY:-}"
[ -z "$KEY" ] && KEY=$(grep -m1 '^export OPENROUTER_API_KEY=' "$HOME/.zshrc" "$HOME/.zshenv" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"')
[ -z "$KEY" ] && { echo "OPENROUTER_API_KEY nicht gesetzt. In ~/.zshrc eintragen: export OPENROUTER_API_KEY=sk-or-..."; exit 1; }
echo "Key: ${KEY:0:10}..."
```

### 2. Motivdatei ermitteln

Pfad aus `$ARGUMENTS` nutzen (`/produktbild pfad/zum/motiv.jpg`; leer, wenn keiner uebergeben wurde), sonst per `AskUserQuestion` nach absolutem Pfad fragen. Datei per `Read` anschauen (Farben/Stimmung erfassen, hilft bei Raum-Empfehlung). Formate: JPEG, PNG, WebP.

### 3. Stimmungen, Format, Aufloesung waehlen

Per `AskUserQuestion`:

Frage "Welche Raumstimmungen? (bis zu 5)" (multiSelect):
- `skandinavisch-hell` — helles Holz, weiss, Morgenlicht
- `warm-boho` — Terracotta/Creme, Rattan, Pflanzen, Abendlicht
- `urban-modern` — dunkle Akzentwand, Beton, gerichtetes Licht
- `japandi-minimal` — ruhige Naturtoene, viel Leere, sanftes Tageslicht
- (weitere bei Bedarf: `schlafzimmer-cozy`, `studio-hell`, `galerie-wand`)

Frage "Format?" (single): `hochformat` → `3:4` (Detailseite), `quadratisch` → `1:1` (Grid), `querformat` → `4:3` (Raumkontext/OG).

Frage "Aufloesung?" (single): `2K` (empfohlen, ~0,14 USD) oder `4K` (groesser, teurer).

### 4. Referenz vorbereiten

Motiv handlich skalieren (Modell braucht keine 6k px, spart Tokens). **Nicht trimmen**: einen eingebauten weissen Rand/Margin behaelt das Motiv, der gehoert zum Design und muss im Mockup erscheinen.

```bash
magick "$MOTIV" -resize 1280x /tmp/pb_ref.jpg
B64=$(base64 -i /tmp/pb_ref.jpg | tr -d '\n')
```

### 5. Pro Stimmung generieren

Raum-Beschreibung je Stimmung:

- `skandinavisch-hell`: a bright Scandinavian living room with white walls, light oak furniture, a cozy armchair and soft morning light
- `warm-boho`: a warm bohemian living room with terracotta and cream tones, a rattan armchair, hanging plants and soft warm evening light
- `urban-modern`: a modern urban living room with a dark accent wall, concrete textures, minimal geometric furniture and directional pendant lighting
- `japandi-minimal`: a serene japandi living room with calm neutral tones, natural wood and linen, lots of empty space and soft diffused daylight
- `schlafzimmer-cozy`: a cozy bedroom with linen bedding, warm neutral tones and soft lamp light
- `studio-hell`: a bright minimalist home office with a wooden desk, plants and large windows
- `galerie-wand`: a clean gallery-style wall with neutral paint, wooden floor and a single accent plant

Gewinner-Prompt (aus Praxis, behaelt Rand + Layout am besten):

```bash
ROOM="a warm bohemian living room with terracotta and cream tones, a rattan armchair, hanging plants and soft warm evening light"
RATIO="3:4"; SIZE="2K"
PROMPT="Create a photorealistic interior photograph of ${ROOM}. On the wall hangs this exact poster as a framed art print in a thin black frame. Reproduce the poster artwork 100% identical to the reference, including its built-in white border margin, the exact stripe count and widths, the exact size and position of the large handwritten lettering. Do not crop, do not redraw, do not add an extra passe-partout mat. Matte finish, fully visible, no glass glare. Shallow depth of field, realistic."

# WICHTIG: Response in Datei schreiben. Die base64-Antwort (mehrere MB) sprengt jq in einer Bash-Variable.
jq -n --arg p "$PROMPT" --arg u "data:image/jpeg;base64,${B64}" --arg r "$RATIO" --arg s "$SIZE" '{
  model:"google/gemini-3-pro-image",
  modalities:["image","text"],
  image_config:{aspect_ratio:$r, image_size:$s},
  messages:[{role:"user",content:[{type:"text",text:$p},{type:"image_url",image_url:{url:$u}}]}]
}' > "/tmp/pb_${MOOD}_req.json"

# Retry mit Backoff bei 429/5xx (gleiches Muster wie /mockup, Rate-Limit-Vorfall 2026-07-06)
for attempt in 1 2 3 4; do
  code=$(curl -s -o "/tmp/pb_${MOOD}.json" -w '%{http_code}' -X POST "https://openrouter.ai/api/v1/chat/completions" \
    -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" --data-binary @"/tmp/pb_${MOOD}_req.json")
  [ "$code" = "200" ] && jq -e '.choices[0].message.images|length>0' "/tmp/pb_${MOOD}.json" >/dev/null 2>&1 && break
  case "$code" in 429|500|502|503|529) sleep $((attempt*attempt*3)); echo "retry $MOOD ($code), Versuch $attempt";; *) break;; esac
done

# Fehler pruefen
jq -e '.choices[0].message.images|length>0' "/tmp/pb_${MOOD}.json" >/dev/null 2>&1 \
  || { echo "API-Fehler ($MOOD, HTTP $code): $(jq -c '.error // "no image"' /tmp/pb_${MOOD}.json)"; exit 1; }

# zurueckgegebene Bilder speichern, groesstes ist das volle 2K/4K (kleinere sind Vorschau)
OUTDIR=$(dirname "$MOTIV"); BASE=$(basename "$MOTIV" | sed 's/\.[^.]*$//')
N=$(jq '.choices[0].message.images | length' "/tmp/pb_${MOOD}.json")
best=""; bestpx=0
for i in $(seq 0 $((N-1))); do
  EXT=$(jq -r ".choices[0].message.images[$i].image_url.url" "/tmp/pb_${MOOD}.json" | sed -n 's/^data:image\/\([^;]*\);base64,.*/\1/p')
  TMPF="/tmp/pb_${MOOD}_$i.${EXT:-png}"
  jq -r ".choices[0].message.images[$i].image_url.url" "/tmp/pb_${MOOD}.json" | sed 's/^data:image\/[^;]*;base64,//' | base64 -d > "$TMPF"
  w=$(identify -format '%w' "$TMPF" 2>/dev/null || echo 0)
  [ "$w" -gt "$bestpx" ] && { bestpx=$w; best="$TMPF"; }
done
cp "$best" "$OUTDIR/${BASE}_room_${MOOD}.jpg"
echo "saved ${BASE}_room_${MOOD}.jpg ($(identify -format '%wx%h' "$best")), Kosten $(jq -r '.usage.cost' /tmp/pb_${MOOD}.json) USD"
```

Mehrere Stimmungen: Calls sind unabhaengig, parallel starten (`&` + `wait`), je Mood eine eigene Response-Datei.

**Treue-Hinweis:** Nano Banana zeichnet das Motiv neu, das Ergebnis ist eine sehr treue Interpretation (~95%, Rand/Farben/Layout korrekt), kein Pixel-Abzug. Fuer den Shop bewusst akzeptiert: Raum-Realismus schlaegt die letzten 5%. Wer echte Pixel-Treue braucht, muss die Datei composite-einsetzen (verworfen, zu fragil).

### 6. Auswahl zeigen

Alle erzeugten Bilder per `Read` zeigen. User waehlt. Bei Glas-Glare oder verzerrtem Detail: Prompt scharfstellen (Glare-Phrase betonen) und betroffene Stimmung neu generieren.

### 7. Final als WebP exportieren

Nur ausgewaehlte Bilder zu WebP (passt zur `custom_images`-Konvention):

```bash
magick "$OUT" -quality 85 "$OUTDIR/${BASE}_room_${MOOD}.webp"
```

### 8. Zusammenfassung

```
Produktbilder erstellt:
  Motiv:     pfad/zum/motiv.jpg
  Stimmungen: skandinavisch-hell, warm-boho
  Format:    3:4, 2K
  Ausgewaehlt + WebP:
    ..._room_skandinavisch-hell.webp
    ..._room_warm-boho.webp
```

Fuer den Shop: im Filament-Admin am Produkt die WebPs in die Collection "Eigene Produktbilder" (`custom_images`) hochladen.

## Fehlerbehandlung

- `OPENROUTER_API_KEY` fehlt: in `~/.zshrc` eintragen, kein weiterer Schritt.
- `.error` im Response nicht null: vollstaendigen Fehler ausgeben (oft Guthaben leer oder Rate-Limit).
- Glas-Spiegelung ueberm Druck: Glare-Phrase im Prompt verstaerken, Stimmung neu generieren.
- Motiv minimal veraendert: "completely unchanged ... 100% identical to the reference" betonen, ggf. Referenz hoeher aufloesen.
- `magick` fehlt: `brew install imagemagick`.

## Hinweise

- Modell-ID `google/gemini-3-pro-image` (Nano Banana Pro, GA-ID, kanonisch `-20260528`). Liefert 2K (1792x2400 bei 3:4) bzw. 4K. Die alte Preview-ID `-preview` loest bei OpenRouter zwar noch auf, Preview-IDs werden aber abgekuendigt; GA-IDs sind stabil.
- Ein Key (OpenRouter) deckt viele Bildmodelle ab. Runway bleibt separat fuer Video.
- Motiv ist beliebig: Poster, Print, Illustration, alles was gerahmt an eine Wand passt.
- Fuer mehrere Motive: Skill mehrfach aufrufen.
- Verwandt: `/produktvideo` (Lifestyle-Video via Runway), `/mockup` (generische Mockups auf derselben Nano-Banana-Basis).
