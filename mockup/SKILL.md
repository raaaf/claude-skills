---
name: mockup
description: "Erstellt fotorealistische Mockups eines beliebigen Designs (Logo, Flyer, Workbook, Aufkleber, Visitenkarte, Poster, Branding, Apparel, Verpackung, Social) im passenden Kontext via Nano Banana Pro (Gemini 3 Pro Image) ueber OpenRouter. Digitale/UI-Designs (Website, App, Screenshot) pixeltreu ueber deterministischen ImageMagick-Composite (Browser-/Phone-Rahmen, kein KI-Redraw). Bild waehlen, sagen was es ist, fertiges Mockup. - /mockup, mockup erstellen, logo mockup, flyer mockup, branding mockup, visitenkarte, aufkleber, produktmockup, website mockup, app mockup, ui mockup, screenshot mockup, browser mockup, phone mockup, shirt mockup, verpackung, social mockup"
argument-hint: "[pfad/zum/design.jpg]"
disable-model-invocation: true
model: sonnet
effort: medium
allowed-tools:
  - Bash
  - AskUserQuestion
  - Read
---

# Mockup: Design fotorealistisch in Kontext setzen (Nano Banana Pro via OpenRouter)

Setzt ein beliebiges Design (Logo, Flyer, Workbook, Aufkleber, Visitenkarte, Poster, Branding, Apparel, Verpackung, Social) in einen passenden, fotorealistischen Mockup-Kontext. Bild waehlen, sagen was es ist, das Modell rendert das Mockup.

**Zwei Pfade:** (1) **Physisch/Print/Marketing** ueber Nano Banana (generativ, ~95% treu, Schritte 1-7). (2) **Digital/UI** (Website, App, Screenshot) ueber einen **pixeltreuen ImageMagick-Composite** (Abschnitt "Digital/UI pixeltreu"): echter Screenshot unveraendert in Browser-/Phone-Rahmen, kein KI-Redraw. Bei digitalem Design immer Pfad 2.

Schwester-Skill von `/produktbild` (das ist der Spezialfall "gerahmtes Poster im Wohnraum"). Gleiche Technik (Nano Banana Pro, ein API-Call pro Bild), aber generisch ueber viele Oberflaechen.

Kosten ca. 0,14 USD pro Bild (2K). Das Modell liefert oft 1-2 Varianten pro Call.

## Wichtig: Treue

Nano Banana **zeichnet das Design neu** (sehr treue Interpretation, ~95%, kein Pixel-Abzug). Fuer Mockups/Portfolio/Marketing top. Wenn ein Detail (Schrift, exakte Proportion) driftet: ungetrimmte Referenz nutzen und im Prompt "100% identical to the reference, do not redraw" betonen. Pixel-genau gibt es nur per Composite (bewusst nicht gebaut, zu fragil).

**Website-/App-Screenshots und jedes digitale/UI-Design: pixeltreu ueber den Composite-Pfad (Abschnitt "Digital/UI pixeltreu"), NICHT ueber Nano Banana.** Das Modell zeichnet UI neu und driftet bei dichter Kleinschrift; fuer digitales Design ist das der falsche Weg. Der Composite setzt den echten Screenshot unveraendert in einen magick-gebauten Rahmen (Browser-Chrome / Phone-Bezel), 0 Pixel-Drift, kostenlos, deterministisch. Die generativen Device-Kontexte (`phone-hand`, `laptop-desk` etc.) sind nur fuer Lifestyle-Vibe-Shots (Hand haelt Handy im Cafe) gedacht und ausdruecklich NICHT pixeltreu.

## Ablauf

### 1. API-Key laden

```bash
KEY="${OPENROUTER_API_KEY:-}"
[ -z "$KEY" ] && KEY=$(grep -m1 '^export OPENROUTER_API_KEY=' "$HOME/.zshrc" "$HOME/.zshenv" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"')
[ -z "$KEY" ] && { echo "OPENROUTER_API_KEY nicht gesetzt (in ~/.zshrc: export OPENROUTER_API_KEY=sk-or-...)"; exit 1; }
echo "Key: ${KEY:0:10}..."
```

### 2. Designdatei ermitteln + ansehen

