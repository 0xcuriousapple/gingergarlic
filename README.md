# gingergarlic 🫚

turn your blabber into sentences before you hit send.

a tiny macOS menu bar tool: select your rough draft anywhere (slack, telegram,
wherever), hit a hotkey, and it's rewritten in place — typos fixed, rambling
trimmed, but still *you*. lowercase stays lowercase, "lmao" stays "lmao",
"gotta bounce" never becomes "have to leave".

runs 100% on-device using apple's foundation models (the apple intelligence
model). no cloud, no api keys, no ollama, ~1s per rewrite.

## flow

1. type your draft: `so basically i was like thinking we could um do the thing tommow`
2. `⌘A` to select it
3. `⌃⌥⌘G`
4. it's replaced in place: `i was thinking we could do the thing tomorrow`

## requirements

- macOS 26 (tahoe) on apple silicon
- apple intelligence enabled (system settings → apple intelligence & siri)
- xcode command line tools (`xcode-select --install`)

## install

```sh
git clone https://github.com/0xcuriousapple/gingergarlic.git
cd gingergarlic
./make-app.sh
open dist/gingergarlic.app
```

a HUD pill confirms it's running and shows the hotkey. look for 🫚 in the
menu bar (if you don't see it, the notch is probably hiding it — the app
still works).

**first run:** press the hotkey once on selected text. macOS will ask you to
grant **accessibility** permission (needed to synthesize the ⌘C/⌘V
keystrokes). grant it in system settings → privacy & security →
accessibility, then press the hotkey again.

to launch at login: system settings → general → login items → add
`dist/gingergarlic.app`.

## make it sound like you

the style prompt lives at `~/.config/gingergarlic/style.md` (menu bar →
"edit style prompt"). it's reloaded on every rewrite, so edits apply
instantly — no restart.

the biggest quality lever is the `draft:` / `rewrite:` example pairs.
replace the defaults with real before/after pairs of your own messages and
the model will mirror your voice much harder.

your shorthand is also protected in code, not just prompt: if your draft
contains `u`, `tmrw`, `r`, `tho`, `thru`, `pls`, `ngl`, etc., any expansion
the model sneaks in ("u" → "you") is deterministically swapped back. edit the
list in `Sources/GingerGarlic/Rewriter.swift` to match your own shorthand.

## change the hotkey

default is `⌃⌥⌘G`. if it clashes with another app, edit
`~/.config/gingergarlic/hotkey.txt` (menu bar → "change hotkey"), e.g.
`ctrl+opt+r` or `cmd+shift+9`, then relaunch. if the combo is already taken
by another app, the HUD and menu warn you on launch.

## menu bar

- **copy original (undo)** — puts the pre-rewrite text back on your clipboard
- **copy last rewrite** — re-copy the last output
- **edit style prompt** / **change hotkey**
- **quit**

## it learns your style as you use it

every rewrite is logged as a draft → rewrite pair to
`~/.config/gingergarlic/corpus.jsonl`. on each hotkey press, the most
similar past pairs (on-device sentence embeddings, most recent as fallback)
are injected into the prompt as extra few-shot examples — so the more you
use it, the more it sounds like you.

pressing **copy original (undo)** marks the last rewrite as rejected: it's
kept out of the example pool and flagged in the corpus. the menu bar shows
how many pairs it has learned.

### LoRA adapter (optional, the endgame)

once your corpus is big enough (~200+ accepted pairs), you can train a
personal LoRA adapter for the on-device model with apple's adapter training
toolkit:

```sh
python3 scripts/export_training_data.py   # corpus -> train.jsonl / valid.jsonl
```

then train with the toolkit (developer.apple.com, search "foundation models
adapter training toolkit") and drop the result at
`~/.config/gingergarlic/adapter.fmadapter`. relaunch — the menu will show
"+ LoRA adapter" and every rewrite now runs through a model fine-tuned on
your own messages.

## how it works

- carbon `RegisterEventHotKey` for the global hotkey (no accessibility needed
  for listening)
- on press: saves your clipboard → synthetic ⌘C via `CGEvent` → runs the
  selection through a deterministic spellcheck pre-pass → sends it to
  `LanguageModelSession` (greedy sampling, fresh session per rewrite) →
  pastes the result with ⌘V → restores your clipboard
- prompt is framed as `draft: … rewrite:` matching the few-shot examples, so
  the model rewrites your text instead of chatting with it
- spelling is fixed twice, for different reasons: `NSSpellChecker` catches
  clear-cut typos deterministically before the model ever sees them (so it
  can't guess the wrong correction), and the model still catches
  context-dependent mistakes ("grate" → "great") a dictionary can't
- spellchecker guesses are re-ranked by damerau-levenshtein distance: a
  candidate one edit away overrides a top guess that's two or more edits out
  ("depoly" → "deploy", not "deeply"), otherwise the dictionary's frequency
  ranking wins ("tommow" → "tomorrow", not "tommy")
- a deterministic post-pass restores any shorthand the model expanded
- every accepted rewrite feeds the corpus that personalizes future rewrites
  (`Corpus.swift`: NLEmbedding cosine retrieval + recency backfill)

no dependencies, plain swiftpm. relaunching always replaces the previous
instance, so `open dist/gingergarlic.app` is always safe.

## troubleshooting

**it keeps asking for accessibility even though the toggle is on** — the app
is ad-hoc signed, so every rebuild invalidates the grant (the toggle points
at the old binary). fix:

```sh
tccutil reset Accessibility xyz.curiousapple.gingergarlic
open dist/gingergarlic.app   # re-grant when prompted
```

permanent fix: get a free apple development cert (xcode → settings →
accounts → add your apple id) and swap `-s -` in `make-app.sh` for your
identity.

**"model unavailable" in the menu** — enable apple intelligence in system
settings and wait for the on-device model download to finish.

**nothing happens on hotkey** — check the menu bar status line; it tells you
whether the hotkey registered, accessibility is granted, and what went wrong
last.

## roadmap

- ~~learn from real usage: log accepted rewrites, build a personal corpus~~ ✅
- ~~retrieval few-shot: pull your most similar past messages as examples per
  rewrite~~ ✅
- LoRA adapter trained on your message history via apple's adapter toolkit —
  export + in-app loading are done, training is on you (needs ~200+ pairs)
- seed the corpus from a slack/telegram export instead of starting cold

## license

MIT
