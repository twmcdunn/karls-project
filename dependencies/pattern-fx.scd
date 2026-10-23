// Effects for patterns, two ways, from one set of effect definitions (~fxLib):
//
// PER BUS: one effect synth per effect per pattern, processing all its notes together (a
// chain on a private bus, built with nested Pfxb). Settings live on control buses, so they
// glide and sweep smoothly while the pattern plays, and time effects (reverb, delay) ring
// across notes.
//   ~buildFx.value;  s.sync;                              // once, after boot
//   ~p1 = ~withFx.(\pb1, ~pb1).play;                      // every effect in ~fxOrder, all dry
//   ~p1 = ~withFx.(\pb1, ~pb1, [\fbDelay, \reverb]).play; // only these, in this order
//   ~p1 = ~withFx.(\pb1, ~pb1, nil, (out: ~myBus), 8).play; // extra event keys; 8 s of tail at stop
//   ~fx.(\pb1, \reverb, \mix, 0.4);                       // set at once
//   ~fx.(\pb1, \reverb, \mix, 0.8, 20, -3);               // glide over 20 s (curve as in Env)
//   ~fxLfo.(\pb1, \fbDelay, \time, 12, 0.1, 0.5);         // sine, 12 s per cycle, 0.1..0.5
//   ~fxLfo.(\pb1, \lpf, \freq, 8, 300, 3000, \noise);     // shapes: \sine, \tri, \noise
//   ~fxStop.(\pb1, \fbDelay, \time);                      // stop a glide / LFO where it is
//   ~fxShow.(\pb1);                                       // post the current settings
//
// PER NOTE: the effect is built into the note's own SynthDef, its settings are note keys
// ("<effect>_<param>"), so every note can differ (Pwhite, Pseq, ...) and settings glide note
// by note. Time effects are cut when the note ends (give notes a long release or use per bus).
//   SynthDef(\pluck, { |out, freq, amp = 0.2, pan|
//       var sig = Pan2.ar(Pluck.ar(...), pan);
//       sig = ~noteFx.(sig, [\lpf, \drive, \fbDelay]);    // stereo in, stereo out
//       DetectSilence.ar(sig, doneAction: 2); Out.ar(out, sig);
//   }).add;
//   ~pb1 = PbindProxy(\instrument, \pluck, \lpf_mix, 1, \lpf_freq, Pwhite(400, 4000), ...);
//   ~nfx.(~pb1, \lpf, \freq, 800);                        // set at once (a value or a pattern)
//   ~nfx.(~pb1, \lpf, \freq, 4000, 20);                   // glide over 20 s, note by note
//   ~nfxLfo.(~pb1, \drive, \gain, 10, 1, 8);              // sine, 10 s per cycle
//
// Adding an effect: ~fxLib[\name] = (defaults: (...), func: { |sig, p, buf| wet }) before
// ~buildFx -- see the existing entries. `sig` is stereo, `p` holds a control per default
// (already smoothed), the result is the wet signal; mix (0 = dry, 1 = only wet) is added for you.
// Options: buf: seconds (a Buffer per pattern; per bus only), feedback: true (uses
// LocalIn/LocalOut: one per SynthDef, so one such effect per ~noteFx call).