Pfad aus `$ARGUMENTS` nutzen (leer, wenn keiner uebergeben wurde), sonst per `AskUserQuestion` nach absolutem Pfad fragen. Datei per `Read` anschauen: erkennen **was es ist** (Logo, Flyer, Aufkleber, Workbook-Cover, Visitenkarte, Poster, volles Branding) und welche Form/Farben. Das steuert die Mockup-Empfehlung.

### 3. Mockup-Kontext waehlen

Anhand des Design-Typs die passenden Kontexte vorschlagen. `AskUserQuestion` (multiSelect, bis zu 4 + Freitext/Other). Mapping:

| Design ist... | Sinnvolle Mockups |
|---|---|
| Logo | `schild`, `visitenkarte`, `branding-flatlay`, `tasse`, `tote` |
| Flyer | `flyer-hand`, `flyer-tisch`, `poster-wand` |
| Workbook / Booklet | `workbook-desk`, `workbook-hand`, `branding-flatlay` |
| Aufkleber | `sticker-laptop`, `sticker-sheet`, `sticker-flasche` |
| Visitenkarte | `visitenkarte`, `branding-flatlay` |
| Poster / Print | `poster-wand` (oder `/produktbild` nutzen) |
| Print-Motiv / Apparel-Design | `shirt`, `hoodie`, `tote`, `tasse` |
| Verpackung / Versand | `versandkarton`, `mailer`, `hangtag`, `produktlabel` |
| Social / Ad-Creative | `social-ad`, `story-frame`, `instagram-post` |
| Website / Landingpage (Screenshot) | **Composite-Pfad** (pixeltreu): `browser`, `responsive-set`. Nur fuer Lifestyle-Vibe generativ: `laptop-desk` |
| Mobile / App-Screen (Screenshot) | **Composite-Pfad** (pixeltreu): `phone`. Nur fuer Lifestyle-Vibe generativ: `phone-hand`, `phone-flatlay` |
| Volles Branding | `branding-flatlay`, `visitenkarte`, `briefpapier`, `schild` |

Dazu `Format?` (Aspect je Kontext, siehe Bibliothek) und `Aufloesung?` (`1K` fuer schnelle guenstige Previews / `2K` empfohlen fuer final / `4K` fuer Print/Zoom).

### 4. Referenz vorbereiten (typabhaengig, flexibel)

Nano Banana frisst nur Raster (PNG/JPEG/WebP), kein SVG/PDF. Ablauf:

**a) Vektor/PDF zuerst rastern** (300dpi), falls noetig:

```bash
EXT_IN=$(echo "$DESIGN" | tr 'A-Z' 'a-z' | sed 's/.*\.//')
SRC="$DESIGN"
if [ "$EXT_IN" = "pdf" ]; then
  pdftoppm -png -r 300 "$DESIGN" /tmp/mk_src && SRC=$(ls /tmp/mk_src*.png | head -1)
elif [ "$EXT_IN" = "svg" ]; then
  magick -density 300 -background none "$DESIGN" /tmp/mk_src.png && SRC=/tmp/mk_src.png
fi
```

Bei mehrseitigem PDF oder Brand-Sheet ggf. erst per `Read` ansehen und das gewuenschte Asset mit `magick "$SRC" -crop WxH+X+Y +repage` herausschneiden (wie beim E-Werk-Logo).

**b) Referenz-Typ abfragen** per `AskUserQuestion` "Was fuer eine Referenz?":
- `Logo/Icon (freigestellt)` — soll auf farbige Flaechen (Schild, Tasse, Tote)
- `Poster/Flyer/Print (randvoll)` — volle Flaeche, eingebauter Rand bleibt
- `Foto/komplexes Bild` — Foto-Artwork

**c) Je Typ aufbereiten** (immer sRGB):

```bash
TYPE="logo"   # bzw. print / foto
case "$TYPE" in
  logo)  # Alpha erhalten, transparent lassen, scharf, gross
    magick "$SRC" -colorspace sRGB -resize 1800x -background none /tmp/mk_ref.png
    REF=/tmp/mk_ref.png; REF_MIME="image/png" ;;
  print) # randvoll, Rand behalten, weiss flatten, PNG verlustfrei
    magick "$SRC" -colorspace sRGB -background white -alpha remove -alpha off -resize 1600x /tmp/mk_ref.png
    REF=/tmp/mk_ref.png; REF_MIME="image/png" ;;
  foto)  # Foto, JPG reicht
    magick "$SRC" -colorspace sRGB -resize 1600x -quality 90 /tmp/mk_ref.jpg
    REF=/tmp/mk_ref.jpg; REF_MIME="image/jpeg" ;;
esac
B64=$(base64 -i "$REF" | tr -d '\n')
echo "ref $REF ($REF_MIME) $(identify -format '%wx%h' "$REF")"
```

