# rounds 1.2

**rounds** is a clocked sample manipulation environment for **monome norns**.

---

## Requirements

- **monome Norns**
- **Optional**: Arc for enhanced control
- **Optional**: Grid for step sequencing and pattern automation

## Installation

1. Go to **Maiden** (Norns' script manager).
2. In the **Maiden** REPL, type the following command:
   ```lua
   ;install https://github.com/NiklasKramer/rounds
   ```

---

## Overview

Rounds features **4 independent tracks**, each with its own:

- Sample playback and recording
- Step sequencer with patterns
- Envelope and filter controls
- Randomization parameters
- Pan and volume controls

All tracks share a **master delay effect** and sync to the global Norns clock.

**Additional Features:**
- **Pattern Recording**: Record parameter automation to 8 pattern slots
- **PSET Integration**: Recorded audio buffers are automatically saved/loaded with PSETs
- **Grid Support**: Visual step sequencing and piano keyboard for pitch control

---

## Controls

### Global Controls

- **Key 1**: Shift
- **Key 2**: Play/Stop current track
- **Key 2 + Shift**: Global Play/Stop (all tracks)
- **Enc 1**: Navigate sub-screens (within track/delay modes)
- **Enc 1 + Shift**: Switch between Tape, Tracks 1-4, and Delay

---

## Global Screens

Rounds has two global screens accessible via **Enc 1** (when in global mode):

### Tape Recorder

Record audio input for each track with beat-synced recording.

- **Enc 2**: Select track (1-4)
- **Enc 3**: Adjust recording buffer length (in beats, 1-64)
- **Key 2**: Toggle between record and sample mode
- **Key 3**: Start/stop recording
- **Key 3 + Shift**: Arm recording (starts when playback begins)

Recording automatically syncs to beat boundaries when playback is active.

### Tempo & Swing

Control the global tempo and add swing to all tracks.

- **Enc 2**: Adjust BPM (20-300)
- **Enc 3**: Adjust Swing (0-100%)
- **Key 3 + Shift**: Reset swing to 0%

Swing values above 50% delay off-beats for a shuffled feel. All parameter changes on this screen are recorded to pattern slots when pattern recording is active.

---

## Track Screens (1-4)

Each track has 5 sub-screens accessible via **Enc 1**:

### Screen 1: Sequencer

- **Enc 2**: Select Pattern
- **Enc 3**: Change Beat Division
- **Enc 2 + Shift**: Set Playback Direction
- **Enc 3 + Shift**: Set Steps (4-64)

- **Key 3**: Load Sample

**Grid Controls** (when Grid is connected):
- **Step Grid** (rows 2-7, centered columns): Toggle steps on/off
- **Shift + Step**: Toggle reverse playback for that step

### Screen 2: Envelope

- **Enc 2**: Attack
- **Enc 3**: Release
- **Enc 2 + Shift**: Randomize Attack
- **Enc 3 + Shift**: Randomize Release

### Screen 3: Pan & Volume

- **Enc 2**: Random Pan
- **Enc 3**: Random Volume
- **Enc 2 + Shift**: Pan
- **Enc 3 + Shift**: Volume

### Screen 4: Pitch

- **Enc 2**: Random Fifth
- **Enc 3**: Random Octave
- **Enc 2 + Shift**: Pitch in Semitones
- **Enc 3 + Shift**: Set Scale for Random Fifth
- **Key 2 + Shift**: Show current scale name

**Grid Controls** (when Grid is connected):
- **Piano Keyboard** (rows 2-3, columns 5-12): Play notes to set pitch
  - Row 3: White keys (C, D, E, F, G, A, B, C)
  - Row 2: Black keys (C#, D#, F#, G#, A#, C#)
- **Octave Selector** (row 5, columns 7-10): Select octave (-1, 0, +1, +2)
- Notes trigger preview playback and are recorded to pattern slots

### Screen 5: Filter

- **Enc 2**: Lowpass Frequency
- **Enc 3**: Resonance
- **Enc 2 + Shift**: Randomize Lowpass
- **Enc 3 + Shift**: Lowpass Envelope Strength

---

## Delay Screen (Master FX)

The delay affects all four tracks as a master effect.

- **Enc 2**: Delay Time (synced to clock) or Rate (free-running)
- **Enc 3**: Feedback
- **Enc 2 + Shift**: Mix
- **Enc 3 + Shift**: Rotate (stereo width)

- **Key 2**: Toggle delay sync on/off
- **Key 3**: Toggle between straight/dotted/triplet divisions

**Additional Parameters** (via params menu):
- **Lag Time**: Smoothing time for delay parameter changes (0.001-2.0s)
- **Lowpass/Highpass**: Frequency filtering for delay feedback
- **Wiggle Rate/Depth**: Modulation for delay time

---

## Arc Support

When an Arc is connected, it provides visual feedback and direct control:

- **Tape Screen**: Track selector, loop length, animated reels
- **Tempo Screen**: BPM and swing controls
- **Track Screens**: Pattern, division, direction, steps, and all parameters mapped to encoders
- **Delay Screen**: Time/division, feedback, mix, and rotate

**Arc Key Controls:**
- **Short Press**: Advance sub-screen for current track
- **Long Press**: Switch between main screen modes

---

## Grid Support

When a Grid is connected, it provides visual feedback and direct control:

### Grid Layout

**Column 1 (Left):**
- **Row 8**: Shift button (hold for secondary functions)
- **Rows 1-5**: Sub-screen indicators (active screen highlighted)

**Column 16 (Right):**
- **Row 1**: Tape/Global mode indicator
- **Rows 2-5**: Track 1-4 indicators
- **Row 6**: Delay mode indicator
- **Row 8**: All tracks play/stop indicator

**Row 8 (Bottom):**
- **Columns 5-12**: Pattern recording slots (8 slots)
  - **Bright**: Currently recording
  - **Medium Bright**: Pattern playing back
  - **Dim**: Pattern has data
  - **Very Dim**: Empty slot

### Pattern Recording (Automation)

Record parameter changes to 8 pattern slots for automation playback.

**Controls:**
- **Press empty slot** (columns 5-12, row 8): Start recording to that slot
- **Press recording slot**: Stop recording and save pattern
- **Press slot with data**: Toggle playback on/off
- **Shift + Press slot**: Clear pattern data

**What Gets Recorded:**
- All encoder parameter changes
- Track play/stop toggles
- Pitch changes (via encoders or grid piano)
- Tempo and swing changes
- Delay parameter changes

Patterns play back automatically, applying recorded parameter changes at their original timing.

### Grid Step Sequencing

On **Track Screen 1 (Sequencer)**:
- **Step Grid** (rows 2-7, centered): Visual representation of steps
  - **Press step**: Toggle step on/off
  - **Shift + Press step**: Toggle reverse playback
  - Active steps shown in bright, current step highlighted
  - Reversed steps shown with different brightness

### Grid Piano Keyboard

On **Track Screen 4 (Pitch)**:
- **Piano Layout** (rows 2-3, columns 5-12):
  - Row 3: White keys (C, D, E, F, G, A, B, C)
  - Row 2: Black keys (C#, D#, F#, G#, A#, C#)
- **Octave Selector** (row 5, columns 7-10): Choose octave (-1, 0, +1, +2)
- Pressing keys sets the track's pitch and triggers preview playback

---

## PSET Integration

Rounds automatically saves and loads recorded audio buffers with PSETs:

- **Saving a PSET**: All 4 tracks' recorded buffers are saved to `_path.audio/rounds/pset_{number}_track_{1-4}`
- **Loading a PSET**: Recorded buffers are automatically loaded when a PSET is loaded
- **Deleting a PSET**: Recorded buffer files are automatically deleted

**Note**: When loading a PSET, all tracks are stopped to prevent playback with unloaded buffers. Wait for the "PSET LOAD COMPLETE" message before playing.

---
