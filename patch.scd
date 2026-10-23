// ===================================================================================
//  MARKOV GUITARS
//
//  Four voices play melodies invented by Markov chains trained on Für Elise, on sampled
//  guitar. You can shape the texture they make (register, density, scale, dynamics, effects)
//  and write CUES, blocks of changes that happen together.
//
//  1. Save this file (it finds its other files relative to itself).
//  2. Run the MAIN BLOCK below: put the cursor inside it and press Cmd-Return.
//     The first time, a window asks to download the guitar samples: press Proceed.
//     Wait for "READY" in the Post window.
//  3. Run the lines further down one at a time (Shift-Return), or a whole cue (Cmd-Return).
//
//  Cmd-period stops everything. ~play.(\all) starts again (no need to rerun the main block).
// ===================================================================================

// ---------------------------------- MAIN BLOCK ----------------------------------
(
if(thisProcess.nowExecutingPath.isNil) { Error("Save this file first, then run the block again.").throw };
~root = thisProcess.nowExecutingPath.dirname;   // the folder this file is in
~players !? { ~players.do(_.stop) };              // stop voices from an earlier run

s.options.numInputBusChannels = 0;   // no microphone needed (and avoids sample-rate mismatch errors)
s.options.memSize = 65536;            // 64 MB for delays and reverbs
s.reboot;
s.waitForBoot {
	["markov", "glide", "pattern-fx", "texture"].do { |f| (~root +/+ "dependencies" +/+ f ++ ".scd").load };

	// The Markov chain: for every run of up to 9 notes in the melody, which note came next
	// and how often. Voices with a lower order remember fewer notes, so they wander more.
	~melody = ~loadMelody.("fur_elise.mid", 9);
	~scaleRun = ~loadMelody.("scale.mid", 9);   // C major, up an octave and back down

	d = ();
	d.requiredSounds = ["Guitar_Samples"];
	d.onComplete = {
		fork {
			var dir = Platform.userAppSupportDir +/+ "sounds" +/+ "twm_samples" +/+ "Guitar_Samples";
			~guitarBufs = Dictionary.new;   // MIDI number -> sample
			PathName(dir).files.do { |file|
				var midi = file.fileNameWithoutExtension;
				if((file.extension == "wav") and: { midi.notEmpty } and: { midi.every(_.isDecDigit) }) {
					~guitarBufs[midi.asInteger] = Buffer.readChannel(s, file.fullPath, channels: [0]);
				};
			};
			s.sync;

			~buildGuitar.(~guitarBufs);   // the guitar instrument
			~buildFx.value;               // the effects
			~limiter.value;
			s.sync;
			~limiterTree.(s);

			// The voices: Markov order, then any settings that differ from the defaults
			// (~defaults in dependencies/texture.scd).
			~makeVoice.(\pb1, ~melody, 8);
			~makeVoice.(\pb2, ~melody, 6, (rhythm: 0.5, pan: -0.4));
			~makeVoice.(\pb3, ~melody, 4, (octave: 4, rhythm: 0.75, pan: 0.4));
			~makeVoice.(\pb4, ~melody, 2, (octave: 3, rhythm: 1, db: -9));
			"READY".postln;
		};
	};
	(~root +/+ "dependencies" +/+ "sample-install.scd").load;   // downloads the samples if needed
};
)


// ------------------------------- 1. PLAY AND STOP -------------------------------
// Every control names the voice(s) it changes: \pb1, a list [\pb1, \pb3], or \all.
// Voices start on the next bar line, so they line up.

~play.(\pb1);
~play.([\pb2, \pb3]);
~play.(\all);
~stop.(\pb3);        // effects ring on for a few seconds after a stop
~stop.(\all);
~tempo.(300);         // beats per minute, for every voice (60 at the start)


// ---------------------------------- 2. TOOLBOX ----------------------------------
// Many controls take a TIME in seconds as the last number: the change happens gradually
// over that time instead of at once. Leave it out to change at once.

