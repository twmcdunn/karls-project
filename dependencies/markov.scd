// N-order Markov chain built from a MIDI melody in C major.
//
// Notes are C-major scale degrees with 0 = middle C (MIDI 60), so 7 = C5,
// -1 = B3. This matches Pbind's \degree with the default scale and octave.
// Chromatic notes become the lower degree + 0.1 (SC's sharp convention), e.g. C# = 0.1.
//
// Pitch only:
//   map = ~markovFromMidi.(path, order)
//   Dictionary: "0-1-2" -> [[probabilities], [next degrees]]
//
// Pitch + rhythm (each state is [degree, dur], dur in beats):
//   map = ~markovRhythmFromMidi.(path, order, quant)
//   Dictionary: "0:1-1:0.5" -> [[probabilities], [[degree, dur], ...]]
//   dur = time to the next note's onset, so rests are folded into the note before them.
//   quant (beats, e.g. 0.25) snaps onsets to a grid first; use it for played-in MIDI.
//
// Keys exist for every context length 0..order ("" is the overall distribution).
// Both kinds of map work with:
//   ~markovNext.(map, history)             -> next state, from the longest matching key
//   ~markovPattern.(map, order, length)    -> pattern of states
//     Pbind(\degree, ~markovPattern.(m, 2))
//     Pbind([\degree, \dur], ~markovPattern.(m, 2))