Faustregel: **PNG verlustfrei fuer Logo/Print** (scharfe Kanten, Schrift), transparent nur bei Logo. JPG nur fuer Fotos. Immer sRGB (CMYK-Quellen kippen sonst die Farben).

### 5. Prompt-Bibliothek (je Kontext)

Jeder Prompt endet mit dem Treue-Suffix:
`Show the entire design exactly as in the reference: identical text, colours, proportions and layout, uncropped, with all text sharp and legible. Photorealistic, soft natural shadows, realistic lighting.`

Warum positiv formuliert: Google/DeepMind nennen positives Framing ("show the entire design") ausdruecklich robuster als Verbote ("do not crop/redraw"). Text als eigene semantische Ebene behandelt das Modell besser, wenn Treue explizit auf Text bezogen wird ("all text sharp and legible"). Bei hartem Schrift-Drift zusaetzlich den exakten Wortlaut in Quotes nennen (z.B. `the wordmark reads "punkt und pause"`).

Aufbau je Szene folgt der Nano-Banana-Formel: **Subjekt + Umgebung. Komposition/Kamera. Licht.** Kamera- und Licht-Baustein sind bereits eingearbeitet, Materialien bewusst konkret (nicht "mug" sondern "matte ceramic mug").

| Kontext | Aspect | Szenen-Prompt (vor dem Suffix) |
|---|---|---|
| `poster-wand` | 3:4 | On the wall of a bright, tastefully decorated living room hangs this exact artwork as a framed art print in a thin black frame, including its built-in white border. Eye-level shot, 35mm lens, shallow depth of field. Soft diffused daylight from a side window, matte finish, no glass glare. |
| `visitenkarte` | 1:1 | A small stack of business cards on a warm oak desk with one card lying face up showing this exact design, a pen and a coffee cup softly blurred beside it. Top-down flatlay, 50mm macro, shallow depth of field (f/2.8). Soft natural window light, gentle shadows. |
| `briefpapier` | 4:3 | A branded stationery flatlay on a light linen desk: an A4 letterhead showing this exact design, a kraft envelope and a fountain pen beside it. Top-down, 50mm, shallow depth of field. Soft diffused daylight. |
| `branding-flatlay` | 4:3 | A full brand identity flatlay neatly arranged on a textured concrete surface: business cards, letterhead, a folder and a notebook, all featuring this exact logo/design. Top-down, 35mm, even soft lighting. Three-point softbox setup, subtle shadows. |
| `schild` | 4:3 | This exact logo mounted as clean dimensional lettering on the facade wall of a modern venue entrance. Slight low-angle architectural shot, 24mm wide lens. Bright directional daylight, crisp shadows. |
| `flyer-hand` | 3:4 | A hand holding this exact flyer in a warm cafe, the flyer showing this exact design. Close-up, 50mm, shallow depth of field (f/1.8), blurred background. Soft warm window light. |
| `flyer-tisch` | 4:3 | This exact flyer lying on a rustic cafe table next to a matte ceramic coffee cup and a notebook, slightly angled. 35mm, shallow depth of field. Soft natural daylight, gentle shadows. |
| `workbook-desk` | 4:3 | A softcover workbook on a wooden desk, its cover showing this exact design, a pen and a matte ceramic cup of coffee beside it, slightly angled. 50mm, shallow depth of field. Soft morning daylight. |
| `workbook-hand` | 3:4 | Hands holding an open workbook whose cover shows this exact design, cozy indoor setting. Close-up, 50mm, shallow depth of field. Warm soft indoor light. |
| `sticker-laptop` | 4:3 | A brushed-aluminium laptop lid with this exact design applied as one die-cut sticker among a few subtle others. Angled close-up, 35mm, shallow depth of field. Soft cool daylight, gentle reflections. |
| `sticker-sheet` | 1:1 | A kiss-cut sticker sheet of this exact design on white backing paper. Top-down flatlay, 50mm macro. Even soft studio light, faint paper texture and shadow. |
| `sticker-flasche` | 3:4 | A stainless-steel reusable water bottle with this exact design as a die-cut sticker, on a light wood desk. 50mm, shallow depth of field. Soft daylight, subtle metallic reflections. |
| `tasse` | 1:1 | A matte ceramic mug with this exact design printed on it, on a light kitchen counter. 50mm, shallow depth of field. Soft morning window light, gentle steam. |
| `tote` | 3:4 | A natural cotton canvas tote bag with this exact design printed on it, held by a person walking outdoors. 50mm, shallow depth of field, blurred street background. Soft golden daylight. |
| `shirt` | 3:4 | A person wearing a heather-grey t-shirt with this exact design printed centred on the chest, upper-body shot outdoors. 50mm, shallow depth of field, blurred background. Soft daylight, natural fabric folds. |
| `hoodie` | 3:4 | A person wearing a cream hoodie with this exact design printed on the chest, casual outdoor setting. 50mm, shallow depth of field. Soft daylight, natural fabric texture. |
| `versandkarton` | 4:3 | A kraft cardboard shipping box with this exact design printed as a label on the lid, on a light wooden table. Slight top-down angle, 35mm. Soft daylight, gentle shadows. |
| `mailer` | 4:3 | A flat kraft paper mailer envelope with this exact design printed on the front, held in two hands. 50mm, shallow depth of field. Soft daylight. |
| `hangtag` | 3:4 | A cardboard hangtag showing this exact design, tied with string to a folded garment. Close-up, 50mm macro, shallow depth of field. Soft daylight. |
| `produktlabel` | 1:1 | A matte kraft jar with this exact design applied as a wraparound product label, on a light shelf. Straight-on, 50mm. Soft studio light, gentle shadow. |
| `social-ad` | 4:5 | This exact design presented as a clean social media ad creative on a soft neutral gradient background with a subtle drop shadow, straight-on flat product shot. Even soft studio light. |
| `story-frame` | 9:16 | This exact design shown full-bleed as a smartphone Instagram story screen, held in a hand in a casual bright setting. 50mm, shallow depth of field. Soft daylight, screen crisp. |
| `instagram-post` | 1:1 | A smartphone showing an Instagram feed with this exact design as the featured square post, held in hand. Close-up, 50mm, shallow depth of field. Soft daylight, screen crisp. (Fuer ein exakt designtes Post-Motiv besser den pixeltreuen `phone`-Composite nutzen.) |
| `phone-hand` | 3:4 | A hand holding a modern smartphone in a cafe, its screen showing this exact mobile design edge-to-edge. Close-up, 50mm, shallow depth of field, blurred warm background. Screen bright and crisp, no glare. |
| `phone-flatlay` | 1:1 | A smartphone lying on a light desk next to a notebook and pen, its screen showing this exact mobile design. Top-down flatlay, 50mm, soft daylight. Screen sharp and legible, no glare. |
| `laptop-desk` | 16:9 | A modern laptop on a wooden desk in a bright office, its screen showing this exact website design filling the browser. Slight angle, 35mm, shallow depth of field. Soft daylight, screen crisp, no reflections. (Lifestyle-Vibe, nicht pixeltreu; pixelgenau via Composite-Pfad.) |

