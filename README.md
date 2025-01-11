# rounds

**rounds** is a clocked sample manipulation environment for **monome norns**.

---

## Requirements

- **monome Norns**

## Installation

1. Go to **Maiden** (Norns' script manager).
2. In the **Maiden** REPL, type the following command:
   ```lua
   ;install https://github.com/NiklasKramer/rounds
   ```

---

## Controls

### Key Functions

- **Key 1**: Shift
- **Key 2**: Play/Stop
- **Key 3**: Load Sample (on Voice Screen 1)

### Encoder Functions

- **Enc 1**: Change Voice Screen
- **Enc 1 + Shift**: Switch between Voice and FX screens

---

## Voice Screens

### Screen 1

- **Enc 2**: Select Pattern
- **Enc 3**: Change Beat Length
- **Enc 2 + Shift**: Set Playback Direction
- **Enc 3 + Shift**: Set Steps

### Screen 2

- **Enc 2**: Attack
- **Enc 3**: Release
- **Enc 2 + Shift**: Randomize Attack
- **Enc 3 + Shift**: Randomize Release

### Screen 3

- **Enc 2**: Random Pan
- **Enc 3**: Random Volume

### Screen 4

- **Enc 2**: Random Note
- **Enc 3**: Random Octave
- **Enc 2 + Shift**: Pitch in Semitones
- **Enc 3 + Shift**: Set Scale for Random Note   


### Screen 5

- **Enc 2**: Filter Frequency
- **Enc 3**: Filter Resonance
- **Enc 2 + Shift**: Randomize Filter Frequency
- **Enc 3 + Shift**: Filter Envelope Strength

---

## FX Screen

### Delay Screen

- **Enc 2**: Rate
- **Enc 3**: Feedback
- **Enc 2 + Shift**: Mix
- **Enc 3 + Shift**: Rotate

- **Button 2**: Toggle between delay sync/unsync.
- **Button 3**: Toggle between straight/dotted/thirds


## Record Screen

- **Enc 2**: Adjust recording buffer length (in beats)
  
- **Button 2**: Toggle between record and sample mode
- **Button 3**: Start/stop recording
- **Button 3 + Shift**: Arm recording (recording will start when playback begins, which allows to sync recording and playback )
