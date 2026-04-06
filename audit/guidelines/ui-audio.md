# UI Audio Guidelines

## When to Use Audio Feedback

| Interaction | Sound? | Reason |
|---|---|---|
| Payment success | Yes | Significant confirmation |
| Form submission | Yes | User needs assurance |
| Error state | Yes | Must not be overlooked |
| Notification | Yes | User may not be looking at screen |
| Significant button | Maybe | Only if action warrants it |
| Typing / keystrokes | No | Too frequent |
| Hover | No | Decorative only |
| Scroll | No | Too frequent |
| Keyboard navigation | No | Would be noisy |

## Accessibility Rules

- Every audio cue MUST have a visual equivalent — sound never replaces visual feedback
- Provide an explicit toggle setting to disable all sounds
- Respect `prefers-reduced-motion: reduce` as a proxy for sound sensitivity — skip playback when set
- Provide independent volume control (not tied to system volume)
- Default volume must be subtle (around 0.3), never 1.0

## Sound Design Rules

- No sound on high-frequency interactions (typing, scrolling, hovering, keyboard nav)
- No decorative sound — every sound must carry informational value
- No auto-play audio without user interaction
- Sound should inform, not punish — use gentle alerts for errors, never harsh buzzers
- Sound weight must match action importance (soft click for toggle, chime for purchase)
- Sound duration must match action duration (50ms for a click, longer for uploads)

## Implementation Checks

- Audio files are preloaded at init, not created on demand per play
- `currentTime` is reset to 0 before replay to allow rapid retriering
- Single `AudioContext` instance is reused, not created per sound
- `AudioContext` state is checked and resumed if suspended before playback
- Audio nodes are disconnected and cleaned up after playback ends
- Gain values never exceed 1.0 (prevents clipping)

## Anti-Patterns to Flag

| Anti-Pattern | What to Look For |
|---|---|
| Sound without visual | `playSound()` call with no corresponding state change or UI update |
| No disable option | Sound provider/context without an `enabled` / `soundEnabled` toggle |
| Ignores reduced-motion | `playSound()` without checking `prefers-reduced-motion` |
| Hardcoded full volume | `audio.volume = 1` or `DEFAULT_VOLUME = 1.0` |
| Sound on every keystroke | `playSound()` inside `onChange` / `onKeyDown` of text inputs |
| Hover sound | `playSound()` inside `onMouseEnter` / `onMouseOver` |
| Audio loaded on demand | `new Audio(src)` created inside a play function instead of preloaded |
| No currentTime reset | `audio.play()` without setting `currentTime = 0` first |
| Multiple AudioContexts | `new AudioContext()` inside a play function instead of singleton |
| Gain over 1.0 | `gain.gain.setValueAtTime` with value > 1.0 |
| Disproportionate sound | Fanfare/triumphant sound for trivial actions (toggles, minor clicks) |
| Long sound, instant action | Sound duration significantly exceeds action duration |

## Code Review Checklist

- [ ] Every `playSound()` call has a corresponding visual state change
- [ ] A user-facing toggle exists to disable all sounds
- [ ] `prefers-reduced-motion` is checked before any sound playback
- [ ] Volume is user-controllable and defaults to a subtle level
- [ ] No sound is attached to typing, hover, scroll, or keyboard navigation
- [ ] All audio files are preloaded, not created on demand
- [ ] `currentTime` is reset before replay
- [ ] AudioContext is a singleton and resumed when suspended
- [ ] Audio nodes are cleaned up after playback
- [ ] No gain value exceeds 1.0
- [ ] Sound weight and duration are proportional to action importance
- [ ] Error sounds are gentle and informative, not harsh or punishing
