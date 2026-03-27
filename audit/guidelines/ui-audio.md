# UI Audio Guidelines

## Audio Feedback

### 5.1 Visual Equivalent for Every Sound

Every audio cue must have a visual equivalent; sound never replaces visual feedback.

**Incorrect (sound without visual):**

```tsx
function SubmitButton({ onClick }) {
  const handleClick = () => {
    playSound("success");
    onClick();
  };
}
```

**Correct (sound with visual):**

```tsx
function SubmitButton({ onClick }) {
  const [status, setStatus] = useState("idle");

  const handleClick = () => {
    playSound("success");
    setStatus("success");
    onClick();
  };

  return <button data-status={status}>Submit</button>;
}
```

### 5.2 Toggle Setting to Disable Sounds

Provide explicit toggle to disable sounds in settings.

**Incorrect (no way to disable):**

```tsx
function App() {
  return <SoundProvider>{children}</SoundProvider>;
}
```

**Correct (toggle available):**

```tsx
function App() {
  const { soundEnabled } = usePreferences();
  return (
    <SoundProvider enabled={soundEnabled}>
      {children}
    </SoundProvider>
  );
}
```

### 5.3 Respect prefers-reduced-motion for Sound

Respect prefers-reduced-motion as proxy for sound sensitivity.

**Incorrect (ignores preference):**

```tsx
function playSound(name: string) {
  audio.play();
}
```

**Correct (checks preference):**

```tsx
function playSound(name: string) {
  const prefersReducedMotion = window.matchMedia(
    "(prefers-reduced-motion: reduce)"
  ).matches;

  if (prefersReducedMotion) return;
  audio.play();
}
```

### 5.4 Independent Volume Control

Allow volume adjustment independent of system volume.

**Incorrect (always full volume):**

```tsx
function playSound() {
  audio.volume = 1;
  audio.play();
}
```

**Correct (user-controlled volume):**

```tsx
function playSound() {
  const { volume } = usePreferences();
  audio.volume = volume;
  audio.play();
}
```

### 5.5 No Sound on High-Frequency Interactions

Do not add sound to high-frequency interactions (typing, keyboard navigation).

**Incorrect (sound on every keystroke):**

```tsx
function Input({ onChange }) {
  const handleChange = (e) => {
    playSound("keystroke");
    onChange(e);
  };
}
```

**Correct (no sound on typing):**

```tsx
function Input({ onChange }) {
  return <input onChange={onChange} />;
}
```

### 5.6 Sound for Confirmations

Sound is appropriate for confirmations: payments, uploads, form submissions.

**Correct:**

```tsx
async function handlePayment() {
  await processPayment();
  playSound("success");
  showConfirmation();
}
```

### 5.7 Sound for Errors and Warnings

Sound is appropriate for errors and warnings that can't be overlooked.

**Correct:**

```tsx
function handleError(error: Error) {
  playSound("error");
  showErrorToast(error.message);
}
```

### 5.8 No Decorative Sound

Do not add sound to decorative moments with no informational value.

**Incorrect (hover sound):**

```tsx
function Card({ onHover }) {
  return (
    <div onMouseEnter={() => playSound("hover")}>
      {children}
    </div>
  );
}
```

### 5.9 Informative Not Punishing Sound

Sound should inform, not punish; avoid harsh sounds for user mistakes.

**Incorrect (harsh buzzer):**

```tsx
function ValidationError() {
  playSound("loud-buzzer");
  return <span>Invalid input</span>;
}
```

**Correct (gentle alert):**

```tsx
function ValidationError() {
  playSound("gentle-alert");
  return <span>Invalid input</span>;
}
```

### 5.10 Preload Audio Files

Preload audio files to avoid playback delay.

**Incorrect (loads on demand):**

```tsx
function playSound(name: string) {
  const audio = new Audio(`/sounds/${name}.mp3`);
  audio.play();
}
```

**Correct (preloaded):**

```tsx
const sounds = {
  success: new Audio("/sounds/success.mp3"),
  error: new Audio("/sounds/error.mp3"),
};

Object.values(sounds).forEach(audio => audio.load());

function playSound(name: keyof typeof sounds) {
  sounds[name].currentTime = 0;
  sounds[name].play();
}
```

### 5.11 Subtle Default Volume

Default volume should be subtle, not loud.

**Incorrect (too loud):**

```tsx
const DEFAULT_VOLUME = 1.0;
```

**Correct (subtle):**

```tsx
const DEFAULT_VOLUME = 0.3;
```

### 5.12 Reset currentTime Before Replay

Reset audio currentTime before replay to allow rapid triggering.