// REGISTER AND RANGE: the lowest and highest notes allowed (MIDI numbers: 60 = middle C).
// Notes outside the range jump by octaves until they fit, so they stay in the scale.
// The guitar samples cover 40 (low E) .. 84; the voices start with that whole range.
~range.(\pb1, 55, 67);          // squeeze pb1 into G3..G4
~range.(\pb4, 40, 52);          // pb4 into the bottom octave
~range.(\all, 64, 84, 20);      // over 20 s, the range climbs: everything ends up high
~range.(\all, 40, 84);          // back to the full guitar, at once

// The floor rises and falls for all voices together: lowest note between 40 and 72,
// 30 s per cycle. As it rises, low notes are pushed up and the texture crowds together.
~rangeLfo.(\all, \low, 30, 40, 72);
~rangeLfo.(\pb1, \high, 12, 60, 84);   // the ceiling can swing too (here only pb1's)
~range.(\all, 40, 84);          // stops the LFOs

~transpose.(\pb2, 2);           // move the melody up 2 steps of the scale (a third)
~transpose.(\pb2, 0);
~spread.(\pb1, 0.3, 10);        // squeeze the melody's leaps towards its centre: 1 = as written,
                                //   0 = a single note, 2 = leaps twice as wide

// DENSITY: how many notes
~density.(\pb1, 2);             // twice as many notes (half the time between them)
~density.(\pb1, 0.5, 16);       // thin out to half over the next 16 notes
~thin.(\pb2, 0.6);              // each note has a 60% chance of being silent
~thin.(\pb2, 0, 30);            // fill back in over 30 s
~rhythm.(\pb1, Pseq([0.75, 0.75, 0.5], inf));            // a groove, in beats (3+3+2)
~rhythm.(\pb2, Pseq([Rest(0.5), 0.5], inf));             // offbeats: Rest = a silent step
~rhythm.(\pb3, Prand([0.25, 0.5, 1], inf));              // random choice each note
~rhythm.(\pb1, 0.25);           // back to steady 16ths

// SCALE: the melody's steps are mapped onto the scale you choose
~scale.(\all, Scale.minor);
~scale.(\pb3, Scale.majorPentatonic);
~scale.(\all, Scale([0, 1, 4, 5, 7, 8, 10]));   // your own: semitones above the tonic
~scale.(\all, Scale.major);
// Scale.directory posts the built-in names. Scales with other than 7 notes bend the
// melody's shape (it was written for 7).

// DYNAMICS
~dyn.(\pb1, -24);               // in dB: 0 is full, -6 half as loud, -40 very quiet
~dyn.(\pb1, -6, 15);            // crescendo over 15 s
~dyn.(\all, -60, 20, -4);       // fade everything out over 20 s (-4: fast at first)
~swell.(\pb2, -30, -8, 6);      // keep swelling between -30 and -8 dB, 6 s per cycle
~dyn.(\pb2, -12);               // stops the swell
~pan.(\pb1, -1, 10);            // move left over 10 s (-1 left .. 1 right)
~ring.(\all, 0.2);              // short, damped notes (seconds each note rings on)
~ring.(\all, 3);

~reset.(\all);                  // everything above back to the start (not effects)


// ---------------------------------- 3. EFFECTS ----------------------------------
// Each voice has its own chain of effects, all switched off (mix 0) at the start:
//   notes -> hpf -> lpf -> drive -> ringmod -> decimate -> chorus -> granulator -> fbDelay -> reverb
//
//   ~fx.(which, effect, setting, value, time)
//
// Every effect has a `mix` setting, 0 = off (dry) .. 1 = only the effect. Its other settings:
//   hpf         freq (Hz: cuts below), rq (0.1 resonant .. 1 smooth)
//   lpf         freq (Hz: cuts above), rq
//   drive       gain (1 clean .. 30 fuzz), tone (Hz)
//   ringmod     freq (Hz: low = tremolo, high = metallic)
//   decimate    factor (1 clean .. 40 crunchy), antiAlias, antiImage (0 or 1)
//   chorus      rate (Hz), depth (0 .. 0.04)
//   granulator  grainDur (s), density (grains/s), delay (s back), scatter (s), pitchJitter (semitones), spread (0..1)
//   fbDelay     time (s between echoes), fb (0 .. 0.95 echoes), damp (Hz: darker echoes)
//   reverb      room (0 .. 1), damp (0 .. 1)

