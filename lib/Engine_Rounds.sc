Engine_Rounds : CroneEngine {
    var pg, buffer,path="", stepInfo, numSteps, numSegments, delayBus, segmentLength, simpleBuffer, activeStep, fade = 0.1, trigBus, useSampleLength=1, warpDelay,
	randomOctave = 0, randomPan = 0, randomAmp = 0, randomFith = 0, randomReverse = 0, randomAttack = 0, randomRelease = 0, attack=0.01, release=0.5, useEnv = 0, semitones=0;

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
						segmentLength = buffer.duration / numSegments;  // Recalculate segmentLength
						"Buffer loaded. Segment length: %".format(segmentLength).postln;
					});
				}, {
					// Stereo file
					(tempBuffer.numChannels == 2).if({
						buffer = Buffer.readChannel(context.server, path, 0, -1, [0, 1], {
							segmentLength = buffer.duration / numSegments; 
							"Stereo buffer loaded. Segment length: %".format(segmentLength).postln;
							trigBus  = Bus.control(context.server, 1);
						
						});
					}, {
						"Unsupported number of channels: %".format(tempBuffer.numChannels).postln;
					});
				});
			});
		}, {
			"File not found: %".format(path).postln;
		});
	}



    alloc {
		buffer = Buffer.alloc(context.server, context.server.sampleRate * 1, 2);

		SynthDef(\simpleBufferSynth, {
			|bufnum, startSegment = 0, endSegment = 1, numSegments = 8, amp = 0.1, rate = 1, reverse=0, pan = 0, out, trig = 0, fade = 0.005, vol = 1, attack = 0.01, release = 0.5,
			ampLag = 0.1, rateLag = 0.0, panLag = 0.1, trigIn, useEnv = 0|
			
			var segmentSize, bufplay, phase, gate, phasorStart, phasorEnd, phasorEndRev, start, end, envGen, percEnvGen, fadeEnvGen, safetyEnvGen;

			segmentSize = BufDur.kr(bufnum) / numSegments;
			phasorStart = startSegment / numSegments * BufFrames.kr(bufnum);
			phasorEndRev = (startSegment + 1) / numSegments * BufFrames.kr(bufnum);
			phasorEnd = BufFrames.kr(bufnum);

			end = Select.kr(reverse, [phasorEnd, phasorEndRev]);
			start = Select.kr(reverse, [phasorStart, 0]);

			rate = rate * (1 - (reverse * 2));
			rate = Lag.kr(rate, rateLag);  

			phase = Phasor.ar(
				trig: Impulse.ar(0),
				rate: rate * BufRateScale.kr(bufnum), 
				start: start,  
				end: end,
				resetPos: phasorStart
			
			);

			bufplay = BufRd.ar(2, bufnum, phase, loop: 0);

			amp = Lag.kr(amp, ampLag);     
			pan = Lag.kr(pan, panLag);     

			bufplay = Balance2.ar(bufplay[0], bufplay[1], pan);
			
			gate = Impulse.ar(0);

			percEnvGen = EnvGen.ar(Env.perc((attack + fade), release),gate: gate, doneAction: Done.freeSelf);
			fadeEnvGen = EnvGen.ar(Env.new([0, 1, 1, 0], [fade, segmentSize-(2*fade), fade]),gate:gate, doneAction: Done.freeSelf);
			envGen = Select.ar(useEnv, [fadeEnvGen,percEnvGen]);

			Out.ar(out, bufplay * amp * vol * envGen);
		}).add;

		
		SynthDef(\warpDelay, { |out=0, in=32, delay=0.2, time=10, hpf=330, lpf=8200, w_rate=0.667, w_depth=0.00027, rotate=0.0, mix=0.2, i_max_del=8, lagTime=0.1|
			var inputSignal, modulation, delayedSignal, tapeSignal ,feedbackSignal, feedback, smoothedDelay, smoothedTime;

			inputSignal = In.ar(in, 2); // Input from bus

			smoothedDelay = Lag.kr(delay, lagTime);
			smoothedTime = Lag.kr(time, lagTime);

			feedback = exp(log(0.001) * (smoothedDelay / smoothedTime));
			modulation = LFPar.kr(w_rate, mul: w_depth);

			feedbackSignal = LocalIn.ar(2);
			feedbackSignal = Rotate2.ar(feedbackSignal[0], feedbackSignal[1], rotate).softclip;

			delayedSignal = DelayL.ar(Limiter.ar(Mix([feedbackSignal * feedback, inputSignal]), 0.99, 0.01), i_max_del, smoothedDelay + modulation);
			delayedSignal = LPF.ar(HPF.ar(delayedSignal, hpf), lpf);

			tapeSignal = AnalogTape.ar(delayedSignal);

			LocalOut.ar(tapeSignal);

			Out.ar(out, 1 - mix * inputSignal + (mix * delayedSignal));
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
			\in, delayBus, // Take input from the audio bus
			\out, context.out_b.index, // Send output to the main output
			\delay, 0.2, // Delay time (you can adjust as needed)
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

		// Attack
		this.addCommand(\attack, "f", { |msg|
			attack = msg[1];
		});

		// Release
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
			this.loadBuffer();
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

			

			simpleBuffer = Synth.new(\simpleBufferSynth, [
				\bufnum, buffer,
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
				\vol, 1,
			], target: context.xg);
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
        pg.free;
		warpDelay.free;
    }
}

