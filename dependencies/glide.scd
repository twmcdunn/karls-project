// Gradual changes for per-note pattern parameters, timed in seconds (the same timebase whether
// called live from the interpreter, from a cue, or from a pattern) rather than in notes -- so
// it works for non-metrical patterns with irregular \dur.
//
//   ~glide.(~pb1, \pitched, 0.7, 20);         // from its last value to 0.7 over 20 s, then hold
//   ~glide.(~pb1, \amp, 0, 30, -4);           // curve as in Env: 0 linear, negative = fast start
//   ~glide.(~pb1, \pitched, 0, 10, 0, 0.7);   // give the start value explicitly
//   ~glideNotes.(~pb1, \density, 1, 16);     // over the next 16 notes instead of seconds
//   ~lfo.(~pb1, \pitched, 5, 0, 1);          // sine between 0 and 1, 5 s per cycle
//
// Each note takes the value of the ramp at the moment it starts. ~glide remembers the target
// as the start of the next glide for that pattern and parameter; if the parameter was last
// set some other way, pass `from`.

(
~glideLast = ~glideLast ? IdentityDictionary.new;

~glide = { |proxy, key, to, time = 10, curve = 0, from|
	var last, start, t0 = thisThread.seconds;
	if(~glideLast[proxy].isNil) { ~glideLast[proxy] = IdentityDictionary.new };
	last = ~glideLast[proxy];
	start = from ?? { last[key] } ?? {
		("~glide: no previous % for this pattern; starting from %".format(key, to)).warn;
		to
	};
	// Timed from this call, whenever the proxy picks the change up (it can wait for the
	// next beat): each note gets the ramp's value at the moment it starts.
	proxy.set(key, Pfunc {
		var x = ((thisThread.seconds - t0) / time.max(1e-6)).clip(0, 1);
		start + ((to - start) * if(curve == 0) { x } { (1 - exp(curve * x)) / (1 - exp(curve)) })
	});
	last[key] = to;
};

// ~glideNotes.(~pb1, \density, 1, 16): like ~glide, but over the next `notes` notes instead of
// seconds -- one step per note, then hold. Use it for anything that sets the time to the next
// note (e.g. density -> \dur): a time-based glide would jump while a long gap is already
// committed, whereas this advances only as notes actually happen.
~glideNotes = { |proxy, key, to, notes = 16, curve = 0, from|
	var last, start, env;
	if(~glideLast[proxy].isNil) { ~glideLast[proxy] = IdentityDictionary.new };
	last = ~glideLast[proxy];
	start = from ?? { last[key] } ?? {
		("~glideNotes: no previous % for this pattern; starting from %".format(key, to)).warn;
		to
	};
	env = Env([start, to], [1], curve);
	notes = notes.asInteger.max(1);
	proxy.set(key, Pseq([Pseq(notes.collect { |i| env.at((i + 1) / notes) }), Pn(to)]));
	last[key] = to;
};

// ~lfo.(~pb1, \pitched, 5, 0, 1): sweep a per-note parameter with a sine, `period` seconds per
// cycle, between lo and hi, starting at lo. Each note takes the value at the moment it
// starts. A later ~glide or .set on the same key replaces it (give ~glide a `from`).
~lfo = { |proxy, key, period = 5, lo = 0, hi = 1|
	var t0 = thisThread.seconds;
	if(~glideLast[proxy].isNil) { ~glideLast[proxy] = IdentityDictionary.new };
	~glideLast[proxy][key] = nil;
	proxy.set(key, Pfunc {
		var phase = (thisThread.seconds - t0) / period.max(0.01);
		lo + ((hi - lo) * (1 - cos(2pi * phase)) * 0.5)
	});
};
)
