# Discovery: making the medium describe itself

The decisions below were taken and built; `## As built` records what landed, with
measurements. The reasoning is kept because it is what a future change would have
to argue with.

## The gap it closes

The project spent its effort making the composition *provable by a third party*: a
manifest, a signature, an attestation, a reproducible build. It spent almost none
making it *legible to the person holding the stick*. The image had no motd, no
help command, and no way to list what it carried; the inventory lived in three
places, all of them off the medium.

That inverts the situation it is meant for. A rescue medium is picked up because a
machine is dead: no network, no repository, nobody to ask. It has to answer three
readers by itself:

| Reader | Question |
|---|---|
| the operator, 3 a.m., offline | what do I do about this failure? |
| whoever finds the stick | what is this, and what can it do? |
| the auditor | what exactly is inside, and how do I prove it? |

## Already paid for

The layer needed content and hooks, not machinery: `fzf`, `ripgrep`, `fd`,
`bash-completion`, `nano`, `less` and `jq` were in the image already. `dialog` and
`whiptail` are not, so a TUI menu would be a new and measurable dependency for no
added truth. The catalogue and the help are text.

## The catalogue is the image

`nix/tool-catalog.nix` holds one entry per tool (`name`, `category`, `gesture`)
and `modules/tools.nix` only wires it, so there is no parallel list to drift from
the image: the catalogue cannot lie about what ships. The project rule grew its
missing half at the same time. It was "no tool without its closure figure", it is
now also "no tool without its gesture", enforced by an assertion. Both were tested
by inserting bad entries and reading the refusal.

Two images now read that catalogue, so an entry also says which flavours carry it
(`flavours`, absent meaning both). Without it the minimal catalogue would have to
list Firefox, and the desktop one would have to list labwc: a catalogue that
advertises what the image does not carry is worse than no catalogue. A typo in a
flavour name is refused at evaluation, because such an entry would ship in no
image at all and nobody would see it go.

## The bricks

1. **A greeting at login**, generated at build time so it cannot name the wrong
   release: the release, the architecture, where you are, and the commands worth
   knowing.

2. **`depannix tools`**, the catalogue by capability rather than by package: every
   line is the tool, the gesture it covers, and its closure figure for the optional
   ones. `--search <word>` goes through `fzf --filter` when fzf is enabled and
   falls back to `grep`, `--category <name>` filters, `--json` is for scripts, and
   long output goes through `less`. Never in a pipe: a pager in the middle of a
   pipeline is a bug, so the pager is only used when stdout is a terminal.

3. **`depannix missing <command>`**, which answers "not here, and here is how to
   get it":

       nix shell nixpkgs#<name>

   That is the move nobody else in this category can make: it turns a dead end
   into an action at the moment of need. It does need network on the machine being
   rescued, since the image carries no nixpkgs checkout, only the NixOS module tree
   that `nixos-install` pulls in (see `docs/budget.md`). The help says so rather
   than implying otherwise.

   The same answer is wired into the shell: `command_not_found_handle` is defined
   in `interactiveShellInit`, prints the ordinary message, then calls that
   sub-command. Typing `phoronix-test-suite` therefore answers that it is in the
   catalogue but not in this image, with its measured size and the command to get
   it, instead of a bare `command not found`.

4. **`depannix help <subject>`**, the index by task, which is the actual 3 a.m.
   need: deleted files on a USB stick → `photorec`; a disk that clicks →
   `ddrescue`; a broken GPT → `gdisk`; a vanished volume → `vgchange -ay`; a LUKS
   container → `cryptsetup open`; a degraded array → `mdadm --examine`; a pool →
   `zpool import`. This is writing, not code, and it is the highest-value piece for
   a rescue medium.

5. **Completion**, generated from the same data, so `depannix <TAB>` lists the
   sub-commands, the help subjects and the categories. The "couple of safe aliases"
   considered here were dropped: an alias hides which binary actually ran, at the
   moment the operator is least able to check.

6. **The same text as files in the home directory** (`~/depannix-tools.txt`,
   `~/depannix-help.txt`, `~/depannix-version`), because that is where the shell
   lands: a store path is not a place anyone browses. The two text files stay at
   the root of the medium as well, which is mounted at `/iso`, so they can be read
   from a machine that cannot boot the stick.

## Deliberately excluded

- **A TUI menu**, for want of `dialog`.
- **A graphical interface**: this flavour is a TUI by choice.
- **The full manifest baked into the image** (355 KiB, 0.02 % of the ISO). It
  cannot prove anything about itself, since a tampered ISO would carry a tampered
  manifest, though it would let an offline machine check another copy of the same
  release. That is a real if modest use, and it must not be called authenticity.

## As built

Everything is generated at evaluation time from `nix/tool-catalog.nix` and
`help/help.txt`, so there is no second copy to drift from the first.

| Piece | Where it lands |
|---|---|
| `depannix`, bash and nothing beyond what the image already has | `bin/depannix` |
| the catalogue, as text and as JSON | `share/depannix/tools.txt`, `tools.json` |
| the help, 17 subjects, plus an index | `share/depannix/help/`, `help.txt` |
| bash completion | `share/bash-completion/completions/depannix` |
| the greeting, and the missing-command hook | `share/depannix/greeting.txt`, `/etc/bashrc` |
| the same files, where the operator is | `~/depannix-tools.txt`, `~/depannix-help.txt` |

Four things learned while building it:

- **NixOS does not source `/etc/profile.d`.** Verified on a running system rather
  than assumed: `/etc/profile` has no such loop, and the directory does not exist.
  The greeting and the missing-command hook therefore hang off
  `programs.bash.interactiveShellInit`.
- **The greeting and an in-image self-test are asserted by the boot test.** The
  unit prints the greeting, then a line counting the enabled tools and the help
  subjects (`DEPANNIX_SELFTEST tools=58 subjects=17`), then one missing-command
  answer, all to the serial console before the readiness marker. What the operator
  reads on login was otherwise the one part of this image that nothing verified.
- **The command's dependencies were checked against the manifest, not assumed.**
  `gawk` and `findutils` are there; `sed` and `tr` were removed from the script
  anyway, because a rescue medium should not need an installer for its own help.
- **A pager in a pipe is a bug.** `less -RFX` pages an interactive read and quits
  immediately when the text fits one screen, which is what keeps short answers
  behaving like `cat`.

The cost, measured by diffing two closure manifests of the same revision (x86_64):
**+56 800 bytes of NAR, 732 → 739 paths**, 0.002 % of the image. The layer is
content, not machinery, because the tools it describes were already in the
closure. The path set that moved is the new derivations, the greeting text, the
greet unit, and the re-generated system paths (`/etc`, `system-path`, the units)
whose hashes changed because `/etc/bashrc` now mentions the greeting.