(
// -> [[midi, dur], ...] in time order (dur in beats, to the next onset).
// Merges all tracks, skips drums (channel 10), and keeps the highest note when
// several start together.
~midiEvents = { |path, quant = 0|
	var file, bytes, pos, readN, readVLQ, hlen, ntrks, division;
	var ons = List[], offs = List[], melody = List[], last, lastOff, lastDur;
	file = File(path, "rb");
	if(file.isOpen.not) { Error("Can't open MIDI file: " ++ path).throw };
	bytes = Int8Array.newClear(file.length);
	file.read(bytes);
	file.close;
	bytes = bytes.as(Array).collect { |b| b & 255 };
	if(bytes.copyRange(0, 3) != "MThd".ascii) { Error("Not a MIDI file: " ++ path).throw };

	readN = { |n| var v = 0; n.do { v = (v << 8) + bytes[pos]; pos = pos + 1 }; v };
	readVLQ = { var v = 0, b = 128;
		while { b >= 128 } { b = bytes[pos]; pos = pos + 1; v = (v << 7) + (b & 127) };
		v
	};

	pos = 4;
	hlen = readN.(4);
	pos = 10;
	ntrks = readN.(2);
	division = readN.(2); // ticks per quarter note
	pos = 8 + hlen;

	ntrks.do {
		var id = bytes.copyRange(pos, pos + 3), len, end, tick = 0, status = 0, type, d1, d2;
		pos = pos + 4;
		len = readN.(4);
		end = pos + len;
		if(id == "MTrk".ascii) {
			while { pos < end } {
				tick = tick + readVLQ.();
				if(bytes[pos] >= 128) { status = bytes[pos]; pos = pos + 1 }; // else running status
				case
				// read the length first: `pos + readVLQ.()` would use pos from before the read
				{ status == 255 } { pos = pos + 1; d1 = readVLQ.(); pos = pos + d1 }        // meta
				{ (status == 240) or: { status == 247 } } { d1 = readVLQ.(); pos = pos + d1 } // sysex
				{
					type = status & 240;
					d1 = bytes[pos]; pos = pos + 1;
					d2 = 0;
					if((type != 192) and: { type != 208 }) { d2 = bytes[pos]; pos = pos + 1 };
					if((status & 15) != 9) {
						case
						{ (type == 144) and: { d2 > 0 } } { ons.add([tick / division, d1]) }
						{ (type == 128) or: { type == 144 } } { offs.add([tick / division, d1]) };
					};
				};
			};
		};
		pos = end;
	};

	if(quant > 0) { ons.do { |n| n[0] = n[0].round(quant) } };
	ons.sort { |a, b| if(a[0] == b[0]) { a[1] >= b[1] } { a[0] < b[0] } };
	ons.do { |n| if(melody.isEmpty or: { melody.last[0] != n[0] }) { melody.add(n) } };

	// dur = gap to the next onset; the last note lasts until its note-off
	offs.sort { |a, b| a[0] < b[0] };
	melody.collect { |n, i|
		if(i < (melody.size - 1)) {
			[n[1], melody[i + 1][0] - n[0]]
		} {
			lastOff = offs.detect { |o| (o[1] == n[1]) and: { o[0] > n[0] } };
			lastDur = if(lastOff.notNil) { lastOff[0] - n[0] } { 1 };
			if(quant > 0) { lastDur = lastDur.round(quant).max(quant) };
			[n[1], lastDur]
		}
	}.asArray
};

~midiNotes = { |path| ~midiEvents.(path).collect { |e| e[0] } };

~midiToDegree = { |midi|
	var scale = [0, 2, 4, 5, 7, 9, 11];
	var rel = midi - 60, oct = (rel / 12).floor.asInteger, pc = rel % 12, idx;
	idx = scale.indexOf(pc);
	if(idx.notNil) { (oct * 7) + idx } { (oct * 7) + scale.indexOf(pc - 1) + 0.1 }
};

// State -> key token: 2 -> "2", [2, 0.5] -> "2:0.5". Rounded, and 1 / 1.0 both print "1",
// so float noise can't split one state into two keys.
~markovToken = { |x|
	var num = { |v| v = v.round(0.001); if(v == v.round) { v.round.asInteger.asString } { v.asString } };
	if(x.isArray) { x.collect(num).join(":") } { num.(x) }
};

// seq: array of states -> Dictionary of context string -> [[probs], [nexts]]
~markovBuild = { |seq, order = 2|
	var tok = ~markovToken, toks = seq.collect { |x| tok.(x) };
	var counts = Dictionary.new, states = Dictionary.new, map = Dictionary.new;
	seq.do { |x, i| states[toks[i]] = x };
	(0..order).do { |k|
		(k..(seq.size - 1)).do { |i|
			var key = if(k == 0) { "" } { toks.copyRange(i - k, i - 1).join("-") };
			var next = toks[i];
			if(counts[key].isNil) { counts[key] = Dictionary.new };
			counts[key][next] = (counts[key][next] ? 0) + 1;
		};
	};
	counts.keysValuesDo { |key, nexts|
		var total = nexts.values.sum;
		var nextStates = nexts.keys.asArray.collect { |t| states[t] }.sort { |a, b|
			var aa = a.asArray, ba = b.asArray, i = 0;
			while { (i < (aa.size - 1)) and: { aa[i] == ba[i] } } { i = i + 1 };
			aa[i] <= ba[i]
		};
		map[key] = [nextStates.collect { |s| nexts[tok.(s)] / total }, nextStates];
	};
	map
};

~markovFromMidi = { |path, order = 2|
	var toDegree = ~midiToDegree;
	~markovBuild.(~midiNotes.(path).collect { |m| toDegree.(m) }, order)
};

~markovRhythmFromMidi = { |path, order = 2, quant = 0|
	var toDegree = ~midiToDegree;
	~markovBuild.(~midiEvents.(path, quant).collect { |e| [toDegree.(e[0]), e[1]] }, order)
};

// Picks the next state using the longest suffix of history found in map.
~markovNext = { |map, history|
	var tok = ~markovToken, toks = history.collect { |x| tok.(x) }, k = history.size, entry;
	entry = map[toks.join("-")];
	while { entry.isNil and: { k > 0 } } {
		k = k - 1;
		entry = map[if(k == 0) { "" } { toks.keep(k.neg).join("-") }];
	};
	entry !? { entry[1].wchoose(entry[0]) }
};

~markovPattern = { |map, order = 2, length = inf|
	var next = ~markovNext;
	Prout {
		var history = [];
		length.do {
			var d = next.(map, history);
			d.yield;
			history = history.add(d).keep(order.neg);
		};
	}
};
)
