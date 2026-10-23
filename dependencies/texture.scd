// Toolbox: voices (Markov-chain melodies on the guitar sampler), the controls that
// shape them, effects, and cues. Loaded by patch.scd after markov.scd, glide.scd and
// pattern-fx.scd; patch.scd explains how to use it.
//
// Every control takes WHICH voice(s): \pb1, [\pb1, \pb3], or \all.
// Optional `time` arguments are seconds of gradual change (0 = at once).
//
//   ~play.(which)  ~stop.(which)  ~tempo.(bpm)  ~cue.(name, { ... })
//   ~range.(which, low, high, time)   (MIDI notes; notes outside fold in by octaves)
//   ~rangeLfo.(which, \low or \high, secs, from, to)   ~transpose.(which, steps)   (scale steps)
//   ~spread.(which, amount, time)     (1 = as written, 0.5 = intervals halved, 2 = doubled)
//   ~density.(which, amount, notes)   (2 = twice as many notes; glides over `notes` notes)
//   ~thin.(which, chance, time)       (chance 0..1 that a note is silent)
//   ~rhythm.(which, durs)             (a \dur value or pattern, in beats)
//   ~scale.(which, scale)             ~ring.(which, secs)
//   ~loadMelody.(file, order)  ~useMelody.(which, melody, order)   (switch Markov chains)
//   ~dyn.(which, db, time, curve)     ~swell.(which, lowDb, highDb, secs)   ~pan.(which, pos, time)
//   ~fx.(which, effect, param, value, time, curve)   ~fxLfo.(which, effect, param, secs, lo, hi, shape)
//   ~fxStop.(which, effect, param)    ~fxShow.(which)   ~reset.(which)

