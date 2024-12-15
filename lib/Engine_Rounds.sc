Engine_Rounds : CroneEngine {
    var pg, buffer,bufferR, recordBuffer,recordBufferR, sampleOrRecord=0, path="", stepInfo, numSteps, numSegments, delayBus, segmentLength, simpleBuffer, activeStep, fade = 0.1, trigBus, useSampleLength=1, warpDelay,
    randomOctave = 0, randomPan = 0, randomAmp = 0, randomLowPass=0, randomHiPass=0, randomFith = 0, randomReverse = 0, randomAttack = 0, randomRelease = 0, attack=0.01, 
    release=0.5, useEnv = 1, semitones=0, lowpassFreq=20000, resonance=1, hipassFreq=1, lowpassEnvStrength=0, hipassEnvStrength=0, recorder, useRecordBuffer = 0, loopLength=180, recorderPos=0;

    *new { arg context, doneCallback;
        ^super.new(context, doneCallback);
    }

    // Load a buffer for the single voice
    loadBuffer {
		// Check if the file exists
        if (File.exists(path), {
            buffer.do(_.free);  // Free the existing buffer if it exists

            Buffer.read(context.server, path, 0, 1, { |tempBuffer|
				(tempBuffer.numChannels == 1).if({
					// Mono file
                    Buffer.readChannel(context.server, path, 0, -1, [0], { |newBuffer|
						buffer = newBuffer;  // Store buffer
                        bufferR = newBuffer;  // Store buffer
						loopLength = buffer.duration;
						segmentLength = buffer.duration / numSegments;  // Recalculate segmentLength
                        "Buffer loaded. Segment length: %".format(segmentLength).postln;
                    });
                }, {
					// Stereo file
					(tempBuffer.numChannels == 2).if({
                        buffer = Buffer.readChannel(context.server, path, 0, -1, [0], { |newBufferL|
                            segmentLength = newBufferL.duration / numSegments; 
                            buffer = newBufferL;
							loopLength = buffer.duration;
                            "Stereo buffer (left) loaded. Segment length: %".format(segmentLength).postln;
							trigBus  = Bus.control(context.server, 1);
                        });
                        bufferR = Buffer.readChannel(context.server, path, 0, -1, [1], { |newBufferR|
                            "Stereo buffer (right) loaded.".postln;
                            bufferR = newBufferR;
                        });
                    });
                });
            });
        }, {
            "File not found: %".format(path).postln;
        });
}



    alloc {
        buffer = Buffer.alloc(context.server, context.server.sampleRate * 2, 1);
        bufferR = Buffer.alloc(context.server, context.server.sampleRate * 2, 1);

		recordBuffer = Buffer.alloc(context.server, context.server.sampleRate * loopLength, 1);
        recordBufferR = Buffer.alloc(context.server, context.server.sampleRate * loopLength, 1);

		recorderPos = Bus.control(context.server, 1);

        // Simple buffer synth

		SynthDef(\simpleBufferSynth, {
			|bufnumL, bufnumR, startSegment = 0, endSegment = 1, numSegments = 8, amp = 0.1, rate = 1, reverse = 0, pan = 0, lowpassFreq = 20000, resonance = 1, hipassFreq = 1,
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
			
            Out.ar(out, 1 - mix * inputSignal + (mix * delayedSignal));
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


		// Initialize active step
        activeStep = 0;
        // ParGroup for handling the voice
        pg = ParGroup.head(context.xg);

        trigBus  = Bus.control(context.server, 1);
        delayBus = Bus.audio(context.server, 2);

	
		// Number of steps and segments
        numSteps = 64;
        numSegments = 16;
        // Initialize stepInfo array for the single voice
        segmentLength = buffer.duration / numSegments;

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

		recorder = Synth.new(\continuousRecorder, [
			\bufnumL, recordBuffer,
            \bufnumR, recordBufferR,
            \inputBus, 0,
			\loop, 1,
            \out, context.out_b.index,
			\phase_out, recorderPos,
		], target: context.xg);
		


        context.server.sync;

		// ============================================================
		// Commands
		// ============================================================

        this.addCommand(\bufferPath, "s", { |msg|
            path = msg[1];
            this.loadBuffer();
            if (buffer.notNil and: { buffer.numFrames > 0 }) {
                segmentLength = buffer.duration / numSegments;
                "Segment length updated: %".format(segmentLength).postln;
            } {
                "Buffer not loaded correctly or file not found.".postln;
            }
        });

		this.addCommand(\vol, "f", { |msg|
			var vol = msg[1];
		});

		this.addCommand(\semitones, "f", { |msg|
			semitones = msg[1];
		});

		this.addCommand(\lowpassFreq, "f", { |msg|
			var newLowpassFreq = msg[1];
			lowpassFreq = newLowpassFreq;
		});

		this.addCommand(\highpassFreq, "f", { |msg|
			var newHighpassFreq = msg[1];
			hipassFreq = newHighpassFreq;
		});

		this.addCommand(\resonance, "f", { |msg|
			var newResonance = msg[1];
			resonance = newResonance;
		});


		

		this.addCommand(\attack, "f", { |msg|
			attack = msg[1];
		});

		this.addCommand(\release, "f", { |msg|
			release = msg[1];
		});

		this.addCommand(\useEnv, "f", { |msg|
			 useEnv = msg[1];
		});

        this.addCommand(\steps, "i", { |msg|
			var newNumSteps = msg[1];
			numSegments = newNumSteps;
            segmentLength = buffer.duration / numSegments;
            // this.loadBuffer();
        });

		this.addCommand(\useSampleLength, "f", { |msg|
			var newUseSampleLength = msg[1];
			useSampleLength = newUseSampleLength;
		});

		// Random
		this.addCommand(\randomOctave, "f", { |msg|
			var newRandomOctave = msg[1];
			randomOctave = newRandomOctave;
		});

		this.addCommand(\randomPan, "f", { |msg|
			var newRandomPan = msg[1];
			randomPan = newRandomPan;
		});

		this.addCommand(\randomAmp, "f", { |msg|
			var newRandomAmp = msg[1];
			randomAmp = newRandomAmp;
		});

		this.addCommand(\randomFith, "f", { |msg|	
			var newRandomFith = msg[1];
			randomFith = newRandomFith;
		});

		this.addCommand(\randomReverse, "f", { |msg|
			var newRandomReverse = msg[1];
			randomReverse = newRandomReverse;
		});

		this.addCommand(\randomAttack, "f", { |msg|
			var newRandomAttack = msg[1];
			randomAttack = newRandomAttack;
		});

		this.addCommand(\randomRelease, "f", { |msg|
			var newRandomRelease = msg[1];
			randomRelease = newRandomRelease;
		});

		this.addCommand(\randomLowPass, "f", { |msg|
			var newRandomLowPass = msg[1];
			randomLowPass = newRandomLowPass;
		});

		this.addCommand(\randomHiPass, "f", { |msg|
			var newRandomHiPass = msg[1];
			randomHiPass = newRandomHiPass;
		});

		this.addCommand(\lowpassEnvStrength, "f", { |msg|
			var newLowpassEnvStrength = msg[1];
			lowpassEnvStrength = newLowpassEnvStrength;
		});

		this.addCommand(\hipassEnvStrength, "f", { |msg|
			var newHipassEnvStrength = msg[1];
			hipassEnvStrength = newHipassEnvStrength;
		});

        this.addCommand(\play, "ifffi", { |msg|

            var startSegment = msg[1] - 1;
            var amp = msg[2] + (rrand(-1, 1) * randomAmp);
            var pan = msg[4] + (rrand(-1, 1) * randomPan);
            var reverse = wchoose([msg[5], 1], [1 - randomReverse, randomReverse]);

            var attackR = attack + (rrand(0.001, 1) * randomAttack);
            var releaseR = release + (rrand(0.001, 3) * randomRelease);

            var stepRate = msg[3] * (2 ** (semitones / 12));
            var fithFactor = wchoose([1, 1.5], [1 - randomFith, randomFith]); 
            var octaveFactor = wchoose([1, 2], [1 - randomOctave, randomOctave]);
            var rate = (stepRate * fithFactor) * octaveFactor;
            var lowpassFreqFactor = lowpassFreq + (rrand(-1, 1) * randomLowPass * 10000);
            var hipassFreqFactor = hipassFreq + (rrand(-1, 1) * randomHiPass * 10000);

            var selectedBufferL = if(sampleOrRecord == 0, { buffer }, { recordBuffer });
            var selectedBufferR = if(sampleOrRecord == 0, { bufferR }, { recordBufferR });
			

            simpleBuffer = Synth.new(\simpleBufferSynth, [
			\bufnumL, selectedBufferL.bufnum,
			\bufnumR, selectedBufferR.bufnum,
			\startSegment, startSegment,
			\endSegment, startSegment + 1,
			\numSegments, numSegments,
			\amp, amp.clip(0, 1),
			\rate, rate,
			\pan, pan,
			\out, delayBus,
			\trigIn, trigBus.index,
			\useEnv, useEnv,
			\attack, attackR,
			\release, releaseR,
			\reverse, reverse,
			\lowpassFreq, lowpassFreqFactor.clip(1, 20000),
			\hipassFreq, hipassFreqFactor.clip(1, 20000),
			\lowpassEnvStrength, lowpassEnvStrength,
			\hipassEnvStrength, hipassEnvStrength,
			\resonance, resonance,
			\loopLength, loopLength,  // Pass updated loopLength
			\sampleOrRecord, sampleOrRecord,  // Pass the mode
			\vol, 1,
		], target: context.xg);
        });

        this.addCommand(\sampleOrRecord, "i", { |msg|
			sampleOrRecord = msg[1];
			if (sampleOrRecord == 0) {
				"Sample mode".postln;
				segmentLength = buffer.duration / numSegments;  // Recalculate segmentLength
			} {
				"Record mode".postln;
				segmentLength = loopLength / numSegments;  // Use loopLength for calculation
			}
		});

		this.addCommand(\record, "f", { |msg|
			var isRecording = msg[1];
			recorder.set(\isRecording, isRecording);
			if (sampleOrRecord == 1) {
				segmentLength = loopLength / numSegments;  // Recalculate segmentLength for recording
			}
		});
		
		this.addCommand(\loopLength, "f", { |msg|
			loopLength = msg[1];
			recorder.set(\loopLength, loopLength);  // Update recorder
			segmentLength = loopLength / numSegments;  // Recalculate segmentLength for playback
			
		});

		this.addPoll(\recorderPos, { 
			recorderPos.getSynchronous;
		});





		// Delay Commands
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
        buffer.free;
        recordBuffer.free;
		bufferR.free;
		recordBufferR.free;
		simpleBuffer.free;
		recorder.free;
		
        pg.free;
        warpDelay.free;
    }
}

