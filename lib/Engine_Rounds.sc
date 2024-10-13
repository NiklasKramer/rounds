Engine_Rounds : CroneEngine {
    var pg, buffer,path="", routine, stepInfo, numSteps, numSegments, segmentLength, simpleBuffer, activeStep, fade = 0.1, trigBus, direction, yieldTime, useSampleLength=1, stepTime = 0.1, stepLength,
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


    // Allocate buffer and initialize routine
    alloc {
        // Allocate stereo buffer for the single voice
        buffer = Buffer.alloc(context.server, context.server.sampleRate * 1, 2);
		trigBus  = Bus.control(context.server, 1);
		// Initialize active step
		activeStep = 0;
        // ParGroup for handling the voice
        pg = ParGroup.head(context.xg);
		
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




		
		// Number of steps and segments

		
		numSteps = 64;
        numSegments = 16;
        // Initialize stepInfo array for the single voice
        stepInfo = Array.fill(numSteps, { |i| [i, 1, 0 ,1, 0, 1] });  // Default values: [startSegment, rate, reverse, amp, pan, active]
        segmentLength = buffer.duration / numSegments;

		direction = 0;
		yieldTime = 0.1;

        // Create a routine for the single voice
        routine = Task({
            
			"Segment length: %".format(segmentLength).postln;
			"STEP INFO: %".format(stepInfo).postln;
			

            loop {
                numSegments.do { |i|
                    context.server.bind({
						var options = [i, numSegments - i - 1, rrand(0, numSegments - 1)];
						var stepIndex = options[direction];
						var step = stepInfo[stepIndex % stepInfo.size];
						var startSegment = step[0];

						var stepRate = step[1] * (2 ** (semitones / 12)); 
						var fithFactor = wchoose([1, 1.5], [1 - randomFith, randomFith]); 
						var octaveFactor = wchoose([1, 2], [1 - randomOctave, randomOctave]);
						var rate = (stepRate * fithFactor) * octaveFactor;

						var reverse = wchoose([step[2], 1], [1 - randomReverse, randomReverse]);
						var amp = step[3] + (rrand(-1, 1) * randomAmp);
						
						var pan = step[4] + (rrand(-1, 1) * randomPan);
						var active = step[5];
						var fade = if(direction == 0, 0.005, 0.005);
						var attackR = attack + (rrand(0.001, 1) * randomAttack);
						var releaseR = release + (rrand(0.001, 3) * randomRelease);

						activeStep = stepIndex;
						trigBus.set(1);

						// simpleBuffer = Synth.new(\simpleBufferSynth, [
						// 		\bufnum, buffer,
						// 		\startSegment, startSegment,
						// 		\endSegment, startSegment + 1,
						// 		\numSegments, numSegments,
						// 		\amp, amp.clip(0, 1),
						// 		\rate, rate,
						// 		\pan, pan,
						// 		\out, context.out_b.index,
						// 		\trigIn, trigBus.index,
						// 		\useEnv, useEnv,
						// 		\attack, attackR,
						// 		\release, releaseR,
						// 		\reverse, reverse,
						// 		\vol, 1,
						// ], target: pg);
						
						
						stepLength = if(useSampleLength == 1, segmentLength, stepTime);
						yieldTime = if(active == 1, stepLength, 0);

						
					});
						yieldTime.yield;
					
                };
            }
        });

		context.server.sync;




        // Command to set buffer path
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

        // Command to set rate
        this.addCommand(\rate, "if", { |msg|
			var stepIndex = msg[1]-1;
            var newRate = msg[2];
            stepInfo[stepIndex][1] = newRate;
        });

		this.addCommand(\reverse, "if", { |msg|
			var stepIndex = msg[1]-1;
			var newReverse = msg[2];
			stepInfo[stepIndex][2] = newReverse;
		});

		this.addCommand(\segment, "if", { |msg|
			var stepIndex = msg[1] - 1;
			var newSegment = msg[2] - 1;
			stepInfo[stepIndex][0] = newSegment;
		});

		// Command to set amp
		this.addCommand(\amp, "if", { |msg|
			var stepIndex = msg[1] - 1;
			var newAmp = msg[2];	
			stepInfo[stepIndex][3] = newAmp;});

		// Command to set pan
		this.addCommand(\pan, "if", { |msg|
			var stepIndex = msg[1] - 1;
			var newPan = msg[2];
			stepInfo[stepIndex][4] = newPan;
		});

		this.addCommand(\active, "if", { |msg|
			var stepIndex = msg[1] - 1;
			var newActive = msg[2];
			stepInfo[stepIndex][5] = newActive;
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

		this.addCommand(\direction, "f", { |msg|
			var newDirection = msg[1] - 1;
			direction = newDirection;
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

		this.addCommand(\stepTime, "f", { |msg|
			var newStepTime = msg[1];
			stepTime = newStepTime;
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
								\out, context.out_b.index,
								\trigIn, trigBus.index,
								\useEnv, useEnv,
								\attack, attackR,
								\release, releaseR,
								\reverse, reverse,
								\vol, 1,
						], target: pg);
		});	
			




        // Command to start the routine
		this.addCommand(\start, "", { |msg|
			"Attempting to start voice".postln;
			if (routine.isPlaying.not) {
				routine.stop;
				routine.reset;
				routine.play;
				context.server.sync;
				"Voice started".postln;
			} {
				"Voice is already playing".postln;
			};
		});


        // Command to stop the routine
        this.addCommand(\stop, "", { |msg|
			"Attempting to stop voice".postln;
            routine.stop;
			context.server.sync;
        });

		this.addPoll(("position"), {
			var val = activeStep;

			val
		});

    }

    // Free resources
    free {
        buffer.free;
        routine.stop;
        pg.free;
    }
}

