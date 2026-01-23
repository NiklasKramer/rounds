Engine_Rounds : CroneEngine {
    var pg, delayBus, warpDelay, fade = 0.1, trigBus;
    
    // Arrays for 4 tracks
    var <buffers, <buffersR, <recordBuffers, <recordBuffersR;
    var <recorders, <recorderPosses;
    var <paths, <sampleOrRecords, <numSegmentsList, <segmentLengths, <loopLengths;
    
    // Track-specific parameters (arrays indexed by track)
    var <semitonesList, <lowpassFreqs, <resonances, <hipassFreqs;
    var <attacks, <releases, <useEnvs, <lowpassEnvStrengths, <hipassEnvStrengths;
    var <randomOctaves, <randomPans, <randomAmps, <randomLowPasses, <randomHiPasses;
    var <randomFiths, <randomReverses, <randomAttacks, <randomReleases;
    
    var numTracks = 4;

    *new { arg context, doneCallback;
        ^super.new(context, doneCallback);
    }

    // Load a buffer for a specific track
    loadBuffer { arg trackIndex;
        var path = paths[trackIndex];
        
        // Check if the file exists
        if (File.exists(path), {
            buffers[trackIndex].do(_.free);  // Free the existing buffer if it exists

            Buffer.read(context.server, path, 0, 1, { |tempBuffer|
                (tempBuffer.numChannels == 1).if({
                    // Mono file
                    Buffer.readChannel(context.server, path, 0, -1, [0], { |newBuffer|
                        buffers[trackIndex] = newBuffer;  // Store buffer
                        buffersR[trackIndex] = newBuffer;  // Store buffer
                        loopLengths[trackIndex] = buffers[trackIndex].duration;
                        segmentLengths[trackIndex] = buffers[trackIndex].duration / numSegmentsList[trackIndex];
                        "Track %: Buffer loaded. Segment length: %".format(trackIndex + 1, segmentLengths[trackIndex]).postln;
                    });
                }, {
                    // Stereo file
                    (tempBuffer.numChannels == 2).if({
                        buffers[trackIndex] = Buffer.readChannel(context.server, path, 0, -1, [0], { |newBufferL|
                            segmentLengths[trackIndex] = newBufferL.duration / numSegmentsList[trackIndex];
                            buffers[trackIndex] = newBufferL;
                            loopLengths[trackIndex] = buffers[trackIndex].duration;
                            "Track %: Stereo buffer (left) loaded. Segment length: %".format(trackIndex + 1, segmentLengths[trackIndex]).postln;
                        });
                        buffersR[trackIndex] = Buffer.readChannel(context.server, path, 0, -1, [1], { |newBufferR|
                            "Track %: Stereo buffer (right) loaded.".format(trackIndex + 1).postln;
                            buffersR[trackIndex] = newBufferR;
                        });
                    });
                });
            });
        }, {
            "Track %: File not found: %".format(trackIndex + 1, path).postln;
        });
    }

    alloc {
        // Initialize arrays for 4 tracks
        buffers = Array.newClear(numTracks);
        buffersR = Array.newClear(numTracks);
        recordBuffers = Array.newClear(numTracks);
        recordBuffersR = Array.newClear(numTracks);
        recorders = Array.newClear(numTracks);
        recorderPosses = Array.newClear(numTracks);
        
        paths = Array.fill(numTracks, { "" });
        sampleOrRecords = Array.fill(numTracks, { 0 });
        numSegmentsList = Array.fill(numTracks, { 16 });
        segmentLengths = Array.fill(numTracks, { 0 });
        loopLengths = Array.fill(numTracks, { 180 });
        
        // Initialize parameter arrays
        semitonesList = Array.fill(numTracks, { 0 });
        lowpassFreqs = Array.fill(numTracks, { 20000 });
        resonances = Array.fill(numTracks, { 1 });
        hipassFreqs = Array.fill(numTracks, { 1 });
        attacks = Array.fill(numTracks, { 0.01 });
        releases = Array.fill(numTracks, { 0.5 });
        useEnvs = Array.fill(numTracks, { 1 });
        lowpassEnvStrengths = Array.fill(numTracks, { 0 });
        hipassEnvStrengths = Array.fill(numTracks, { 0 });
        
        randomOctaves = Array.fill(numTracks, { 0 });
        randomPans = Array.fill(numTracks, { 0 });
        randomAmps = Array.fill(numTracks, { 0 });
        randomLowPasses = Array.fill(numTracks, { 0 });
        randomHiPasses = Array.fill(numTracks, { 0 });
        randomFiths = Array.fill(numTracks, { 0 });
        randomReverses = Array.fill(numTracks, { 0 });
        randomAttacks = Array.fill(numTracks, { 0 });
        randomReleases = Array.fill(numTracks, { 0 });
        
        // Allocate buffers for each track
        numTracks.do { |i|
            buffers[i] = Buffer.alloc(context.server, context.server.sampleRate * 2, 1);
            buffersR[i] = Buffer.alloc(context.server, context.server.sampleRate * 2, 1);
            recordBuffers[i] = Buffer.alloc(context.server, context.server.sampleRate * loopLengths[i], 1);
            recordBuffersR[i] = Buffer.alloc(context.server, context.server.sampleRate * loopLengths[i], 1);
            recorderPosses[i] = Bus.control(context.server, 1);
        };

        // Simple buffer synth (unchanged - works for any track)
        SynthDef(\simpleBufferSynth, {
            |bufnumL, bufnumR, startSegment = 0, endSegment = 1, numSegments = 8, amp = 0.5, rate = 1, reverse = 0, pan = 0, lowpassFreq = 20000, resonance = 1, hipassFreq = 1,
            out, trig = 0, fade = 0.005, vol = 1, attack = 0.01, release = 0.5, lowpassEnvStrength = 0, hipassEnvStrength = 0,
            ampLag = 0.1, rateLag = 0.0, panLag = 0.1, trigIn, useEnv = 1, sampleOrRecord = 0, loopLength = 1|

            var segmentSize, bufplay, bufplayL, bufplayR, phase, gate, phasorStart, phasorEnd, phasorEndRev, start, end, envGen, percEnvGen, fadeEnvGen, lpEnvGen, hpEnvGen, loopLengthInFrames, bufferOrLoopLengthFrames;

            // Determine segment size based on mode
            segmentSize = Select.kr(sampleOrRecord, [
                BufDur.kr(bufnumL) / numSegments,  // Sample mode: use buffer duration
                loopLength / numSegments          // Record mode: use loopLength
            ]);

            loopLengthInFrames = loopLength * SampleRate.ir;

            bufferOrLoopLengthFrames = Select.kr(sampleOrRecord, [
                BufFrames.kr(bufnumL),             // Sample mode: use buffer frames
                loopLengthInFrames        // Record mode: use loopLength in frames
            ]);

            // Calculate phasor start and end points
            phasorStart = startSegment / numSegments * Select.kr(sampleOrRecord, [
                BufFrames.kr(bufnumL),             // Sample mode: use buffer frames
                loopLengthInFrames        // Record mode: use loopLength in frames
            ]);

            phasorEndRev = (startSegment + 1) / numSegments * Select.kr(sampleOrRecord, [
                BufFrames.kr(bufnumL),             // Sample mode: use buffer frames
                loopLengthInFrames        // Record mode: use loopLength in frames
            ]);

            phasorEnd = Select.kr(sampleOrRecord, [
                BufFrames.kr(bufnumL),             // Sample mode: use buffer frames
                loopLengthInFrames        // Record mode: use loopLength in frames
            ]);

            // Determine start and end based on reverse flag
            end = Select.kr(reverse, [phasorEnd, phasorEndRev]);
            start = Select.kr(reverse, [phasorStart, 0]);

            rate = rate * (1 - (reverse * 2));
            rate = Lag.kr(rate, rateLag);

            // Phasor for playback
            phase = Phasor.ar(
                trig: Impulse.ar(0),
                rate: rate * BufRateScale.kr(bufnumL),
                start: start,
                end: end,
                resetPos: phasorStart
            );

            // Read from buffer
            bufplayL = BufRd.ar(1, bufnumL, phase, loop: 0);
            bufplayR = BufRd.ar(1, bufnumR, phase, loop: 0);

            amp = Lag.kr(amp, ampLag);
            pan = Lag.kr(pan, panLag);
            gate = Impulse.ar(0);

            // Main amplitude envelope
            percEnvGen = EnvGen.ar(Env.perc((attack + fade), release), gate: gate, doneAction: Done.freeSelf);

            // Envelope modulating low-pass filter
            lpEnvGen = EnvGen.ar(Env.perc(attack, release), gate: gate) * lowpassEnvStrength;
            lowpassFreq = lowpassFreq + (lpEnvGen * (20000 - lowpassFreq));

            // Envelope modulating high-pass filter
            hpEnvGen = EnvGen.ar(Env.perc(attack, release), gate: gate) * hipassEnvStrength;
            hipassFreq = hipassFreq + (hpEnvGen * (hipassFreq - 1));

            // Apply filters
            bufplayL = RLPF.ar(bufplayL, lowpassFreq.clip(1, 20000), resonance);
            bufplayR = RLPF.ar(bufplayR, lowpassFreq.clip(1, 20000), resonance);
            bufplayL = RHPF.ar(bufplayL, hipassFreq.clip(1, 20000));
            bufplayR = RHPF.ar(bufplayR, hipassFreq.clip(1, 20000));

            // Balance channels
            bufplay = Balance2.ar(bufplayL, bufplayR, pan);

            fadeEnvGen = EnvGen.ar(Env.new([0, 1, 1, 0], [fade, segmentSize - (2 * fade), fade]), gate: gate, doneAction: Done.freeSelf);
            envGen = Select.ar(useEnv, [fadeEnvGen, percEnvGen]);

            // Output
            Out.ar(out, bufplay * amp * vol * envGen);
        }).add;

        SynthDef(\warpDelay, { |out=0, in=32, delay=0.2, time=10, hpf=330, lpf=8200, w_rate=0.667, w_depth=0.00027, rotate=0.0, mix=0.2, i_max_del=8, lagTime=0.1|
            var inputSignal, modulation, delayedSignal ,feedbackSignal, feedback, smoothedDelay, smoothedTime;

            inputSignal = In.ar(in, 2); // Input from bus

            smoothedDelay = Lag.kr(delay, lagTime);
            smoothedTime = Lag.kr(time, lagTime);

            feedback = exp(log(0.001) * (smoothedDelay / smoothedTime));
            modulation = LFPar.kr(w_rate, mul: w_depth);

            feedbackSignal = LocalIn.ar(2);
            feedbackSignal = Rotate2.ar(feedbackSignal[0], feedbackSignal[1], rotate).softclip;

            delayedSignal = DelayL.ar(Limiter.ar(Mix([feedbackSignal * feedback, inputSignal]), 0.99, 0.01), i_max_del, smoothedDelay + modulation);
            delayedSignal = LPF.ar(HPF.ar(delayedSignal, hpf), lpf);

            LocalOut.ar(delayedSignal);

            Out.ar(out, Limiter.ar(1 - mix * inputSignal + (mix * delayedSignal), 0.99, 0.01));
        }).add;

        SynthDef(\continuousRecorder, {
            |bufnumL, bufnumR, rate = 1, inputBus = 0, loop = 1, isRecording = 0, out = 0, phase_out = 0, loopLength = 1|
            var signalL, signalR, pos, endFrame, existingLeft, existingRight, mixedLeft, mixedRight;

            // Capture stereo input
            signalL = SoundIn.ar(inputBus);
            signalR = SoundIn.ar(inputBus + 1);

            // Calculate end frame based on loopLength
            endFrame = loopLength * SampleRate.ir;

            // Create a position Phasor that wraps within the loopLength
            pos = Phasor.ar(
                trig: isRecording,
                rate: rate * BufRateScale.kr(bufnumL),
                start: 0,
                end: endFrame,
                resetPos: 0
            );

            // Read existing audio from the buffer
            existingLeft = BufRd.ar(1, bufnumL, pos, loop: loop);
            existingRight = BufRd.ar(1, bufnumR, pos, loop: loop);

            // Mix the existing audio with the incoming signal
            mixedLeft = ((existingLeft * (1 - isRecording)) + (signalL * isRecording));
            mixedRight = ((existingRight * (1 - isRecording)) + (signalR * isRecording));

            // Write audio to the buffer only if recording is active
            BufWr.ar(mixedLeft, bufnumL, pos, loop: loop); 
            BufWr.ar(mixedRight, bufnumR, pos, loop: loop);

            // Output normalized position
            Out.kr(phase_out, pos / endFrame);
        }).add;

        context.server.sync;

        // ParGroup for handling voices
        pg = ParGroup.head(context.xg);

        trigBus = Bus.control(context.server, 1);
        delayBus = Bus.audio(context.server, 2);

        // Create recorder for each track
        numTracks.do { |i|
            recorders[i] = Synth.new(\continuousRecorder, [
                \bufnumL, recordBuffers[i],
                \bufnumR, recordBuffersR[i],
                \inputBus, 0,
                \loop, 1,
                \out, context.out_b.index,
                \phase_out, recorderPosses[i],
            ], target: context.xg);
        };

        warpDelay = Synth.new(\warpDelay, [
            \in, delayBus, 
            \out, context.out_b.index, 
            \delay, 0.2, 
            \time, 10,
            \hpf, 330,
            \lpf, 8200,
            \w_rate, 0.667,
            \w_depth, 0.00027,
            \rotate, 0.0,
            \mix, 0.2,
        ], target: context.xg);

        context.server.sync;

        // ============================================================
        // Commands - now all accept track index
        // ============================================================

        this.addCommand(\bufferPath, "is", { |msg|
            var trackIndex = msg[1];
            var path = msg[2];
            paths[trackIndex] = path;
            this.loadBuffer(trackIndex);
            if (buffers[trackIndex].notNil and: { buffers[trackIndex].numFrames > 0 }) {
                segmentLengths[trackIndex] = buffers[trackIndex].duration / numSegmentsList[trackIndex];
                "Track %: Segment length updated: %".format(trackIndex + 1, segmentLengths[trackIndex]).postln;
            } {
                "Track %: Buffer not loaded correctly or file not found.".format(trackIndex + 1).postln;
            }
        });

        this.addCommand(\vol, "f", { |msg|
            var vol = msg[1];
        });

        this.addCommand(\semitones, "if", { |msg|
            var trackIndex = msg[1];
            semitonesList[trackIndex] = msg[2];
        });

        this.addCommand(\lowpassFreq, "if", { |msg|
            var trackIndex = msg[1];
            lowpassFreqs[trackIndex] = msg[2];
        });

        this.addCommand(\highpassFreq, "if", { |msg|
            var trackIndex = msg[1];
            hipassFreqs[trackIndex] = msg[2];
        });

        this.addCommand(\resonance, "if", { |msg|
            var trackIndex = msg[1];
            resonances[trackIndex] = msg[2];
        });

        this.addCommand(\attack, "if", { |msg|
            var trackIndex = msg[1];
            attacks[trackIndex] = msg[2];
        });

        this.addCommand(\release, "if", { |msg|
            var trackIndex = msg[1];
            releases[trackIndex] = msg[2];
        });

        this.addCommand(\useEnv, "if", { |msg|
            var trackIndex = msg[1];
            useEnvs[trackIndex] = msg[2];
        });

        this.addCommand(\steps, "ii", { |msg|
            var trackIndex = msg[1];
            var newNumSteps = msg[2];
            numSegmentsList[trackIndex] = newNumSteps;
            segmentLengths[trackIndex] = buffers[trackIndex].duration / numSegmentsList[trackIndex];
        });

        // Random parameters
        this.addCommand(\randomOctave, "if", { |msg|
            var trackIndex = msg[1];
            randomOctaves[trackIndex] = msg[2];
        });

        this.addCommand(\randomPan, "if", { |msg|
            var trackIndex = msg[1];
            randomPans[trackIndex] = msg[2];
        });

        this.addCommand(\randomAmp, "if", { |msg|
            var trackIndex = msg[1];
            randomAmps[trackIndex] = msg[2];
        });

        this.addCommand(\randomFith, "if", { |msg|
            var trackIndex = msg[1];
            randomFiths[trackIndex] = msg[2];
        });

        this.addCommand(\randomReverse, "if", { |msg|
            var trackIndex = msg[1];
            randomReverses[trackIndex] = msg[2];
        });

        this.addCommand(\randomAttack, "if", { |msg|
            var trackIndex = msg[1];
            randomAttacks[trackIndex] = msg[2];
        });

        this.addCommand(\randomRelease, "if", { |msg|
            var trackIndex = msg[1];
            randomReleases[trackIndex] = msg[2];
        });

        this.addCommand(\randomLowPass, "if", { |msg|
            var trackIndex = msg[1];
            randomLowPasses[trackIndex] = msg[2];
        });

        this.addCommand(\randomHiPass, "if", { |msg|
            var trackIndex = msg[1];
            randomHiPasses[trackIndex] = msg[2];
        });

        this.addCommand(\lowpassEnvStrength, "if", { |msg|
            var trackIndex = msg[1];
            lowpassEnvStrengths[trackIndex] = msg[2];
        });

        this.addCommand(\hipassEnvStrength, "if", { |msg|
            var trackIndex = msg[1];
            hipassEnvStrengths[trackIndex] = msg[2];
        });

        this.addCommand(\play, "iifffi", { |msg|
            var trackIndex = msg[1];
            var startSegment = msg[2] - 1;
            var amp = msg[3] + (rrand(-1, 1) * randomAmps[trackIndex]);
            var pan = msg[5] + (rrand(-1, 1) * randomPans[trackIndex]);
            var reverse = wchoose([msg[6], 1], [1 - randomReverses[trackIndex], randomReverses[trackIndex]]);
            var rate = msg[4];

            var attackR = attacks[trackIndex] + (rrand(0.001, 1) * randomAttacks[trackIndex]);
            var releaseR = releases[trackIndex] + (rrand(0.001, 3) * randomReleases[trackIndex]);

            var stepRate = msg[4] * (2 ** (semitonesList[trackIndex] / 12));
            var lowpassFreqFactor = lowpassFreqs[trackIndex] + (rrand(-1, 1) * randomLowPasses[trackIndex] * 10000);
            var hipassFreqFactor = hipassFreqs[trackIndex] + (rrand(-1, 1) * randomHiPasses[trackIndex] * 10000);

            var selectedBufferL = if(sampleOrRecords[trackIndex] == 0, { buffers[trackIndex] }, { recordBuffers[trackIndex] });
            var selectedBufferR = if(sampleOrRecords[trackIndex] == 0, { buffersR[trackIndex] }, { recordBuffersR[trackIndex] });

            Synth.new(\simpleBufferSynth, [
                \bufnumL, selectedBufferL.bufnum,
                \bufnumR, selectedBufferR.bufnum,
                \startSegment, startSegment,
                \endSegment, startSegment + 1,
                \numSegments, numSegmentsList[trackIndex],
                \amp, amp.clip(0, 3),
                \rate, rate,
                \pan, pan,
                \out, delayBus,
                \trigIn, trigBus.index,
                \useEnv, useEnvs[trackIndex],
                \attack, attackR,
                \release, releaseR,
                \reverse, reverse,
                \lowpassFreq, lowpassFreqFactor.clip(1, 20000),
                \hipassFreq, hipassFreqFactor.clip(1, 20000),
                \lowpassEnvStrength, lowpassEnvStrengths[trackIndex],
                \hipassEnvStrength, hipassEnvStrengths[trackIndex],
                \resonance, resonances[trackIndex],
                \loopLength, loopLengths[trackIndex],
                \sampleOrRecord, sampleOrRecords[trackIndex],
                \vol, 1,
            ], target: context.xg);
        });

        this.addCommand(\sampleOrRecord, "ii", { |msg|
            var trackIndex = msg[1];
            sampleOrRecords[trackIndex] = msg[2];
            if (sampleOrRecords[trackIndex] == 0) {
                "Track %: Sample mode".format(trackIndex + 1).postln;
                segmentLengths[trackIndex] = buffers[trackIndex].duration / numSegmentsList[trackIndex];
            } {
                "Track %: Record mode".format(trackIndex + 1).postln;
                segmentLengths[trackIndex] = loopLengths[trackIndex] / numSegmentsList[trackIndex];
            }
        });

        this.addCommand(\record, "if", { |msg|
            var trackIndex = msg[1];
            var isRecording = msg[2];
            recorders[trackIndex].set(\isRecording, isRecording);
            if (sampleOrRecords[trackIndex] == 1) {
                segmentLengths[trackIndex] = loopLengths[trackIndex] / numSegmentsList[trackIndex];
            }
        });
        
        this.addCommand(\loopLength, "if", { |msg|
            var trackIndex = msg[1];
            loopLengths[trackIndex] = msg[2];
            recorders[trackIndex].set(\loopLength, loopLengths[trackIndex]);
            segmentLengths[trackIndex] = loopLengths[trackIndex] / numSegmentsList[trackIndex];
        });

        this.addPoll(\recorderPos, { 
            recorderPosses[0].getSynchronous;  // Currently returns track 0 position
        });

        // Delay Commands (global, not per-track)
        this.addCommand(\delay, "f", { |msg|
            warpDelay.set(\delay, msg[1]);
        });

        this.addCommand(\time, "f", { |msg|
            warpDelay.set(\time, msg[1]);
        });

        this.addCommand(\hpf, "f", { |msg|
            warpDelay.set(\hpf, msg[1]);
        });

        this.addCommand(\lpf, "f", { |msg|
            warpDelay.set(\lpf, msg[1]);
        });

        this.addCommand(\w_rate, "f", { |msg|
            warpDelay.set(\w_rate, msg[1]);
        });

        this.addCommand(\w_depth, "f", { |msg|
            warpDelay.set(\w_depth, msg[1]/100);
        });

        this.addCommand(\rotate, "f", { |msg|
            warpDelay.set(\rotate, msg[1]);
        });

        this.addCommand(\mix, "f", { |msg|
            warpDelay.set(\mix, msg[1]);
        });

        this.addCommand(\lagTime, "f", { |msg|
            warpDelay.set(\lagTime, msg[1]);
        });
    }

    // Free resources
    free {
        numTracks.do { |i|
            buffers[i].free;
            buffersR[i].free;
            recordBuffers[i].free;
            recordBuffersR[i].free;
            recorders[i].free;
            recorderPosses[i].free;
        };
        
        delayBus.free;
        trigBus.free;
        pg.free;
        warpDelay.free;
    }
}
