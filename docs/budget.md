# Size budget

Every figure in this document is **measured**, not estimated.

Two sources, and they do not replace one another:

| Source | What it measures | Use |
|---|---|---|
| The ISO manifest (`nix build .#closure-manifest`) | The **real** closure of the built system: 777 paths, hashes included | **The budget.** It is the only value that describes the artifact |
| `nix path-info --store https://cache.nixos.org` on an isolated package | The closure of a package, without building anything | The **ranking** of costs, to decide what to ship |

```bash
# individual closure of a package, without building anything
nix eval --raw -f '<nixpkgs>' <package>.outPath        # -> /nix/store/...
nix path-info --store https://cache.nixos.org -rs --json --json-format 1 <path>
```

A caution when reading: an **individual closure** counts shared dependencies in
full. Adding several closures together therefore always overestimates the total.
These values serve to compare tools with one another, never to add up. The
benchmark section below shows the gap, measured: 1026.5 MiB of individual
closures for 172.9 MiB actually added.

## The closure of the image

Measured on the ISO manifest, that is on the artifact itself.

| Line item | Store | Paths |
|---|---|---|
| Firmware (11 packages) | **836.4 MiB** | 11 |
| of which `linux-firmware-20260916-zstd` | 809.5 MiB | 1 |
| NixOS module tree (`nixos-26.11...`) | 200.0 MiB | 1 |
| Kernel modules | 145.2 MiB | 1 |
| `python3-3.14.7` | 136.6 MiB | 1 |
| `john-1.9.0-Jumbo` | 72.5 MiB | 1 |
| `systemd-261.3` | 63.0 MiB | 1 |
| `git-2.55.0` | 56.5 MiB | 1 |
| `perl-5.42.3` | 55.2 MiB | 1 |
| `vim-9.2.1001` | 43.6 MiB | 1 |
| `icu4c-78.3` | 39.7 MiB | 1 |
| `grub-2.14` (two outputs) | 74.9 MiB | 2 |
| everything else (764 paths) | ~1462 MiB | 764 |
| **Total** | **2640.5 MiB** (2.58 GiB) | **777** |

**Firmware accounts for 32% of the total**, not 70%. It is the largest single line
item, but it does not dominate the discussion as much as was believed, see the
correction below. The other 766 paths, which include all the system's plumbing
(systemd, the Nix stack, Python, Perl, git, vim), weigh on their own more than
twice the firmware.

## What the real measurement corrected

An earlier revision of this document stated **186 paths / 2675.6 MiB** with
firmware at 70%. Both figures were wrong, for two distinct reasons:

- **Firmware was overestimated.** The figure of 1884 MiB applied to the
  **monolithic** `linux-firmware` package, whereas the image ships the `-zstd`
  variant, at 809.5 MiB. The error factor is 2.3.
- **The system was underestimated.** The 186 paths were the union of the
  components *explicitly chosen* (firmware, kernel, listed tools). The real
  closure counts 777: the rest come from the `installation-cd-base` profile,
  meaning systemd, the Nix tools, the Perl stack, Python, vim, `nixos-rebuild`.

The total therefore happened to be roughly right while **its composition was
wrong**. That is the worst case: a figure that looks good and sends decisions in
the wrong direction. The only measurement that counts is that of the artifact,
never that of a model of the artifact.

## Cost of the optional tools

Individual closure, measured on the binary cache. These are additional
troubleshooting line items, to be enabled knowingly with
`depannix.optionalTools = [ ... ]`.

| Tool | Store | Paths |
|---|---|---|
| `fd` | 50.9 MiB | 7 |
| `fzf` | 50.1 MiB | 11 |
| `ripgrep` | 55.7 MiB | 8 |
| `eza` | 62.4 MiB | 13 |
| `bat` | 72.5 MiB | 16 |
| `hwinfo` | 135.3 MiB | 27 |
| `inxi` | 140.0 MiB | 35 |
| `neovim` | 261.7 MiB | 115 |
| `fish` | 309.4 MiB | 45 |
| `gsmartcontrol` | 317.2 MiB | 112 |
| `gparted` | 385.1 MiB | 132 |
| `phoronix-test-suite` | 606.0 MiB | 139 |
| `guymager` | 2539.6 MiB | 259 |