Freitext/Other: Szene nach der Formel bauen (Subjekt + Umgebung, dann Kamera/Brennweite/Blende, dann Licht), Suffix anhaengen.

### 6. Generieren (pro Kontext)

```bash
SCENE="A small stack of business cards with one card lying face up on a warm oak desk, the card shows this exact design, top-down flatlay, shallow depth of field."
SUFFIX="Show the entire design exactly as in the reference: identical text, colours, proportions and layout, uncropped, with all text sharp and legible. Photorealistic, soft natural shadows, realistic lighting."
PROMPT="${SCENE} ${SUFFIX}"
RATIO="1:1"; SIZE="2K"; CTX="visitenkarte"

# Payload in Datei (grosse base64 sprengt jq/curl in einer Bash-Variable)
jq -n --arg p "$PROMPT" --arg u "data:${REF_MIME};base64,${B64}" --arg r "$RATIO" --arg s "$SIZE" '{
  model:"google/gemini-3-pro-image", modalities:["image","text"],
  image_config:{aspect_ratio:$r, image_size:$s},
  messages:[{role:"user",content:[{type:"text",text:$p},{type:"image_url",image_url:{url:$u}}]}]
}' > "/tmp/mk_${CTX}_req.json"

# Retry mit Backoff bei 429/5xx (Rate-Limit / Overload wie am 2026-07-06 erlebt)
for attempt in 1 2 3 4; do
  code=$(curl -s -o "/tmp/mk_${CTX}.json" -w '%{http_code}' -X POST "https://openrouter.ai/api/v1/chat/completions" \
    -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" --data-binary @"/tmp/mk_${CTX}_req.json")
  [ "$code" = "200" ] && jq -e '.choices[0].message.images|length>0' "/tmp/mk_${CTX}.json" >/dev/null 2>&1 && break
  case "$code" in 429|500|502|503|529) sleep $((attempt*attempt*3)); echo "retry $CTX ($code), Versuch $attempt";; *) break;; esac
done

jq -e '.choices[0].message.images|length>0' "/tmp/mk_${CTX}.json" >/dev/null 2>&1 \
  || { echo "API-Fehler ($CTX, HTTP $code): $(jq -c '.error // "no image"' /tmp/mk_${CTX}.json)"; exit 1; }

OUTDIR=$(dirname "$DESIGN"); BASE=$(basename "$DESIGN" | sed 's/\.[^.]*$//')
N=$(jq '.choices[0].message.images|length' "/tmp/mk_${CTX}.json"); best=""; bestpx=0
for i in $(seq 0 $((N-1))); do
  EXT=$(jq -r ".choices[0].message.images[$i].image_url.url" "/tmp/mk_${CTX}.json" | sed -n 's/^data:image\/\([^;]*\);base64,.*/\1/p')
  TMPF="/tmp/mk_${CTX}_$i.${EXT:-png}"
  jq -r ".choices[0].message.images[$i].image_url.url" "/tmp/mk_${CTX}.json" | sed 's/^data:image\/[^;]*;base64,//' | base64 -d > "$TMPF"
  w=$(identify -format '%w' "$TMPF" 2>/dev/null||echo 0); [ "$w" -gt "$bestpx" ] && { bestpx=$w; best="$TMPF"; }
done
cp "$best" "$OUTDIR/${BASE}_mockup_${CTX}.jpg"
echo "saved ${BASE}_mockup_${CTX}.jpg ($(identify -format '%wx%h' "$best")), $(jq -r '.usage.cost' /tmp/mk_${CTX}.json) USD"
```