~fx.(\pb1, \reverb, \mix, 0.4);                   // some room
~fx.(\all, \reverb, \room, 1);
~fx.(\pb1, \lpf, \mix, 1);                        // turn the filter on...
~fx.(\pb1, \lpf, \freq, 400, 10);                 // ...and close it over 10 s
~fx.(\pb2, \fbDelay, \mix, 0.5);
~fx.(\pb2, \fbDelay, \time, 0.75);                // echoes 0.75 s apart
~fx.(\pb2, \fbDelay, \fb, 0.8, 5);
~fx.(\pb3, \drive, \mix, 1); ~fx.(\pb3, \drive, \gain, 20, 8);
~fx.(\pb4, \ringmod, \mix, 0.7); ~fx.(\pb4, \ringmod, \freq, 6);   // tremolo
~fx.(\pb1, \decimate, \mix, 1); ~fx.(\pb1, \decimate, \factor, 30, 15);
~fx.(\pb2, \granulator, \mix, 0.8); ~fx.(\pb2, \granulator, \pitchJitter, 7, 10);

// LFOs keep a setting moving by itself:
//   ~fxLfo.(which, effect, setting, seconds per cycle, low, high, shape)
// shape: \sine (smooth, the default), \tri (straight up and down), \noise (wanders at random).
// Turn the effect's mix up first, or you won't hear it.

// DECIMATE: lower the sample rate for digital grit
~fx.(\all, \decimate, \mix, 1);
~fxLfo.(\all, \decimate, \factor, 16, 1, 40);          // crunch slowly comes and goes, all voices
~fxLfo.(\pb1, \decimate, \factor, 2, 1, 30, \noise);   // pb1: restless, random crunch
~fxLfo.(\pb2, \decimate, \factor, 4, 8, 60, \tri);     // pb2: deep, sawing back and forth
~fxLfo.(\all, \decimate, \mix, 24, 0, 1);              // and fade the whole effect in and out
~fx.(\all, \decimate, \mix, 0);                        // off (also stops the mix LFO)

// FILTERS
~fx.(\pb1, \lpf, \mix, 1);
~fxLfo.(\pb1, \lpf, \freq, 8, 300, 4000);              // a slow wah
~fxLfo.(\pb1, \lpf, \rq, 3, 0.1, 0.8, \noise);         // with wandering resonance
~fx.(\pb3, \hpf, \mix, 1);
~fxLfo.(\pb3, \hpf, \freq, 12, 100, 2000, \tri);       // thins pb3 out and back

// DRIVE AND RING MOD
~fx.(\pb4, \drive, \mix, 1);
~fxLfo.(\pb4, \drive, \gain, 10, 1, 25);               // clean to fuzz and back
~fx.(\pb2, \ringmod, \mix, 0.7);
~fxLfo.(\pb2, \ringmod, \freq, 20, 4, 800);            // tremolo that speeds up into a metallic tone

// MOVEMENT AND SPACE
~fx.(\pb3, \chorus, \mix, 0.6);
~fxLfo.(\pb3, \chorus, \depth, 3, 0, 0.02, \noise);
~fx.(\pb1, \fbDelay, \mix, 0.5); ~fx.(\pb1, \fbDelay, \fb, 0.6);
~fxLfo.(\pb1, \fbDelay, \time, 10, 0.1, 0.5);          // changing delay time bends the echoes' pitch
~fx.(\pb2, \granulator, \mix, 0.8);
~fxLfo.(\pb2, \granulator, \pitchJitter, 15, 0, 12);   // grains drift out of tune and back
~fxLfo.(\pb2, \granulator, \density, 7, 5, 60, \noise);
~fxLfo.(\all, \reverb, \mix, 20, 0.1, 0.8);            // near, then far away

~fxStop.(\pb1, \lpf, \freq);                      // freeze an LFO or glide where it is
~fxShow.(\pb1);                                   // post every effect setting of pb1

~fx.(\all, \lpf, \mix, 0, 5);                     // fade an effect out (mix 0) over 5 s