(
~fxLib = (
	lpf: (defaults: (freq: 2000, rq: 0.7),
		func: { |sig, p| RLPF.ar(sig, p[\freq].clip(20, 20000), p[\rq].clip(0.05, 2)) }),

	drive: (defaults: (gain: 4, tone: 6000),
		func: { |sig, p| LPF.ar((sig * p[\gain]).tanh, p[\tone].clip(200, 20000)) / p[\gain].max(1).sqrt }),

	ringmod: (defaults: (freq: 300),
		func: { |sig, p| sig * SinOsc.ar(p[\freq]) }),

	// sample-and-hold at SampleRate / factor / 2, optional low-passes against aliasing /
	// imaging (twice at the new rate / 4, before / after)
	decimate: (defaults: (factor: 1, antiAlias: 0, antiImage: 0),
		func: { |sig, p|
			var newRate = SampleRate.ir / p[\factor].max(1);
			var lowPass = { |x| 2.do { x = LPF.ar(x, newRate / 4) }; x };
			var wet = SelectX.ar(p[\antiAlias].clip(0, 1), [sig, lowPass.(sig)]);
			wet = Latch.ar(wet, Impulse.ar(newRate / 2));
			SelectX.ar(p[\antiImage].clip(0, 1), [wet, lowPass.(wet)])
		}),

	fbDelay: (defaults: (time: 0.375, fb: 0.5, damp: 5000), feedback: true,
		func: { |sig, p|
			var loop = LocalIn.ar(2), wet;
			wet = DelayC.ar(sig + (loop * p[\fb]), 4, (p[\time] - ControlDur.ir).clip(0, 4));
			LocalOut.ar(LPF.ar(wet, p[\damp].clip(20, 20000)).clip2(4));
			wet
		}),

	// 4-line feedback delay network: the whole tail decays 60 dB in rt60 s
	tail: (defaults: (rt60: 3, damp: 8000), feedback: true,
		func: { |sig, p|
			var delays = [0.0497, 0.0671, 0.0813, 0.0977];
			var hadamard = [[1, 1, 1, 1], [1, -1, 1, -1], [1, 1, -1, -1], [1, -1, -1, 1]];
			var src = sig.sum * 0.5, fb = LocalIn.ar(4), lines;
			[0.0043, 0.0067, 0.0097, 0.0131].do { |t| src = AllpassN.ar(src, 0.02, t, 0.3) };
			lines = hadamard.collect { |row| (row * fb).sum * 0.5 };
			lines = lines + (src * [1, -1, 1, -1] * 0.5);
			lines = DelayN.ar(lines, 0.2, delays - ControlDur.ir);
			lines = LPF.ar(lines, p[\damp].clip(20, 20000)) * (0.001 ** (delays / p[\rt60].max(0.05)));
			LocalOut.ar(lines.clip2(4));
			Splay.ar(LeakDC.ar(lines), 0.8)
		}),

	reverb: (defaults: (room: 0.8, damp: 0.5),
		func: { |sig, p| FreeVerb2.ar(sig[0], sig[1], 1, p[\room].clip(0, 1), p[\damp].clip(0, 1)) }),

	// granulates the last 4 s of its input (GrainBuf can't read a LocalBuf, so per bus only)
	granulator: (defaults: (grainDur: 0.08, density: 20, delay: 0.3, scatter: 0.2, pitchJitter: 0, spread: 0.8),
		buf: 4,
		func: { |sig, p, buf|
			var frames = BufFrames.kr(buf);
			var write = Phasor.ar(0, 1, 0, frames);
			var trig = Dust.ar(p[\density]);
			var back = (p[\delay] + TRand.ar(0, p[\scatter], trig)).clip(0, 3.5) * BufSampleRate.kr(buf);
			var pos = (write - back).wrap(0, frames) / frames;
			var rate = TRand.ar(p[\pitchJitter].neg, p[\pitchJitter], trig).midiratio;
			BufWr.ar(sig.sum * 0.5, buf, write);
			GrainBuf.ar(2, trig, p[\grainDur], buf, rate, pos, 2, TRand.ar(p[\spread].neg, p[\spread], trig))
		})
);
~fxOrder = [\tail, \fbDelay, \reverb, \granulator, \decimate];   // ~withFx's default chain

// Wet signal of effect `name` on stereo `sig`, mixed by its mix control. `ctl` makes a
// control from (key, default): plain names per bus, "<effect>_<key>" per note.
~fxApply = { |name, sig, ctl, buf|
	var e = ~fxLib[name], p = ();
	e[\defaults].keysValuesDo { |key, value| p[key] = ctl.(key, value).lag(0.1) };
	XFade2.ar(sig, e[\func].(sig, p, buf), (ctl.(\mix, 0).lag(0.1) * 2) - 1)
};

~buildFx = {
	~fxLib.keysValuesDo { |name, e|
		// reads and replaces its pattern's private bus; on gate 0 (pattern stopped) it fades
		// out over `release` s, still processing, so tails ring on
		SynthDef(("fx_" ++ name).asSymbol, { |out, gate = 1, release = 0.05, buf = 0|
			var sig = ~fxApply.(name, In.ar(out, 2), { |key, value| NamedControl.kr(key, value) }, buf);
			ReplaceOut.ar(out, sig * EnvGen.kr(Env.asr(0, 1, release.max(0.01), \lin), gate, doneAction: 2));
		}).add;
	};
	// glide a control bus from its current value to `to` over `time` s (curve as in Env)
	SynthDef(\fx_glide, { |out, to = 0, time = 1, curve = 0|
		var from = Latch.kr(In.kr(out), Impulse.kr(0));
		ReplaceOut.kr(out, EnvGen.kr(Env([from, to], [time], curve), doneAction: 2));
	}).add;
	// LFO on a control bus between lo and hi, `period` s per cycle; shape 0 sine (starting at
	// lo), 1 triangle, 2 smooth random
	SynthDef(\fx_lfo, { |out, period = 5, lo = 0, hi = 1, shape = 0|
		var f = 1 / period.max(0.01);
		var wave = Select.kr(shape, [SinOsc.kr(f, 1.5pi), LFTri.kr(f, 3), LFNoise1.kr(f)]);
		ReplaceOut.kr(out, wave.range(lo, hi));
	}).add;
};

// PER NOTE: use inside a SynthDef function. Adds "<effect>_<param>" and "<effect>_mix"
// (default 0, so each effect is off until a note sets its mix).
~noteFx = { |sig, effects|
	var feedback = effects.select { |name| ~fxLib[name] !? { |e| e[\feedback] } ? false };
	if(feedback.size > 1) {
		Error("~noteFx: % all use LocalIn; only one per SynthDef".format(feedback)).throw;
	};
	effects.do { |name|
		var e = ~fxLib[name];
		case
		{ e.isNil } { Error("~noteFx: no effect % (have %)".format(name, ~fxLib.keys.asArray.sort)).throw }
		{ e[\buf].notNil } { "~noteFx: % needs a buffer; per bus only (skipped)".format(name).warn }
		{ sig = ~fxApply.(name, sig, { |key, value| NamedControl.kr((name ++ "_" ++ key).asSymbol, value) }) };
	};
	sig
};

~fxBuses = ~fxBuses ? ();   // pattern name -> (effect -> (param -> Bus))
~fxNodes = ~fxNodes ? ();   // pattern name -> (effect -> (param -> glide / LFO synth))
~fxBufs = ~fxBufs ? ();     // pattern name -> (effect -> Buffer)

~fxFree = { |name|
	~fxNodes[name] !? { |fx| fx.do { |ps| ps.do { |n| if(n.isPlaying) { n.free } } } };
	~fxBuses[name] !? { |fx| fx.do { |ps| ps.do(_.free) } };
	~fxBufs[name] !? { |fx| fx.do(_.free) };
	~fxNodes[name] = nil; ~fxBuses[name] = nil; ~fxBufs[name] = nil;
};

// PER BUS: `pattern` through `effects` (first = nearest the notes), with fresh control buses
// at the defaults (all dry). `base`: extra event keys for every note and effect (e.g. out).
// `tail`: s the effects keep processing after the pattern stops, then fade.
~withFx = { |name, pattern, effects, base, tail = 2|
	var buses = (), bufs = ();
	effects = effects ? ~fxOrder;
	~fxFree.(name);
	effects.do { |fx|
		var e = ~fxLib[fx];
		if(e.isNil) { Error("~withFx: no effect % (have %)".format(fx, ~fxLib.keys.asArray.sort)).throw };
		buses[fx] = ();
		(e[\defaults] ++ (mix: 0)).keysValuesDo { |param, value| buses[fx][param] = Bus.control(s, 1).set(value) };
		e[\buf] !? { |secs| bufs[fx] = Buffer.alloc(s, s.sampleRate * secs, 1) };
	};
	~fxBuses[name] = buses; ~fxBufs[name] = bufs; ~fxNodes[name] = ();
	Pchain(effects.inject(pattern) { |pat, fx|
		var pairs = [\release, tail.max(0.05)];
		bufs[fx] !? { |b| pairs = pairs ++ [\buf, b.bufnum] };
		buses[fx].keysValuesDo { |param, bus| pairs = pairs ++ [param, bus.asMap] };
		Pfxb(pat, ("fx_" ++ fx).asSymbol, *pairs)
	}, (base ? ()) ++ (endTime: tail.max(0.05)))   // endTime: how long Pbus keeps the bus after a stop
};

~fxBus = { |name, effect, param|
	var bus = ~fxBuses[name] !? { |fx| fx[effect] } !? { |ps| ps[param] };
	bus ?? {
		"no % / % / % (effects of %: %; parameters of %: %)".format(name, effect, param,
			name, ~fxBuses[name] !? { |fx| fx.keys.asArray.sort },
			effect, ~fxLib[effect] !? { |e| (e[\defaults].keys.asArray ++ [\mix]).sort }).warn;
		nil
	}
};

~fxStop = { |name, effect, param|
	var node = ~fxNodes[name] !? { |fx| fx[effect] } !? { |ps| ps[param] };
	node !? { if(node.isPlaying) { node.free }; ~fxNodes[name][effect][param] = nil };
};

~fxRun = { |name, effect, param, def, args|
	var node;
	~fxStop.(name, effect, param);
	node = Synth(def, [\out, ~fxBuses[name][effect][param].index] ++ args, s.defaultGroup, \addToHead);
	NodeWatcher.register(node, true);
	~fxNodes[name][effect] = ~fxNodes[name][effect] ? ();
	~fxNodes[name][effect][param] = node;
};

~fx = { |name, effect, param, value, time = 0, curve = 0|
	~fxBus.(name, effect, param) !? { |bus|
		if(time <= 0) { ~fxStop.(name, effect, param); bus.set(value) } {
			~fxRun.(name, effect, param, \fx_glide, [\to, value, \time, time, \curve, curve]);
		};
	};
};

~fxLfo = { |name, effect, param, period = 5, lo = 0, hi = 1, shape = \sine|
	~fxBus.(name, effect, param) !? {
		~fxRun.(name, effect, param, \fx_lfo, [\period, period, \lo, lo, \hi, hi,
			\shape, [\sine, \tri, \noise].indexOf(shape) ? 0]);
	};
};

~fxShow = { |name|
	(~fxBuses[name] ? ()).keysValuesDo { |fx, ps|
		ps.keys.asArray.sort.do { |param|
			ps[param].get { |v| "% %.% = %".format(name, fx, param, v.round(0.001)).postln };
		};
	};
};

// PER NOTE settings, through ~glide / ~lfo (glide.scd): key "<effect>_<param>"
~nfx = { |proxy, effect, param, value, time = 0, curve = 0, from|
	var key = (effect ++ "_" ++ param).asSymbol;
	if(time <= 0) {
		proxy.set(key, value);
		if(~glideLast[proxy].isNil) { ~glideLast[proxy] = IdentityDictionary.new };
		~glideLast[proxy][key] = if(value.isNumber) { value };   // a pattern has no "last value"
	} {
		~glide.(proxy, key, value, time, curve, from);
	};
};

~nfxLfo = { |proxy, effect, param, period = 5, lo = 0, hi = 1|
	~lfo.(proxy, (effect ++ "_" ++ param).asSymbol, period, lo, hi);
};
)
