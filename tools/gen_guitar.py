#!/usr/bin/env python3
"""Render one guitar sample per MIDI pitch with MuseScore 4 + Muse Sounds.

Each pitch: a whole note tied across NOTE_MEASURES measures (MuseScore releases
at the written end even with l.v.), mf, l.v. on the last note, then empty
measures. The check verifies the sound decayed before the release. Renders are trimmed of leading/trailing silence and
written to samples/Guitar_Samples/{N}.wav (mono).

usage: python3 tools/gen_guitar.py [lo hi]   (default 40 88)
"""
import json
import re
import subprocess
import sys
from pathlib import Path

MSCORE = "/Applications/MuseScore 4.app/Contents/MacOS/mscore"
ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build" / "guitar"
OUT = ROOT / "samples" / "Guitar_Samples"

TEMPO = 60          # bpm; whole note = 4 s
NOTE_MEASURES = 4   # tied whole notes: 16 s of ring time before release
TAIL_MEASURES = 1   # empty measures after the note
SILENCE_DB = -70    # trim threshold
CUTOFF_DB = -70     # level just before release must be quieter than this

NAMES = [("C", 0), ("C", 1), ("D", 0), ("D", 1), ("E", 0), ("F", 0),
         ("F", 1), ("G", 0), ("G", 1), ("A", 0), ("A", 1), ("B", 0)]


def musicxml(midi):
    step, alter = NAMES[midi % 12]
    octave = midi // 12 - 1
    alter_xml = f"<alter>{alter}</alter>" if alter else ""
    pitch = f"<pitch><step>{step}</step>{alter_xml}<octave>{octave}</octave></pitch>"

    def note(i):
        last = i == NOTE_MEASURES
        ties = ("" if i == 1 else '<tie type="stop"/>') + ('<tie type="let-ring"/>' if last else '<tie type="start"/>')
        tied = ("" if i == 1 else '<tied type="stop"/>') + ('<tied type="let-ring"/>' if last else '<tied type="start"/>')
        return f"<note>{pitch}<duration>4</duration>{ties}<type>whole</type><notations>{tied}</notations></note>"

    rest = '<note><rest measure="yes"/><duration>4</duration></note>'
    measures = "".join(f'<measure number="{i}">{note(i)}</measure>' for i in range(2, NOTE_MEASURES + 1))
    measures += "".join(f'<measure number="{i}">{rest}</measure>'
                        for i in range(NOTE_MEASURES + 1, NOTE_MEASURES + 1 + TAIL_MEASURES))
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 4.0 Partwise//EN" "http://www.musicxml.org/dtds/partwise.dtd">
<score-partwise version="4.0">
 <part-list><score-part id="P1"><part-name>Acoustic Guitar</part-name>
  <score-instrument id="P1-I1"><instrument-name>Acoustic Guitar</instrument-name></score-instrument>
 </score-part></part-list>
 <part id="P1">
  <measure number="1">
   <attributes><divisions>1</divisions><key><fifths>0</fifths></key><time><beats>4</beats><beat-type>4</beat-type></time>
    <clef><sign>G</sign><line>2</line><clef-octave-change>-1</clef-octave-change></clef></attributes>
   <direction placement="above"><direction-type><metronome><beat-unit>quarter</beat-unit><per-minute>{TEMPO}</per-minute></metronome></direction-type><sound tempo="{TEMPO}"/></direction>
   <direction placement="below"><direction-type><dynamics><mf/></dynamics></direction-type><sound dynamics="80"/></direction>
   {note(1)}
  </measure>
  {measures}
 </part>
</score-partwise>
"""


def max_db(path, start=None, dur=None):
    cmd = ["ffmpeg", "-hide_banner", "-nostats"]
    if start is not None:
        cmd += ["-ss", str(start)]
    if dur is not None:
        cmd += ["-t", str(dur)]
    cmd += ["-i", str(path), "-af", "volumedetect", "-f", "null", "-"]
    err = subprocess.run(cmd, capture_output=True, text=True).stderr
    m = re.search(r"max_volume: (-?[\d.]+|-inf) dB", err)
    return float(m.group(1)) if m else float("-inf")


def duration(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                          "-of", "csv=p=0", str(path)], capture_output=True, text=True).stdout
    return float(out)


def main():
    lo, hi = (int(a) for a in sys.argv[1:3]) if len(sys.argv) >= 3 else (40, 88)
    BUILD.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)

    jobs = []
    for n in range(lo, hi + 1):
        xml = BUILD / f"{n}.musicxml"
        xml.write_text(musicxml(n))
        jobs.append({"in": str(xml), "out": str(BUILD / f"{n}.wav")})
    job_file = BUILD / "job.json"
    job_file.write_text(json.dumps(jobs, indent=1))

    print(f"rendering {len(jobs)} files...")
    subprocess.run([MSCORE, "-j", str(job_file)], capture_output=True)

    problems = []
    for job in jobs:
        raw, name = Path(job["out"]), Path(job["out"]).name
        if not raw.exists():
            problems.append(f"{name}: not rendered")
            continue
        if max_db(raw) < -60:
            problems.append(f"{name}: silent (out of instrument range?)")
            continue
        release = NOTE_MEASURES * 4 * 60 / TEMPO
        tail = max_db(raw, start=release - 0.5, dur=0.5)
        if tail > CUTOFF_DB:
            problems.append(f"{name}: still sounding at release ({tail} dB), raise NOTE_MEASURES")
        trim = (f"silenceremove=start_periods=1:start_threshold={SILENCE_DB}dB,"
                f"areverse,silenceremove=start_periods=1:start_threshold={SILENCE_DB}dB,areverse")
        subprocess.run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-i", str(raw),
                        "-af", trim, "-ac", "1", "-c:a", "pcm_s24le", str(OUT / name)], check=True)
        print(f"{name}: {duration(OUT / name):.2f} s")

    print("\n".join(problems) if problems else "all good")


if __name__ == "__main__":
    main()