// ----------------------------------- 4. CUES ------------------------------------
// A cue is a group of changes that happen at the same moment, the electronic part's
// "next section". Write it as ~cue.("name", { ...changes... }); and run it with Cmd-Return.
// It waits for the next bar line, so it lands in time, and posts its name.
// Mix gradual changes (a time) with sudden ones for shape.
//
// Below: a short piece in five cues. Run them in order, a little while apart.

(
~cue.("1: one voice, far away", {
	~reset.(\all);
	~fx.(\all, \reverb, \mix, 0.6);
	~fx.(\pb1, \lpf, \mix, 1); ~fx.(\pb1, \lpf, \freq, 800);
	~dyn.(\pb1, -30); ~dyn.(\pb1, -12, 20);     // fade in over 20 s
	~fx.(\pb1, \lpf, \freq, 6000, 20);          // and open up
	~play.(\pb1);
});
)

(
~cue.("2: echoes answer", {
	~play.(\pb2);
	~thin.(\pb2, 0.5);
	~fx.(\pb2, \fbDelay, \mix, 0.5); ~fx.(\pb2, \fbDelay, \time, 0.75); ~fx.(\pb2, \fbDelay, \fb, 0.6);
	~pan.(\pb2, 0.8, 10);
});
)

(
~cue.("3: everything thickens", {
	~play.([\pb3, \pb4]);
	~density.([\pb1, \pb2], 2, 32);             // twice as busy over the next 32 notes
	~thin.(\pb2, 0, 20);
	~swell.(\pb3, -24, -8, 8);
	~fx.(\pb4, \drive, \mix, 1); ~fx.(\pb4, \drive, \gain, 8);
});
)

(
~cue.("4: the floor tilts", {
	~scale.(\all, Scale.harmonicMinor);
	~spread.(\pb1, 2, 15);                      // leaps grow wider
	~fx.(\all, \granulator, \mix, 0.5, 10);
	~rangeLfo.(\all, \low, 30, 40, 70);        // the floor heaves up and down
	~fx.([\pb1, \pb3], \decimate, \mix, 1);
	~fxLfo.([\pb1, \pb3], \decimate, \factor, 12, 1, 35);   // grit comes in waves
	~fxLfo.(\pb3, \lpf, \freq, 6, 400, 5000); ~fx.(\pb3, \lpf, \mix, 1);
});
)

(
~cue.("5: dissolve", {
	~range.(\all, 64, 84, 20);                  // everything climbs up high over 20 s
	~density.(\all, 0.25, 24);
	~fx.(\all, \reverb, \mix, 0.9, 10); ~fx.(\all, \reverb, \room, 1);
	~dyn.(\all, -60, 30, -3);
	TempoClock.default.sched(32, { ~stop.(\all); nil });   // stop 32 beats later
});
)


// --------------------------------- 5. MELODIES ---------------------------------
// Each voice improvises from a Markov chain learned from a MIDI file. Switch chains with
//   ~useMelody.(which, melody, order)
// `order` = how many past notes a voice remembers when it picks the next one. Leave it out
// to keep each voice's own (pb1 8, pb2 6, pb3 4, pb4 2).

~useMelody.(\all, ~scaleRun);          // every voice now plays from the scale
~useMelody.(\pb4, ~scaleRun, 1);       // order 1: knows only the last note, so it wanders
                                       //   up and down at random
~useMelody.(\pb1, ~scaleRun, 3);       // order 3: remembers enough to run up and down in order
~useMelody.(\all, ~melody);            // back to Für Elise

// ADD YOUR OWN MIDI FILE
// 1. Put it in this folder (next to patch.scd), e.g. "my_tune.mid". It should be a melody in
//    C major (other notes count as sharps); if notes overlap, the highest is used, and
//    rhythm is ignored. Most notation programs export MIDI: File > Export > MIDI.
// 2. Learn its chain (9 = the most notes any voice can remember), then switch voices to it:
~myTune = ~loadMelody.("my_tune.mid", 9);
~useMelody.([\pb2, \pb3], ~myTune);


// ------------------------------ 6. YOUR OWN CUES ------------------------------
// Copy this, give it a name, and fill it with controls from sections 1-3 and 5.
// Tip: start a new section from a known state with ~reset.(\all) and effect mixes at 0.

(
~cue.("my cue", {

});
)