Mehrere Kontexte: Calls sind unabhaengig, parallel starten (`&` + `wait`), je Kontext eine eigene Response-Datei.

### 6b. Mehrere Referenzbilder (bis 14)

Bei komplexem Branding oder wenn ein Winkel driftet, mehrere Referenzen mitgeben und im Prompt Rollen benennen. Zusaetzliche `image_url`-Eintraege ins `content`-Array:

```bash
B64A=$(base64 -i ref_logo.png | tr -d '\n'); B64B=$(base64 -i ref_style.jpg | tr -d '\n')
PROMPT="Use image 1 as the exact logo and image 2 as the colour/style reference. ${SCENE} ${SUFFIX}"
jq -n --arg p "$PROMPT" --arg a "data:image/png;base64,${B64A}" --arg b "data:image/jpeg;base64,${B64B}" --arg r "$RATIO" --arg s "$SIZE" '{
  model:"google/gemini-3-pro-image", modalities:["image","text"],
  image_config:{aspect_ratio:$r, image_size:$s},
  messages:[{role:"user",content:[{type:"text",text:$p},{type:"image_url",image_url:{url:$a}},{type:"image_url",image_url:{url:$b}}]}]
}' > /tmp/mk_multi_req.json
```

Danach identischer curl-Retry-Block wie in Schritt 6.

### 7. Zeigen + bei Bedarf nachschaerfen

Alle Mockups per `Read` zeigen. Driftet ein Detail: Treue-Suffix verstaerken, Kontext neu generieren. Glas/Reflexe stoeren: "matte finish, no glare" ergaenzen.