`guymager` (2.5 GiB of closure) illustrates the trap: an "obvious" tool for a
recovery medium costs on its own as much as everything else, because it bundles
the Qt stack. `gparted` and `gsmartcontrol` pay the same toll for the graphical
interface, which is why the `minimal` flavour does not ship them and relies on
`parted`, `gptfdisk` and `smartctl`.

## Cost of the benchmarks

Nine tools entered the core catalogue at once: `openssl`, `p7zip`, `lz4`,
`sysbench`, `stress-ng`, `fio`, `hyperfine`, `ioping` and `john`. Their individual
closures, measured on the binary cache:

| Tool | Individual closure |
|---|---|
| `john` | 399.9 MiB |
| `fio` | 239.7 MiB |
| `stress-ng` | 88.2 MiB |
| `sysbench` | 70.0 MiB |
| `p7zip` | 59.7 MiB |
| `hyperfine` | 48.6 MiB |
| `openssl` | 46.7 MiB |
| `lz4` | 37.2 MiB |
| `ioping` | 36.5 MiB |
| **sum, which means nothing** | **1026.5 MiB** |

What they actually added, by diffing two closure manifests and two ISOs of nearly
the same revision:

| | Added |
|---|---|
| store paths | **+38** (739 → 777) |
| NAR, uncompressed | **+181 318 160 bytes** (172.9 MiB) |
| ISO, zstd-19 | **+63.9 MiB** |

The individual closures are six times the real cost, because `john`, `fio` and
`stress-ng` share a base that was already in the image (gcc runtime, glibc,
OpenSSL, zlib). Reading the sum as a budget would have rejected nine tools that
cost 2.4% of the image.

## Measured ISO size

Both flavours, at the compression a release uses, `zstd -Xcompression-level 19`. The
minimal figures are what CI enforces on every push, on both architectures; the
desktop figure is the same build, measured here.

| flavour | system | release ISO | budget | margin |
|---|---|---|---|---|
| `minimal` | x86_64 | **1629 MiB** (1 707 933 696 B) | 1800 MiB | 171 MiB |
| `minimal` | aarch64 | **1739 MiB** (1 824 458 752 B) | 1800 MiB | 61 MiB |
| `desktop` | x86_64 | **2877 MiB** (3 016 949 760 B) | 3800 MiB | 923 MiB |

The aarch64 row is the figure CI measured before the portal trim below; the next run
on that change re-measures it.

The console image that shipped as 2026.10 was 1517.0 MiB (1 590 722 560 B), with a
store-to-ISO ratio of 57%. Adding a Wayland session cost 204 MiB of ISO, and the
margin under the ceiling fell from 283 MiB to 79. The portal trim gives 92 of those
back: the session now costs **112 MiB**, and the margin is 171. That is the same
decision priced in the currency the guard uses, and the reason the guard is there
rather than in a paragraph.

Context benchmarks:

- SystemRescue 13.02: 1318 MiB
- Official minimal NixOS ISO: 1533 MiB
- Official graphical NixOS ISO (GNOME): 3574 MiB

Dépannix carries that session at **1629 MiB**: 311 MiB above SystemRescue and 96 MiB
above the official minimal NixOS ISO, and 1945 MiB below the official graphical one.
The goal is not to beat SystemRescue on size: it is to land in the same zone **with**
a session, a way to extend the tooling without reflashing, and a publishable
composition. The overhead compared with SystemRescue is the complete
redistributable firmware and the NixOS module tree that `nixos-install` pulls in
(200 MiB). That path holds `nixos/` alone, not `pkgs/`: it is a module tree and
not a nixpkgs copy, and nothing in this image can build from source offline.

## Cost of the graphical flavours

Measured the same way as everything else here: by walking narinfo references
against the 777 paths of the console image, and counting only what is new. The ISO
column applies this image's own store-to-ISO ratio, 40 to 57%, which is why it is
a range.

