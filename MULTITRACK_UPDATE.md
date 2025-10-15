# Multi-Track Update Summary

## Overview

Extended the Rounds engine to support 4 independent tracks while maintaining backward compatibility. The app currently uses Track 1 by default and works exactly as before, but now has the infrastructure to support 3 additional tracks.

## SuperCollider Engine Changes (`lib/Engine_Rounds.sc`)

### New Architecture

- **4 Independent Tracks**: Each track has its own set of buffers and parameters
- **Master Delay Effect**: Single delay effect processes audio from all 4 tracks (via `delayBus`)
- **Track-Indexed Parameters**: All commands now accept a track index (0-3) as the first parameter

### Data Structures

All track-specific data is now stored in arrays indexed by track number (0-3):

#### Buffers (per track)

- `buffers[i]` - Left channel sample buffers
- `buffersR[i]` - Right channel sample buffers
- `recordBuffers[i]` - Left channel record buffers
- `recordBuffersR[i]` - Right channel record buffers
- `recorders[i]` - Recorder synths
- `recorderPosses[i]` - Recorder position buses

#### State (per track)

- `paths[i]` - File paths
- `sampleOrRecords[i]` - Sample or record mode
- `numSegmentsList[i]` - Number of segments/steps
- `segmentLengths[i]` - Segment lengths
- `loopLengths[i]` - Loop lengths

#### Parameters (per track)

- `semitonesList[i]` - Pitch shift
- `lowpassFreqs[i]`, `resonances[i]`, `hipassFreqs[i]` - Filter parameters
- `attacks[i]`, `releases[i]`, `useEnvs[i]` - Envelope parameters
- `lowpassEnvStrengths[i]`, `hipassEnvStrengths[i]` - Filter envelope strengths
- `randomOctaves[i]`, `randomPans[i]`, `randomAmps[i]` - Randomization parameters
- `randomLowPasses[i]`, `randomHiPasses[i]`, `randomFiths[i]`
- `randomReverses[i]`, `randomAttacks[i]`, `randomReleases[i]`

### Command Changes

All track-specific commands now require a track index as the first parameter:

**Before:**

```supercollider
engine.bufferPath("path/to/file.wav")
engine.semitones(5)
engine.play(1, 0.8, 1.0, 0.0, 0)
```

**After:**

```supercollider
engine.bufferPath(0, "path/to/file.wav")  // Track 0 (Track 1)
engine.semitones(0, 5)
engine.play(0, 1, 0.8, 1.0, 0.0, 0)
```

### Global (Non-Track-Specific) Commands

These delay commands remain global and affect all tracks:

- `engine.delay(time)`
- `engine.time(feedback)`
- `engine.hpf(freq)`
- `engine.lpf(freq)`
- `engine.w_rate(rate)`
- `engine.w_depth(depth)`
- `engine.rotate(amount)`
- `engine.mix(amount)`
- `engine.lagTime(time)`

## Lua Script Changes (`rounds.lua`)

### New Variables

```lua
local current_track = 0  -- 0-indexed (0 = track 1, 1 = track 2, etc.)
local num_tracks = 4
```

### Updated Engine Calls

All engine calls that were track-specific now pass `current_track` as the first parameter:

```lua
-- Examples:
engine.bufferPath(current_track, file)
engine.semitones(current_track, value)
engine.steps(current_track, value)
engine.attack(current_track, value)
engine.release(current_track, value)
engine.randomOctave(current_track, value)
engine.play(current_track, start_segment, amp, rate, pan, reverse)
engine.record(current_track, 1)
engine.loopLength(current_track, loop_length)
```

### Removed Obsolete Calls

- Removed `engine.active(i, value)` call (step activation is handled purely in Lua)

## Current Behavior

- App uses **Track 0** (Track 1) for all operations
- All functionality remains identical to the single-track version
- Delay effect processes audio from all tracks globally

## Future Extensions

To add track switching or multi-track functionality:

### Option 1: Track Selector

```lua
-- Add UI to switch current_track
function switch_track(track_num)
  current_track = util.clamp(track_num, 0, num_tracks - 1)
  -- Optionally reload params for the selected track
end
```

### Option 2: Multi-Track Sequencer

```lua
-- Play different tracks on different steps
function start_sequence()
  -- ... existing code ...
  local track_for_step = step_pattern[index]  -- User-defined pattern
  engine.play(track_for_step, start_segment, amp, rate, pan, reverse)
end
```

### Option 3: Track Per Pattern

```lua
-- Each of 4 patterns uses a different track
local pattern_to_track_map = {0, 1, 2, 3}
local track = pattern_to_track_map[params:get("pattern")]
engine.play(track, start_segment, amp, rate, pan, reverse)
```

## Testing Checklist

- [x] SC engine allocates 4 tracks worth of buffers
- [x] SC commands accept track parameter
- [x] Lua passes current_track (0) to all engine calls
- [x] Delay works as master effect
- [ ] Load and play a sample on track 0
- [ ] Record and playback on track 0
- [ ] Test all randomization parameters
- [ ] Test envelope and filter parameters
- [ ] Verify delay affects playback

## Notes

- The delay is intentionally global - it's a master effect that all 4 tracks route through
- Track indices are 0-based in the engine (0, 1, 2, 3 for tracks 1-4)
- Each track has completely independent parameters and buffers
- Memory usage increased ~4x due to 4 sets of buffers