## Digital/UI pixeltreu (Composite-Pfad, kein KI-Redraw)

Fuer Website-/App-/UI-Designs: Nano Banana zeichnet UI neu und driftet bei Kleinschrift. Pixeltreu geht nur ueber einen **deterministischen ImageMagick-Composite**: echten Screenshot unveraendert lassen, nur Browser-Chrome bzw. Phone-Bezel drumherum bauen. 0 Pixel-Drift, kostenlos, sofort. Straight-on/flach ist per Konstruktion pixelgenau; perspektivische Winkel gaebe es nur mit hinterlegten Eck-Koordinaten (fragil, bewusst raus, dafuer die generativen Device-Kontexte als Vibe-Shot).

**Wichtig (magick-Maske):** Ecken-Rundung per `CopyOpacity` braucht eine **weisse Form auf schwarzem** Grund (`xc:black -fill white`). Schwarz-auf-transparent invertiert die Alpha und macht alles unsichtbar.

### A. Screenshot aufnehmen (retina, definierter Pfad)

Bester Input ist ein **PNG des Nutzers** (Figma-Export, exakte Pixelmasse) -> direkt zu Schritt B/C. Fuer Live-Capture **CDP-Device-Emulation, NICHT `--headless --window-size`**: bei schmalen Viewports (Mobile) klemmt Chrome die Fensterbreite auf ~500-600px, rendert die Seite breit und schneidet den Screenshot-Canvas rechts ab (Live-Incident 2026-07-06: Mobile-Shot abgeschnitten). CDP `Emulation.setDeviceMetricsOverride` mit `mobile:true` setzt die echte CSS-Breite.

Dependency-freies CDP-Script (`shot.mjs`, Node 22+ hat globales `WebSocket`/`fetch`):

```javascript
import { writeFileSync } from 'node:fs';
const [url, out, w, h, dsf, mobile] = process.argv.slice(2);
const list = await (await fetch(`http://127.0.0.1:9333/json/new?about:blank`, {method:'PUT'})).json();
const ws = new WebSocket(list.webSocketDebuggerUrl); await new Promise(r => ws.onopen = r);
let id=0; const p=new Map(); ws.onmessage=e=>{const m=JSON.parse(e.data); if(m.id&&p.has(m.id)){p.get(m.id)(m);p.delete(m.id);}};
const send=(method,params={})=>new Promise(res=>{const i=++id;p.set(i,res);ws.send(JSON.stringify({id:i,method,params}));});
await send('Page.enable');
await send('Emulation.setDeviceMetricsOverride',{width:+w,height:+h,deviceScaleFactor:+dsf,mobile:mobile==='1'});
await send('Page.navigate',{url}); await new Promise(r=>setTimeout(r,3500));
const {result}=await send('Page.captureScreenshot',{format:'png',captureBeyondViewport:false});
writeFileSync(out,Buffer.from(result.data,'base64')); ws.close(); process.exit(0);
```

```bash
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
"$CHROME" --headless=new --disable-gpu --remote-debugging-port=9333 --user-data-dir=/tmp/cdp-prof about:blank >/dev/null 2>&1 &
CPID=$!; sleep 2
node shot.mjs "https://example.com" shot_desktop.png 1440 900 2 0   # Desktop @2x
node shot.mjs "https://example.com" shot_mobile.png  390  844 3 1   # Mobile  @3x, mobile:true
kill $CPID 2>/dev/null
```

Kontrolle: `magick shot_mobile.png -format '%[fx:standard_deviation]' info:` (nahe 0 = nicht gerendert -> Ladezeit hoch) und **rechten Rand pruefen** (nichts abgeschnitten). JS-lastige Seiten brauchen ggf. mehr als die 3500ms Wartezeit im Script.

### B. Browser-Fenster-Composite (Desktop @2x)

```bash
FONT='/System/Library/Fonts/Helvetica.ttc'; BG='#eceae5'; URL='example.com'
SHOT=shot_desktop.png; OUT=site_browser.png
W=$(identify -format '%w' "$SHOT"); BAR=88
magick -size ${W}x${BAR} xc:'#f0efec' -gravity None \
  -fill '#ff5f57' -draw "circle 56,44 56,53" -fill '#febc2e' -draw "circle 98,44 98,53" -fill '#28c840' -draw "circle 140,44 140,53" \
  -fill white -stroke '#e2e0db' -strokewidth 2 -draw "roundrectangle 320,24 $((W-320)),64 20,20" \
  -stroke none -fill '#8a8a86' -font "$FONT" -pointsize 28 -gravity West -annotate +360+1 "$URL" /tmp/br_bar.png