**That method has a blind spot, and it bit here.** The hand-composed figures below
describe packages, not the *modules* that pull them in: `programs.labwc.enable`
drags `services.graphical-desktop`, which enables OpenGL by default, and mesa alone
is 826 MiB. Composed by hand, the session promised +170 MiB of NAR; built, the ISO
grew by 790 MiB. With the graphics stack turned off and the same session built
again, the growth is 238 MiB in fast compression. The lesson is the project's own
rule applied to itself: only the built image holds authority, and a narinfo walk
ranks, it does not budget.

The two closure manifests, diffed path by path, which is the only figure that
separates the session's own content from the machinery around it:

| | console image | + Wayland session | added |
|---|---|---|---|
| store paths | 777 | 1071 | **+294** |
| NAR, uncompressed | 2640.6 MiB | 3291.0 MiB | **+669 MiB** |
| ISO, fast compression | 1589 MiB | 1827 MiB | **+238 MiB** |
| paths containing `mesa` | 1 | 1 | **0** |

That last line is the point of the exercise: the image carries a `gbm` library by
name and no OpenGL driver at all.

The added paths are not all session. Walking the image's own reference graph
attributes nearly all of the surprise to a single chain:

```
xdg-desktop-portal-gtk -> gnome-desktop -> gtk4 -> gst-plugins-bad -> flite (60.5 MiB)
                                                                  -> ffmpeg (34.4 MiB)
                                                                  -> x265 (23.8 MiB)
                                                                  -> fluidsynth, wildmidi, freepats (33.0 MiB)
xdg-desktop-portal    -> pipewire, wireplumber, libpulseaudio (23.9 MiB)
```

That is 211 MiB of NAR of speech synthesis, MIDI soundfonts and video codecs, in an
image whose session opens none of them. The compositor does not need them either:
they arrive because GTK4 depends on GStreamer, and GTK4 arrives with the desktop
portals.

**Measured, by diffing two closure manifests: disabling the portal stack removes 89
paths and 242.3 MiB of NAR, and brings back 16 paths of 4.9 MiB - all of them
machinery**, a rewritten `system-path`, the system derivation, unit files. 237 MiB
net, and nothing usable lost: `flatpak` and `gnupg` go with the portals they serve.
The lever is `xdg.portal`, and it costs the session nothing, because a session that
runs no GTK application has no portal to use - `grim` takes screenshots directly, and
there is no file chooser to serve. **The desktop image keeps them**: GNOME's own
components and every file chooser in that session go through portals, and it has paid
for GTK4 anyway.

**Built to check it, and then pulled: the ISO goes from 1 804 861 440 bytes to
1 707 933 696, so 92.4 MiB, 5.4% of the image.** More than the NAR figures
suggested, which is not a surprise once the blocks are named: a squashfs block
holding a speech synthesis voice and one holding a soundfont are blocks the session
never reads, and dropping them drops the block with them.

Removing a default is only honest if what it was said to serve still works, so the
session now captures one pixel with `grim` on every boot and reports `screenshot=yes`
on the serial console, and the minimal image's boot test fails without that line. It
passes, with the portals gone, which is the claim measured rather than argued. The
desktop image keeps its portals.

The same pair of builds is the reproducibility evidence: the image built here, on two
cores, is byte for byte the one CI built on four.

This is the mesa lesson one level further from the surface: what costs money in a
rescue image is rarely a package somebody chose.

### The minimal image's session

These rows rank the candidates against each other; they do not budget the session.
The budget is the measured diff above - **+294 paths, +669 MiB of NAR, +238 MiB of
ISO** - and every row here is smaller than the sum of its parts for the same reason
a package closure is smaller than the image it lands in. The portal trim described
above takes 89 of those paths and 92.4 MiB of that ISO back out.