**Incorrect (won't replay if playing):**

```tsx
function playSound() {
  audio.play();
}
```

**Correct (reset before play):**

```tsx
function playSound() {
  audio.currentTime = 0;
  audio.play();
}
```

### 5.13 Match Sound Weight to Action

Sound weight should match action importance.

**Incorrect (fanfare for toggle):**

```tsx
function handleToggle() {
  playSound("triumphant-fanfare");
  setEnabled(!enabled);
}
```

**Correct (weight matches action):**

```tsx
function handleToggle() {
  playSound("soft-click");
  setEnabled(!enabled);
}

function handlePurchase() {
  playSound("success-chime");
  completePurchase();
}
```

### 5.14 Sound Duration Matches Action Duration

Sound duration should match action duration.

**Incorrect (long sound for instant action):**

```tsx
function handleClick() {
  playSound("long-whoosh"); // 2000ms
}
```

**Correct (matched duration):**

```tsx
function handleClick() {
  playSound("click"); // 50ms
}

function handleUpload() {
  playSound("upload-progress"); // Matches upload duration
}
```

**Sound appropriateness matrix:**

| Interaction | Sound? | Reason |
|-------------|--------|--------|
| Payment success | Yes | Significant confirmation |
| Form submission | Yes | User needs assurance |
| Error state | Yes | Can't be overlooked |
| Notification | Yes | May not be looking at screen |
| Button click | Maybe | Only for significant buttons |
| Typing | No | Too frequent |
| Hover | No | Decorative only |
| Scroll | No | Too frequent |
| Navigation | No | Keyboard nav would be noisy |

---

## Sound Synthesis

### 6.1 Reuse Single AudioContext

Reuse a single AudioContext instance; do not create new ones per sound.

**Incorrect (new context per call):**

```ts
function playSound() {
  const ctx = new AudioContext();
}
```

**Correct (singleton):**

```ts
let audioContext: AudioContext | null = null;

function getAudioContext(): AudioContext {
  if (!audioContext) {
    audioContext = new AudioContext();
  }
  return audioContext;
}
```

### 6.2 Resume Suspended AudioContext

Check and resume suspended AudioContext before playing.

**Incorrect (plays without checking):**

```ts
function playSound() {
  const ctx = getAudioContext();
}
```

**Correct (resumes if suspended):**

```ts
function playSound() {
  const ctx = getAudioContext();
  if (ctx.state === "suspended") {
    ctx.resume();
  }
}
```

### 6.3 Clean Up Audio Nodes After Playback

Disconnect and clean up audio nodes after playback.

**Incorrect (nodes remain connected):**

```ts
source.start();
```

**Correct (cleaned up on end):**

```ts
source.start();
source.onended = () => {
  source.disconnect();
  gain.disconnect();
};
```

### 6.4 Exponential Decay for Natural Sound

Use exponential ramps for natural decay, not linear.

**Incorrect (linear ramp):**

```ts
gain.gain.linearRampToValueAtTime(0, t + 0.05);
```

**Correct (exponential ramp):**

```ts
gain.gain.exponentialRampToValueAtTime(0.001, t + 0.05);
```

### 6.5 No Zero Target for Exponential Ramps

Exponential ramps cannot target 0; use 0.001 or similar small value.

**Incorrect (targets zero):**

```ts
gain.gain.exponentialRampToValueAtTime(0, t + 0.05);
```

**Correct (targets near-zero):**

```ts
gain.gain.exponentialRampToValueAtTime(0.001, t + 0.05);
```

### 6.6 Set Initial Value Before Ramp

Set initial value before ramping to avoid glitches.

**Incorrect (no initial value):**

```ts
gain.gain.exponentialRampToValueAtTime(0.001, t + 0.05);
```

**Correct (initial value set):**

```ts
gain.gain.setValueAtTime(0.3, t);
gain.gain.exponentialRampToValueAtTime(0.001, t + 0.05);
```

### 6.7 Noise for Percussive Sounds

Use filtered noise for clicks/taps, not oscillators.

**Incorrect (oscillator for click):**

```ts
const osc = ctx.createOscillator();
osc.type = "sine";
```

**Correct (noise burst for click):**

```ts
const buffer = ctx.createBuffer(1, ctx.sampleRate * 0.008, ctx.sampleRate);
const data = buffer.getChannelData(0);
for (let i = 0; i < data.length; i++) {
  data[i] = (Math.random() * 2 - 1) * Math.exp(-i / 50);
}
```

### 6.8 Oscillators for Tonal Sounds

Use oscillators with pitch movement for tonal sounds (pops, confirmations).

**Incorrect (static frequency):**

```ts
osc.frequency.value = 400;
```

**Correct (pitch sweep):**

```ts
osc.frequency.setValueAtTime(400, t);
osc.frequency.exponentialRampToValueAtTime(600, t + 0.04);
```

### 6.9 Bandpass Filter for Sound Character

Apply bandpass filter to shape percussive sounds.

**Incorrect (raw noise):**

```ts
source.connect(gain).connect(ctx.destination);
```

**Correct (filtered noise):**

```ts
const filter = ctx.createBiquadFilter();
filter.type = "bandpass";
filter.frequency.value = 4000;
filter.Q.value = 3;
source.connect(filter).connect(gain).connect(ctx.destination);
```

### 6.10 Click Duration 5-15ms

Click/tap sounds should be 5-15ms duration.

**Incorrect (too long):**

```ts
const buffer = ctx.createBuffer(1, ctx.sampleRate * 0.1, ctx.sampleRate);
```

**Correct (appropriate duration):**

```ts
const buffer = ctx.createBuffer(1, ctx.sampleRate * 0.008, ctx.sampleRate);
```

### 6.11 Click Filter 3000-6000Hz

Bandpass filter for clicks should be 3000-6000Hz.

**Incorrect (too low):**

```ts
filter.frequency.value = 500;
```

**Correct (crisp range):**

```ts
filter.frequency.value = 4000;
```

### 6.12 Gain Under 1.0

Gain values should not exceed 1.0 to prevent clipping.

**Incorrect (clipping):**

```ts
gain.gain.setValueAtTime(1.5, t);
```

**Correct (safe gain):**

```ts
gain.gain.setValueAtTime(0.3, t);
```

### 6.13 Filter Q Value 2-5

Filter Q for clicks should be 2-5 for focused but not harsh sound.

**Incorrect (too resonant):**

```ts
filter.Q.value = 15;
```

**Correct (balanced Q):**

```ts
filter.Q.value = 3;
```

**Parameter translation table:**

| User Says | Parameter Change |
|-----------|------------------|
| "too harsh" | Lower filter frequency, reduce Q |
| "too muffled" | Higher filter frequency |
| "too long" | Shorter duration, faster decay |
| "cuts off abruptly" | Use exponential decay |
| "more mechanical" | Higher Q, faster decay |
| "softer" | Lower gain, triangle wave |