magick /tmp/br_bar.png "$SHOT" -append /tmp/br_comb.png
H=$(identify -format '%h' /tmp/br_comb.png)
magick -size ${W}x${H} xc:black -fill white -draw "roundrectangle 0,0,$((W-1)),$((H-1)),28,28" /tmp/br_mask.png
magick /tmp/br_comb.png /tmp/br_mask.png -alpha off -compose CopyOpacity -composite /tmp/br_round.png
magick /tmp/br_round.png \( +clone -background black -shadow 55x35+0+25 \) +swap -background none -layers merge +repage \
  -bordercolor "$BG" -border 120 -background "$BG" -flatten "$OUT"
```

### C. Phone-Composite (Mobile @3x)

```bash
BG='#eceae5'; SHOT=shot_mobile.png; OUT=site_phone.png
SW=$(identify -format '%w' "$SHOT"); SH=$(identify -format '%h' "$SHOT")
IR=110; PAD=54; OR=176
magick -size ${SW}x${SH} xc:black -fill white -draw "roundrectangle 0,0,$((SW-1)),$((SH-1)),$IR,$IR" /tmp/ph_mask.png
magick "$SHOT" /tmp/ph_mask.png -alpha off -compose CopyOpacity -composite /tmp/ph_screen.png
BW=$((SW+2*PAD)); BH=$((SH+2*PAD))
magick -size ${BW}x${BH} xc:none -fill '#111111' -draw "roundrectangle 0,0,$((BW-1)),$((BH-1)),$OR,$OR" /tmp/ph_bezel.png
magick /tmp/ph_bezel.png /tmp/ph_screen.png -gravity center -compose over -composite /tmp/ph_dev.png
magick /tmp/ph_dev.png \( +clone -background black -shadow 60x40+0+30 \) +swap -background none -layers merge +repage \
  -bordercolor "$BG" -border 100 -background "$BG" -flatten "$OUT"
```

Konstanten (BAR 88 / IR 110 / PAD 54 / OR 176) sind fuer @2x bzw. @3x kalibriert. Bei anderer Skalierung proportional mitziehen. `responsive-set` (Laptop + Tablet + Phone nebeneinander): drei Composites bauen und mit `magick +append` auf neutralem BG montieren.

## Fehlerbehandlung

- `OPENROUTER_API_KEY` fehlt: in `~/.zshrc` eintragen.
- `.choices[0].message.images` leer: vollstaendigen `.error` ausgeben (oft Guthaben leer / Rate-Limit).
- Design driftet: ungetrimmte Referenz + Treue-Suffix betonen (oder mehrere Referenzen, Schritt 6b).
- API 429/5xx: Retry-Block in Schritt 6 faengt das ab; bei dauerhaftem Overload spaeter erneut.
- Composite leer/schwarz: Maske muss weiss-auf-schwarz sein (siehe Abschnitt Digital/UI); Screenshot-stddev nahe 0 = nicht gerendert.
- Mobile-Screenshot rechts abgeschnitten: NICHT `--window-size` fuer schmale Viewports (klemmt Fensterbreite), CDP `setDeviceMetricsOverride` mit `mobile:true` nutzen (Schritt A).
- `magick` fehlt: `brew install imagemagick`.

## Hinweise

- Modell-ID `google/gemini-3-pro-image` (Nano Banana Pro, GA-ID, kanonisch `-20260528`), 1K/2K/4K, OpenRouter. Preview-IDs (`-preview`) werden abgekuendigt, GA-IDs nicht.
- Digitales/UI-Design pixeltreu nur ueber den Composite-Pfad, nie ueber Nano Banana.
- Mehrere Referenzbilder (bis 14): siehe Schritt 6b.
- Ein Key deckt viele Bildmodelle ab. Runway separat fuer Video.
- Verwandt: `/produktbild` (Poster im Wohnraum, Shop), `/produktvideo` (Lifestyle-Video via Runway).
