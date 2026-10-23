# Markov Guitars

A SuperCollider patch for composing with texture. Four voices improvise melodies with **Markov chains** learned from MIDI files (Für Elise, a C major scale, or your own) and play them on sampled guitar. Shape the texture with register, density, scale, dynamics and a rack of effects, and write **cues**: blocks of changes that fire together.

```supercollider
~cue.("the floor tilts", {
	~scale.(\all, Scale.harmonicMinor);
	~rangeLfo.(\all, \low, 30, 40, 70);                 // the lowest note rises and falls
	~fx.([\pb1, \pb3], \decimate, \mix, 1);
	~fxLfo.([\pb1, \pb3], \decimate, \factor, 12, 1, 35); // grit comes in waves
});
```

---

## What you need

- A Mac (Apple silicon or Intel)
- [SuperCollider](https://supercollider.github.io/downloads) 3.13 or newer
- [git](https://git-scm.com/downloads). Typing `git --version` in Terminal offers to install it if it's missing.
- A free [GitHub](https://github.com/signup) account

The guitar samples (about 90 MB) aren't stored in this repository. The patch downloads them the first time you run it.

---

## 1. Fork this repository

A fork is your own copy of the project on GitHub. You can change it freely, and I can still send you updates.

1. Sign in to GitHub and open **https://github.com/twmcdunn/karls-project**.
2. Click **Fork** (top right), then **Create fork**.

You now have `https://github.com/YOUR-USERNAME/karls-project`.

## 2. Clone your fork to your Mac

Open **Terminal** and run the following, replacing `YOUR-USERNAME` with your GitHub username:

```bash
cd ~/Documents
git clone https://github.com/YOUR-USERNAME/karls-project.git
cd karls-project
```

The project is now in `~/Documents/karls-project`.

> [!TIP]
> The first time you `git push`, GitHub asks you to sign in. The easiest way is to install the [GitHub CLI](https://cli.github.com) and run `gh auth login` once.

## 3. Run it

1. Open **`patch.scd`** in SuperCollider (double-click it, or File > Open in the SuperCollider IDE).
2. Click inside the **MAIN BLOCK** (the code between the first `(` and `)`) and press **Cmd-Return**.
3. The first time, a window asks to download the guitar samples. Click **Proceed** and wait.
4. When the Post window shows **`READY`**, go down the file and run lines one at a time with **Shift-Return**, or a whole cue block with **Cmd-Return**:
   ```supercollider
   ~play.(\all);
   ```
5. **Cmd-period** stops all sound. `~play.(\all)` starts again; you don't need to rerun the main block.

The patch is a tour: **1** play and stop, **2** the toolbox (range, density, rhythm, scale, dynamics), **3** effects and LFOs, **4** an example piece in five cues, **5** switching melodies and adding your own MIDI files, and **6** a template for your own cues.

## 4. Save your work to GitHub

Whenever you've written something you want to keep:

```bash
cd ~/Documents/karls-project
git add -A
git commit -m "Cues for the opening section"
git push
```

---

## 5. Getting updates from me (pull requests)

When I add a feature or fix something, I'll send it to your fork as a **pull request** (PR). GitHub emails you, and the PR appears under the **Pull requests** tab of your fork.

1. Open the pull request. Read the description, and look at **Files changed** to see exactly what's different.
2. If you're happy with it, click **Merge pull request**, then **Confirm merge**. Ask me if anything is unclear; you can comment on the PR.
3. Bring the change down to your Mac:
   ```bash
   cd ~/Documents/karls-project
   git pull
   ```
4. In SuperCollider, rerun the **MAIN BLOCK** so the new code loads.

> [!IMPORTANT]
> **Commit and push your own work before merging a PR** (step 4 above). Then `git pull` combines my changes with yours.

If GitHub says the PR **can't be merged automatically**, we both changed the same lines (usually in `patch.scd`). Don't worry: leave it, tell me, and I'll update the PR so it merges cleanly.

> [!TIP]
> Write your own cues at the bottom of `patch.scd`, in section 6, or in a new file of your own. My updates rarely touch those, so merges stay simple.

---

## What's in here

| Path | What it is |
|---|---|
| `patch.scd` | **Start here.** The main block plus every control, effect and cue, with explanations |
| `fur_elise.mid`, `scale.mid` | Melodies the Markov chains learn from. Add your own `.mid` files here |
| `dependencies/texture.scd` | The voices and their controls (`~range`, `~density`, `~fx`, `~cue`, ...) |
| `dependencies/markov.scd` | Reads MIDI files and builds and plays the Markov chains |
| `dependencies/pattern-fx.scd` | The effects (filters, drive, ring mod, decimator, delay, granulator, reverb) |
| `dependencies/glide.scd` | Gradual changes and LFOs for the voices' settings |
| `dependencies/sample-install.scd` | Downloads the samples from the latest [twmcdunn/samples](https://github.com/twmcdunn/samples/releases/latest) release |
| `tools/gen_guitar.py` | How the guitar samples were made (MuseScore 4 + Muse Sounds); you don't need it to play |

The samples install into `~/Library/Application Support/SuperCollider/sounds/twm_samples/`, outside this folder.

## Troubleshooting

- **"Save this file first"**: SuperCollider needs `patch.scd` saved, because it finds the other files relative to it.
- **Nothing downloads, or "Installation failed"**: check your internet connection, then run the main block again.
- **No sound**: check the Post window for `READY`, your Mac's output device and volume, and that you ran `~play.(\all)`.
- **The server won't boot ("mismatched sample rates")**: open *Audio MIDI Setup*, set your output device to 48000 Hz, and run the main block again.
