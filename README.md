# rounds 1.2

**rounds** is a clocked sample manipulation environment for **monome norns**.

---

## Requirements

- **monome Norns**
- **Optional**: Arc for enhanced control

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

Swing values above 50% delay off-beats for a shuffled feel.

---

## Track Screens (1-4)

Each track has 5 sub-screens accessible via **Enc 1**:

### Screen 1: Sequencer

- **Enc 2**: Select Pattern
- **Enc 3**: Change Beat Division
- **Enc 2 + Shift**: Set Playback Direction
- **Enc 3 + Shift**: Set Steps (4-64)

- **Key 3**: Load Sample

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

---

## Arc Support

When an Arc is connected, it provides visual feedback and direct control:

- **Tape Screen**: Track selector, loop length, animated reels
- **Tempo Screen**: BPM and swing controls
- **Track Screens**: Pattern, division, direction, steps, and all parameters mapped to encoders
- **Delay Screen**: Time/division, feedback, mix, and rotate

---