(
// ---- effects available on every voice (on top of pattern-fx.scd's library) ----
~fxLib[\hpf] = (defaults: (freq: 200, rq: 0.7),
	func: { |sig, p| RHPF.ar(sig, p[\freq].clip(20, 20000), p[\rq].clip(0.05, 2)) });
~fxLib[\chorus] = (defaults: (rate: 0.3, depth: 0.004),
	func: { |sig, p| DelayC.ar(sig, 0.05, SinOsc.kr(p[\rate], [0, pi]).range(0.005, 0.005 + p[\depth].clip(0, 0.04))) });
// signal order: notes -> hpf -> lpf -> ... -> reverb -> out
~voiceFx = [\hpf, \lpf, \drive, \ringmod, \decimate, \chorus, \granulator, \fbDelay, \reverb];
~voiceTail = 8;   // seconds effects keep ringing after a voice stops

~voices = ~voices ? ();    // name -> PbindProxy (also ~pb1, ~pb2, ... for direct .set)
~players = ~players ? ();  // name -> what's playing now
~wrapped = ~wrapped ? ();  // name -> the voice routed through its effects
~voiceOrders = ~voiceOrders ? ();   // name -> Markov order

// \pb1, [\pb1, \pb2] or \all -> array of voice names
~names = { |which|
	case
	{ which == \all } { ~voices.keys.asArray.sort }
	{ which.isKindOf(Symbol) } { [which] }
	{ which.asArray }
};

~defaults = (octave: 5, mtranspose: 0, low: 40, high: 84, spread: 1, density: 1, thin: 0,
	rhythm: 0.25, db: -12, pan: 0, release: 3);

// A voice: melody from the Markov chain `map` (order `order`), with every control as a key.
// Key order matters: each key can read the ones above it.
~makeVoice = { |name, map, order, settings|
	var s0 = ~defaults ++ (settings ? ());
	var center = (map[""][0] * map[""][1]).sum.round;   // the melody's average degree
	var proxy = PbindProxy(
		\instrument, \guitar,
		\scale, Scale.major,
		\octave, s0[\octave],
		\mtranspose, s0[\mtranspose],
		\melody, ~markovPattern.(map, order),   // degrees as the chain writes them
		\spread, s0[\spread],
		\center, center,
		// spread: stretch or squeeze the intervals around the melody's centre
		\degree, Pfunc { |ev|
			if(ev[\spread] == 1) { ev[\melody] } { ev[\center] + ((ev[\melody] - ev[\center]) * ev[\spread]).round }
		},
		\low, s0[\low],
		\high, s0[\high],
		// range: move notes outside low..high by octaves until they fit
		\ctranspose, Pfunc { |ev|
			var m = ev.use { ~midinote.value }, shift = 0, lo = ev[\low], hi = ev[\high].max(lo + 12);
			while { (m + shift) < lo } { shift = shift + 12 };
			while { (m + shift) > hi } { shift = shift - 12 };
			shift
		},
		\rhythm, s0[\rhythm],
		\density, s0[\density],
		\dur, Pfunc { |ev|
			var r = ev[\rhythm], d = ev[\density].max(0.01);
			if(r.isKindOf(Rest)) { Rest(r.dur / d) } { r / d }
		},
		\thin, s0[\thin],
		\type, Pfunc { |ev| if(ev[\thin].coin) { \rest } { \note } },
		\db, s0[\db],
		\pan, s0[\pan],
		\release, s0[\release]
	);
	// starting values, so the first gradual change knows where to start from
	~glideLast[proxy] = IdentityDictionary.newFrom(s0.asKeyValuePairs);
	~voices[name] = proxy;
	~voiceOrders[name] = order;
	currentEnvironment[name] = proxy;   // ~pb1 etc.
	~wrapped[name] = ~withFx.(name, proxy, ~voiceFx, nil, ~voiceTail);
	proxy
};

~play = { |which, quant = 4|
	~names.(which).do { |n|
		if(~players[n].isNil or: { ~players[n].isPlaying.not }) {
			~players[n] = ~wrapped[n].play(quant: quant);
		};
	};
};

~stop = { |which|
	~names.(which).do { |n| ~players[n] !? { |p| p.stop }; ~players[n] = nil };
};

~tempo = { |bpm| TempoClock.default.tempo = bpm / 60 };

// Runs `func` at the next bar line (every `quant` beats), so changes land together and in time.
~cue = { |name, func, quant = 4|
	TempoClock.default.play({ ("CUE: " ++ name).postln; func.value; nil }, quant);
};

// Set a key on voices at once, or glide it there over `time` seconds.
~setKey = { |which, key, value, time = 0, curve = 0|
	~names.(which).do { |n|
		var p = ~voices[n];
		if(time > 0) { ~glide.(p, key, value, time, curve) } {
			p.set(key, value);
			~glideLast[p][key] = if(value.isNumber) { value };
		};
	};
};

~transpose = { |which, steps| ~setKey.(which, \mtranspose, steps) };
~spread = { |which, amount, time = 0| ~setKey.(which, \spread, amount, time) };
~thin = { |which, chance, time = 0| ~setKey.(which, \thin, chance, time) };
~dyn = { |which, db, time = 0, curve = 0| ~setKey.(which, \db, db, time, curve) };
~pan = { |which, pos, time = 0| ~setKey.(which, \pan, pos, time) };
~ring = { |which, secs| ~setKey.(which, \release, secs) };
~scale = { |which, scale| ~setKey.(which, \scale, scale) };
~rhythm = { |which, durs| ~setKey.(which, \rhythm, durs) };
// Register: the lowest and highest MIDI notes allowed. Notes outside jump by octaves until they
// fit, so they stay in the scale even while the limits glide or swing.
~range = { |which, low = 40, high = 84, time = 0|
	~setKey.(which, \low, low, time);
	~setKey.(which, \high, high, time);
};
// Swing one limit (\low or \high) between `from` and `to`, `secs` per cycle. Voices started in
// one call move together. ~range stops it.
~rangeLfo = { |which, limit = \low, secs = 20, from = 40, to = 72|
	~names.(which).do { |n| ~lfo.(~voices[n], limit, secs, from, to) };
};

// density changes the time between notes, so it glides note by note, not by the clock
~density = { |which, amount, notes = 0|
	~names.(which).do { |n|
		if(notes > 0) { ~glideNotes.(~voices[n], \density, amount, notes) } { ~setKey.(n, \density, amount) };
	};
};

~swell = { |which, lowDb = -30, highDb = -8, secs = 8|
	~names.(which).do { |n| ~lfo.(~voices[n], \db, secs, lowDb, highDb) };
};

// A Markov chain from a MIDI file in the project folder (a melody in C major; rhythm ignored).
~loadMelody = { |file, order = 9| ~markovFromMidi.(~root +/+ file, order) };

// Switch voices to another chain (from ~loadMelody). `order`: how many notes each voice
// remembers; leave it out for each voice's own (set in patch.scd).
~useMelody = { |which, map, order|
	~names.(which).do { |n|
		~voices[n].set(\melody, ~markovPattern.(map, order ? ~voiceOrders[n]), \center, (map[""][0] * map[""][1]).sum.round);
	};
};

// back to the starting settings (effects are left as they are)
~reset = { |which|
	~names.(which).do { |n| ~defaults.keysValuesDo { |key, value| ~setKey.(n, key, value) } };
	~scale.(which, Scale.major);
};

// effects, for one or several voices (pattern-fx.scd's versions work on one)
~fxOne = ~fxOne ? ~fx;
~fxLfoOne = ~fxLfoOne ? ~fxLfo;
~fxStopOne = ~fxStopOne ? ~fxStop;
~fxShowOne = ~fxShowOne ? ~fxShow;
~fx = { |which, effect, param, value, time = 0, curve = 0|
	~names.(which).do { |n| ~fxOne.(n, effect, param, value, time, curve) };
};
~fxLfo = { |which, effect, param, secs = 5, lo = 0, hi = 1, shape = \sine|
	~names.(which).do { |n| ~fxLfoOne.(n, effect, param, secs, lo, hi, shape) };
};
~fxStop = { |which, effect, param| ~names.(which).do { |n| ~fxStopOne.(n, effect, param) } };
~fxShow = { |which| ~names.(which).do { |n| ~fxShowOne.(n) } };

// Guitar sampler: every MIDI note plays the nearest sample, repitched. The sample rings on
// for `release` s after the note's duration ends.
~buildGuitar = { |bufs|
	var sampleMidis = bufs.keys.asArray.sort;
	var nearest = (0..127).collect { |m| sampleMidis.minItem { |n| ((n - m).abs * 2) + (n > m).binaryValue } };
	SynthDef(\guitar, { |out = 0, freq = 440, amp = 0.25, pan = 0, gate = 1, attack = 0.001, release = 3|
		var bufnums = nearest.collect { |n| bufs[n].bufnum };   // fixed when the SynthDef is built
		var midi = freq.cpsmidi;
		var idx = midi.round.clip(0, 127);
		var bufnum = Select.kr(idx, bufnums);
		var rate = (midi - Select.kr(idx, nearest)).midiratio;
		var sig = PlayBuf.ar(1, bufnum, rate * BufRateScale.kr(bufnum), doneAction: 2);
		var env = EnvGen.kr(Env.asr(attack, 1, release), gate, doneAction: 2);
		Out.ar(out, Pan2.ar(sig * env * amp, pan));
	}).add;
};

// Safety limiter on the speakers, after everything else. Restarted after Cmd-period.
~limiter = {
	SynthDef(\masterLimiter, { ReplaceOut.ar(0, Limiter.ar(In.ar(0, 2), -1.dbamp)) }).add;
	ServerTree.remove(~limiterTree);
	~limiterTree = { |server|   // only one limiter, however often this runs
		if(~limiterSynth.notNil and: { ~limiterSynth.isPlaying }) { ~limiterSynth.free };
		~limiterSynth = Synth.tail(RootNode(server), \masterLimiter);
		NodeWatcher.register(~limiterSynth, true);
	};
	ServerTree.add(~limiterTree);
};
)
