# Size budget

Every figure in this document is **measured**, not estimated.

Two sources, and they do not replace one another:

| Source | What it measures | Use |
|---|---|---|
| The ISO manifest (`nix build .#closure-manifest`) | The **real** closure of the built system: 732 paths, hashes included | **The budget.** It is the only value that describes the artifact |
| `nix path-info --store https://cache.nixos.org` on an isolated package | The closure of a package, without building anything | The **ranking** of costs, to decide what to ship |

```bash
# individual closure of a package, without building anything
nix eval --raw -f '<nixpkgs>' <package>.outPath        # -> /nix/store/...
nix path-info --store https://cache.nixos.org -rs --json --json-format 1 <path>
```

A caution when reading: an **individual closure** counts shared dependencies in
full. Adding several closures together therefore always overestimates the total.
These values serve to compare tools with one another, never to add up.

## The closure of the image (2026.10)

Measured on the ISO manifest, therefore on the artifact itself.

| Line item | Store | Paths |
|---|---|---|
| Firmware (11 packages) | **836.4 MiB** | 11 |
| of which `linux-firmware-20260916-zstd` | 809.5 MiB | 1 |
| Kernel modules | 145.2 MiB | 1 |
| nixpkgs copy (`nixos-26.11…`) | 200.0 MiB | 1 |
| `python3-3.14.7` | 136.6 MiB | 1 |
| `systemd-261.3` | 63.0 MiB | 1 |
| `git-2.55.0` | 56.5 MiB | 1 |
| `vim-9.2.1001` | 43.6 MiB | 1 |
| everything else (716 paths) | ~986 MiB | 716 |
| **Total** | **2467.7 MiB** (2.41 GiB) | **732** |

**Firmware accounts for 34% of the total**, not 70%. It is the largest single
line item, but it does not dominate the discussion as much as was believed — see
the correction below. The other 716 paths, which include all the system's
plumbing (systemd, the Nix stack, Python, Perl, git, vim), weigh on their own
more than twice the firmware.

## What the real measurement corrected

The previous version of this document stated **186 paths / 2675.6 MiB** with
firmware at 70%. Both figures were wrong, and for two distinct reasons:

- **Firmware was overestimated.** The figure of 1884 MiB applied to the
  **monolithic** `linux-firmware` package, whereas the image ships the
  `-zstd` variant, at 809.5 MiB. The error factor is 2.3.
- **The system was underestimated.** The 186 paths were the union of the
  components *explicitly chosen* (firmware, kernel, listed tools). The real
  closure counts 732: the other 546 come from the `installation-cd-base`
  profile — systemd, the Nix tools, `git`'s Perl stack, Python, vim,
  `nixos-rebuild`.

The total therefore happened to be roughly right (2675.6 versus 2467.7 MiB, an
8% discrepancy) while **its composition was wrong**. This is the worst case: a
figure that looks good and sends decisions in the wrong direction. The lesson is
that the only measurement that counts is that of the artifact, never that of a
model of the artifact.

## Cost of the optional tools

Individual closure, measured on the binary cache. These are additional
troubleshooting line items, to be enabled knowingly —
`depannix.optionalTools = [ … ]`.

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

`guymager` (2.5 GiB of closure) illustrates the trap: an “obvious” tool for a
recovery medium costs on its own as much as everything else, because it bundles
the Qt stack. `gparted` and `gsmartcontrol` pay the same toll (graphical
interface) — which is why the `minimal` flavour does not ship them and relies on
`parted`, `gptfdisk` and `smartctl`.

## Measured ISO size (2026.10)

**1453.2 MiB (1.419 GiB).**

| | |
|---|---|
| bytes | 1,523,744,768 |
| MiB / GiB | 1453.2 / 1.419 |
| sha256 | `85d2355bda8bff04d59c1995ed07a98bd0142528b1fd14d25bd6bccfa810e355` |
| compression | squashfs, `zstd -Xcompression-level 19`, 2 processors |
| compression time | ~14 min on 2 vCPU |
| store → ISO ratio | 2467.7 MiB → 1453.2 MiB, i.e. **59%** |

Context benchmarks:

- SystemRescue 13.02: 1318 MiB
- Official minimal NixOS ISO: 1533 MiB
- Official graphical NixOS ISO (GNOME): 3574 MiB

Dépannix is **135 MiB above** SystemRescue and **80 MiB below** the official
minimal NixOS ISO. The goal is not to beat SystemRescue on size: it is to land in
the same zone **with** a way to extend the tooling without reflashing, and with a
publishable composition. The overhead compared with SystemRescue is the complete
redistributable firmware and the nixpkgs copy.

## Independently verified content

The manifest publishes every path with its hash, in base32 **and** in SRI.
Verification is therefore done by a simple GET, without Nix and without granting
any trust to the build author:

```bash
awk '!/^#/ {print $1}' closure-sri-x86_64-linux.tsv | while read -r p; do
  h=$(basename "$p")
  curl -s "https://cache.nixos.org/${h%%-*}.narinfo" | sed -n 's/^NarHash: //p'
done
```

Result measured on the x86_64-linux 2026.10 image (the closure differs per
architecture, and each file of the manifest is named after one):

| | |
|---|---|
| paths in the manifest | 732 |
| hashes **identical** to cache.nixos.org | **685** |
| absent from every cache (built locally) | 47 |
| divergences | **0** |

The 47 paths not verifiable this way are the NixOS system itself, the generated
`/etc` files and the systemd units. For those, only rebuilding is authoritative —
hence the value of the observed stability: two successive builds produced the
same fingerprints for `closure-x86_64-linux.json` (`3140438d…`) and
`store-paths-x86_64-linux.txt` (`888e156f…`).

## The rule

> **No tool enters the ISO without its closure figure.**

Not out of stinginess, but because a rescue medium whose composition is unknown
is not a rescue medium. The `checks.size-budget` guard (1800 MiB) fails in CI if
the ISO drifts, and this document must be updated at the same time as
`modules/tools.nix`.

Corollary, learned the hard way: the figure must come from the **artifact**, not
from a model of the artifact. `nix build .#closure-manifest` exists for that —
it is what holds authority, including against this document.
