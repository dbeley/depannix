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

**1517.0 MiB (1.482 GiB)**, `zstd -Xcompression-level 19`, 2 processors.

| | |
|---|---|
| bytes | 1 590 722 560 |
| MiB / GiB | 1517.0 / 1.482 |
| store → ISO ratio | 2640.5 MiB → 1517.0 MiB, that is **57%** |
| previous release (2026.10) | 1453.2 MiB, `85d2355b...10e355` |

Context benchmarks:

- SystemRescue 13.02: 1318 MiB
- Official minimal NixOS ISO: 1533 MiB
- Official graphical NixOS ISO (GNOME): 3574 MiB

Dépannix is **199 MiB above** SystemRescue and **16 MiB below** the official
minimal NixOS ISO. The goal is not to beat SystemRescue on size: it is to land in
the same zone **with** a way to extend the tooling without reflashing, and with a
publishable composition. The overhead compared with SystemRescue is the complete
redistributable firmware and the NixOS module tree that `nixos-install` pulls in
(200 MiB). That path holds `nixos/` alone, not `pkgs/`: it is a module tree and
not a nixpkgs copy, and nothing in this image can build from source offline.

## Independently verified content

The manifest publishes every path with its hash, in base32 **and** in SRI.
Verification is therefore a simple GET, without Nix and without granting any trust
to the build author:

```bash
# the hash a narinfo carries is base32; the manifest's second column is SRI
nix hash convert --to sri "$(curl -s https://cache.nixos.org/<hash>.narinfo \
  | sed -n 's/^NarHash: //p')"
```

Result measured on the current x86_64-linux closure, 777 paths (the closure
differs per architecture, and each file of the manifest is named after one):

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
not a rescue medium. The `checks.size-budget` guard (1800 MiB) fails in CI if the
ISO drifts, and this document must be updated at the same time as
`nix/tool-catalog.nix`, which is what builds the image.

Corollary, learned the hard way: the figure must come from the **artifact**, not
from a model of the artifact. `nix build .#closure-manifest` exists for that, and
it is what holds authority, including against this document.