| stack | + paths | new NAR | ISO |
|---|---|---|---|
| `labwc` + `foot` + a font | +64 | 158.7 MiB | 63 to 91 MiB |
| + `swaybg`, `grim`, `slurp`, `wlr-randr`, `swaylock`, `wl-clipboard`, `mako`, `kanshi` | +12 | 11.2 MiB | 4 to 6 MiB |
| + `mesa`, pulled in by the module rather than asked for | +9 | **826.3 MiB** | **331 to 475 MiB** |
| + `fuzzel` (left out) | | 41.3 MiB | |
| + `yambar` (left out) | | 248.8 MiB | |
| + `dolphin` (left out) | | 988 MiB | |
| + `mesa` and `glmark2` (left out) | | 1303.8 MiB | |

Everything the minimal session ships is GPU-free, so the second row is the only
one that costs money and the only one that is refused: the image keeps the
compositor's software renderer and gives up every GTK application, because on
Wayland one cannot exist without the other.

### The desktop image

| stack | + paths | new NAR | ISO |
|---|---|---|---|
| GNOME + Firefox + mesa + mounted USB | +383 | 2707.5 MiB | 1083 to 1557 MiB |
| + `gnome-disk-utility`, once GTK4 is paid for | | 15.1 MiB | 6 to 9 MiB |
| + `gparted` | | 20.7 MiB | 8 to 12 MiB |
| + `glmark2`, `vkmark`, `clpeak` | +16 | 37.0 MiB | 15 to 21 MiB |
| + `gnome-system-monitor` (catalogue only) | | 25.7 MiB | 10 to 15 MiB |
| + `gsmartcontrol` (catalogue only) | | 20.1 MiB | 8 to 12 MiB |

The GPU benchmarks are the clearest illustration of what marginal cost means.
`glmark2` is 113.8 MiB of closure through the binary cache on its own, and 19.4
MiB once a desktop session has already paid for mesa. In the minimal image the
same package costs 1304 MiB, because it brings the driver with it. Same package, a
factor of 68 between the two images: that is why the catalogue carries a `flavours`
field rather than one global list.

`gnome-disk-utility` illustrates the other lesson, which is that the naive
catalogue figure is a ranking and not a budget. Its individual closure is 1318 MiB,
its marginal cost over the minimal session is +318 MiB of NAR, because it adds GTK4
to a GTK3 that labwc already brought, and its marginal cost over the desktop session
is **+15.1 MiB**, because GNOME brought GTK4 and udisks2 already. Three true
numbers, one package, and only the last one describes the decision actually made:
it ships in the desktop image. This is why the catalogue carries a `flavours` field
rather than one global list, and why the project's rule needed the second half of
its sentence - a figure, and the gesture it pays for.

## Independently verified content

The manifest publishes every path with its hash, in base32 **and** in SRI.
Verification is therefore a simple GET, without Nix and without granting any trust
to the build author:

```bash
# the hash a narinfo carries is base32; the manifest's second column is SRI
nix hash convert --to sri "$(curl -s https://cache.nixos.org/<hash>.narinfo \
  | sed -n 's/^NarHash: //p')"
```

Result measured on the x86_64-linux closure of the published 2026.10 console image,
777 paths. The count is per flavour and per architecture, so the recipe below means
nothing unless the manifest names the same image that was downloaded:

| | |
|---|---|
| paths in the manifest | 777 |
| hash **identical** to cache.nixos.org | **719** |
| absent from every cache (built here) | 58 |
| divergences | **0** |

The 58 paths not verifiable this way are the NixOS system itself, the generated
`/etc` files, the systemd units, and our own derivations. For those, only
rebuilding is authoritative.

## The rule

> **No tool enters the ISO without its closure figure.**

Not out of stinginess, but because a rescue medium whose composition is unknown is
not a rescue medium. The size guards - `checks.size-budget-minimal` at 1800 MiB and
`checks.size-budget-desktop` at 3800 MiB - fail in CI if an image drifts, and this
document must be updated at the same time as `nix/tool-catalog.nix`, which is what
builds the images.

Corollary, learned the hard way: the figure must come from the **artifact**, not
from a model of the artifact. `nix build .#closure-manifest-minimal` exists for
that, and it is what holds authority, including against this document.
