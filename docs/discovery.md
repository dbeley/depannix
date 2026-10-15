# Discovery: making the medium describe itself

Status: design note. The enabler is committed; none of the bricks below are
written yet, and the decisions at the end are open.

## Why this is the gap

The project spent its effort making the composition *provable by a third party*
— a manifest, a signature, an attestation, a reproducible build. It spent almost
none making it *legible to the person holding the stick*. Measured today, the
image contains no motd, no alias, no help command and no way to list what it
carries. The inventory exists in three places, all of them off the medium:
`nix/tool-catalog.nix`, the release manifest, and `docs/budget.md`.

That inverts the situation it is meant for. A rescue medium is picked up because
a machine is dead — no network, no repository, nobody to ask. The medium should
answer, by itself, five questions:

| Reader | Question |
|---|---|
| the operator, 3 a.m., offline | what do I do about this failure? |
| whoever finds the stick | what is this, and what can it do? |
| the auditor | what exactly is inside, and how do I prove it? |

## What the image already carries

The discovery layer is, in effect, already paid for. Measured against the
published manifest (732 paths, x86_64):

| Brick | Present |
|---|---|
| `fzf`, `ripgrep`, `fd` | yes — optional set, enabled by default |
| `bash-interactive`, `bash-completion` | yes |
| `nano`, `less`, `jq`, `gnugrep`, `util-linux` | yes |
| `dialog`, `whiptail` | **no** — a TUI menu would be a new, measurable dependency |

So a categorised catalogue that is fuzzy-searched and tab-completed costs
nothing in bytes. What is missing is content and hooks, not machinery.

## The enabler, done

`nix/tool-catalog.nix` now holds one entry per tool — `name`, `category`, and the
`gesture` it covers — and `modules/tools.nix` only wires it. Two consequences
worth stating:

- the catalogue cannot lie about what ships, because it is *what* ships: there is
  no separate list to drift from, so this needs no CI check;
- the project rule grew its missing half. It was "no tool without its closure
  figure"; it is now also "no tool without its gesture", enforced by an
  assertion. Both were tested by deliberately inserting two bad entries and
  reading the refusal.

The change was proven inert: both ISO derivations are byte-identical before and
after (`nix eval .#minimal.drvPath`).

## The bricks

1. **A greeting at login.** Three lines: which release, which architecture, where
   you are (root on a live medium), and the two commands worth knowing. A few
   hundred bytes, generated at build time so it cannot name the wrong release.

2. **`depannix-tools`** — the catalogue by *capability*, not by package. Every
   line is the tool, the gesture, and its figure. Flags that matter:
   `--search <word>` (fzf is present), `--json` (jq is present), and
   `--missing <name>`, which answers "not here — available on demand:

       nix shell nixpkgs#<name>

   That last one is the move nobody else in this category can make: it turns a
   dead end into an action, at the exact moment of need. It is the one thing the
   ~281 MiB copy of nixpkgs and `stdenv` inside the image is *for*.

3. **`depannix help <subject>`** — the index by task, which is the actual 3 a.m.
   need: deleted files on a USB stick → `photorec`; a disk that clicks →
   `ddrescue`; a broken GPT → `gdisk`; a vanished volume → `vgchange -ay`; a
   LUKS container → `cryptsetup open`; a degraded array → `mdadm --examine`; a
   pool → `zpool import`. This is writing, not code, and it is the highest-value
   piece for a rescue medium.

4. **Completion and a couple of safe aliases**, generated from the same data, so
   `depannix <TAB>` lists the catalogue.

5. **The same text as files on the medium** — `/depannix-tools.txt` and
   `/depannix-help.txt` beside `/depannix-version`. Readable without running
   anything, and part of the artifact, so the auditor reads what the operator
   reads.

## Deliberately excluded

- **A TUI menu.** `dialog` is absent, so it would be a new dependency for code
  and no added truth; bricks 2 and 3 cover the need in text.
- **A graphical interface.** v1 is a TUI by choice.
- **Baking the full manifest** (≈355 KiB, 0.02 % of the ISO) without deciding
  what it is *for*. It cannot prove anything about itself — a tampered ISO would
  carry a tampered manifest — but it would let an offline machine check *another
  copy of the same release*. That is a real if modest use, and it must not be
  called authenticity.

## Open decisions

1. **Scope.** The five bricks, or the five minus the task index (catalogue only,
   help written later), or those plus the baked manifest and a `depannix verify`
   comparing the running system to it?
2. **Language of the in-image text.** English like the rest of the repository, a
   bilingual greeting chosen from the machine's locale, or French in the image
   while the repository stays English?
3. **Files on the medium.** Ship the catalogue and help as files in addition to
   the commands, or only as commands?
