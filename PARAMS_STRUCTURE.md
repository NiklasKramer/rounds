# Rounds - Parameter Structure

## Overview

The parameters are now organized into clear sections for better navigation and editing of all 4 tracks.

## Parameter Structure

```
ROUNDS
│
├── --- GLOBAL ---
│   └── Transport (3 params)
│       ├── Play/Stop
│       ├── Step Division
│       └── Playback Direction
│
├── --- MASTER FX ---
│   └── Delay (11 params)
│       ├── Mix
│       ├── Sync
│       ├── Subdivision Type
│       ├── Division
│       ├── Time (non-synced)
│       ├── Feedback
│       ├── Lowpass Frequency
│       ├── Highpass Frequency
│       ├── Wiggle Rate
│       ├── Wiggle Depth
│       └── Rotate
│
├── --- TRACKS ---
│   │
│   ├── TRACK 1
│   │   ├── T1 Global (4 params)
│   │   │   ├── Sample
│   │   │   ├── Steps
│   │   │   ├── Pattern
│   │   │   └── Semitones
│   │   │
│   │   ├── T1 Record (4 params)
│   │   │   ├── Record Mode On
│   │   │   ├── Record
│   │   │   ├── Arm Record
│   │   │   └── Loop in Beats
│   │   │
│   │   ├── T1 Envelope (7 params)
│   │   │   ├── Enable Envelope
│   │   │   ├── Attack Time
│   │   │   ├── Release Time
│   │   │   ├── Lowpass Frequency
│   │   │   ├── Resonance
│   │   │   ├── Highpass Frequency
│   │   │   └── Lowpass Env Strength
│   │   │
│   │   └── T1 Randomization (10 params)
│   │       ├── Randomize Octave
│   │       ├── Randomize Fifth
│   │       ├── Random Scale
│   │       ├── Randomize Pan
│   │       ├── Randomize Reverse
│   │       ├── Randomize Attack
│   │       ├── Randomize Release
│   │       ├── Randomize Amplitude
│   │       ├── Randomize Lowpass
│   │       └── Randomize Highpass
│   │
│   ├── TRACK 2 (Same structure as Track 1)
│   ├── TRACK 3 (Same structure as Track 1)
│   └── TRACK 4 (Same structure as Track 1)
│
├── --- STEPS ---
│   └── Steps 1-64
│       ├── active_N
│       ├── rate_N
│       ├── amp_N
│       ├── reverse_N
│       ├── pan_N
│       └── segment_N
│
└── --- ARC ---
    └── Arc (1 param)
        └── Sensitivity
```

## Parameter Naming Convention

Track-specific parameters use the prefix: `t{N}_` where N is 1-4

Examples:

- `t1_sample` - Track 1 sample
- `t2_attack` - Track 2 attack time
- `t3_random_pan` - Track 3 randomize pan
- `t4_semitones` - Track 4 semitones

## Helper Function

```lua
get_track_param(param_name, track)
```

Returns the full parameter name for a specific track:

- `param_name`: The base parameter name (without track prefix)
- `track`: Optional track index (0-3), defaults to `current_track`

Example:

```lua
-- Get attack parameter for current track
local attack = params:get(get_track_param("attack"))

-- Get semitones for track 2
local semitones = params:get(get_track_param("semitones", 1))
```

## Global vs Track-Specific

### Global Parameters

These affect the overall system or all tracks:

- Transport controls (play/stop, step division, direction)
- Master FX (delay - processes all 4 tracks)
- Arc sensitivity

### Track-Specific Parameters

Each track has independent:

- Sample/buffer selection
- Number of steps
- Pattern selection
- Pitch (semitones)
- Recording settings
- Envelope settings
- Filter settings
- Randomization settings

## Current Implementation Status

✅ All 4 tracks have independent parameter sets
✅ Parameters organized into logical groups
✅ Master FX section for global delay
✅ Helper function for accessing track params
⏳ UI still uses Track 1 (current_track = 0)
⏳ Need to update UI to allow track selection

## Next Steps

To make the multi-track system fully functional:

1. **Add Track Selection UI**

   - Add encoder or key combo to switch `current_track`
   - Update screen to show which track is selected
   - Update visual feedback for current track

2. **Update UI Param References**

   - Replace hardcoded param names with `get_track_param()` calls
   - Ensure all displays show current track's values

3. **Multi-Track Sequencing**
   - Option 1: Different track per step
   - Option 2: Different track per pattern
   - Option 3: Parallel playback of multiple tracks
