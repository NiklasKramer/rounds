# Rounds - Multi-Track UI Structure

## Overview

The UI now supports 4 independent tracks plus tape recording and master delay, with 6 modes total indicated on the right side of the screen.

## Screen Mode Structure

```
Right Indicator (6 modes):
┌─────────────┐
│  1. Tape    │  Records to Track 1
│  2. Track 1 │  ← 5 sub-screens (left indicator)
│  3. Track 2 │  ← 5 sub-screens (left indicator)
│  4. Track 3 │  ← 5 sub-screens (left indicator)
│  5. Track 4 │  ← 5 sub-screens (left indicator)
│  6. Delay   │  Master FX (affects all tracks)
└─────────────┘
```

## Mode Details

### Mode 1: Tape Recorder

- Records to Track 1 buffer
- Shows tape animation with spools
- Progress bar shows recording position
- No left indicator (single screen)

### Modes 2-5: Tracks 1-4

Each track has 5 sub-screens (shown via left indicator):

**Left Indicator (5 sub-screens):**

1. **Step Circle** - Pattern, steps, direction
2. **Envelope** - Attack, release, randomization
3. **Pan & Amp** - Random pan/amp visualization
4. **Fifth & Octave** - Scale, semitones, random pitch
5. **Filter** - Lowpass, resonance, env strength

### Mode 6: Delay (Master FX)

- Single screen showing delay visualization
- Affects audio from all 4 tracks
- No left indicator

## Navigation

### Encoder 1 (E1)

- **E1 (normal)**: Navigate sub-screens (only in track modes 2-5)
- **K1 + E1 (shift)**: Switch between main modes (1-6)

### Encoders 2 & 3 (E2, E3)

Context-dependent based on current mode and sub-screen

### Visual Feedback

- **Right Indicator**: Shows which mode (1-6) is active
- **Left Indicator**: Shows which sub-screen (1-5) is active (only for track modes)
- **Active track**: Automatically updates based on mode selection

## Track Selection Mapping

```
screen_mode  →  current_track  →  Display Name
─────────────────────────────────────────────
     1       →       0         →  "Tape" (uses Track 1)
     2       →       0         →  "Track 1"
     3       →       1         →  "Track 2"
     4       →       2         →  "Track 3"
     5       →       3         →  "Track 4"
     6       →       0*        →  "Delay" (master FX)

* Mode 6 keeps current_track at 0 but doesn't use it
```

## Auto-Switching Logic

When you switch modes, `current_track` automatically updates:

```lua
-- In redraw():
if screen_mode >= 2 and screen_mode <= 5 then
  current_track = screen_mode - 2
end
```

This means:

- All parameter reads/writes automatically target the correct track
- No need to manually update current_track
- Seamless switching between tracks via E1+shift

## Track-Specific vs Global Parameters

### Track-Specific (uses current_track)

All these use `get_track_param()`:

- Sample, Steps, Pattern, Semitones
- Recording settings
- Envelope (Attack, Release)
- Filter (Lowpass, Resonance, Highpass)
- All randomization parameters

### Global (same for all modes)

- Transport: Play/Stop
- Step Division
- Playback Direction
- Delay parameters (Master FX)
- Arc sensitivity

## Usage Example

**To edit Track 3's filter:**

1. Press K1 + turn E1 until mode indicator shows position 4 (Track 3)
2. Turn E1 (without K1) to navigate to sub-screen 5 (Filter)
3. Turn E2/E3 to adjust filter parameters
4. Parameters automatically save to Track 3

**To switch to Delay:**

1. Press K1 + turn E1 until mode indicator shows position 6
2. Adjust delay with E2/E3
3. Delay affects all 4 tracks as master FX

## Future Enhancements

Potential additions:

- Track name labels in UI
- Per-track mute/solo buttons
- Track activity indicators
- Copy/paste settings between tracks
- Track color coding
