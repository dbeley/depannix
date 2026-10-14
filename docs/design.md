# Architecture decisions

This document explains the choices, including the ones that cost, so that they
are not re-litigated in six months without context.

## Why NixOS rather than a Debian/Arch remaster

The selection of tools is not the problem: in SystemRescue, Grml or Hiren's,
the list is frozen at burn time. That is what ages badly. With NixOS:

- the catalog extends on demand (`nix shell nixpkgs#…`) without reflashing;
- the composition of the image is a computable value, hence publishable;
- the monthly update is a `flake.lock` that moves, not a manual rebuild.

Accepted trade-off: a 1,42 GiB ISO against 1,29 GiB for SystemRescue
(measured figures, see `docs/budget.md`), and the obligation to disable Secure
Boot.

## Why the nixpkgs copy stays in the ISO

`profiles/installation-device.nix` embeds the complete nixpkgs source
(200 MiB of store), `stdenvNoCC`, `busybox` and `jq` (81 MiB) — measured, i.e.
~281 MiB of store, about a hundred megabytes of ISO. This is deliberate: it
makes it possible to **build a package from source without a network**. A rescue
medium that assumes a healthy machine is a contradiction in terms.

## Why only redistributable firmware

`installation-cd-base.nix` enables `hardware.enableAllHardware`, which embeds
firmware under a non-redistributable license. We force it to `false` and enable
`enableRedistributableFirmware`. This is the foundation of rule no. 2: we
publish the composition of the image, so everything it contains must be
redistributable.

Cost, **measured on the manifest of the real image** and not on a mock-up: the
closure is 732 paths for 2467,7 MiB, of which 836,0 MiB is firmware, i.e. 34%.
The largest single item is `linux-firmware-20260916-zstd` at 809,5 MiB.

A method correction along the way: the figure of 1884 MiB that appeared here came
from the **monolithic** `linux-firmware` package, whereas the image embeds the
`-zstd` variant, which is markedly lighter — and it ignored the 546 other paths
in the system (systemd, Nix tools, the Perl stack, Python, git). Firmware remains
the largest line item, but at 34% of the total and not 70%: it was the hierarchy
of priorities that was wrong, not just the amount.

## Why no graphical interface in v1

Two reasons, quantified rather than aesthetic:

- `nautilus` alone = 1162 MiB of closure, `gparted` = 385 MiB, `gsmartcontrol` =
  317 MiB. The official NixOS graphical ISO weighs 3574 MiB against 1533 MiB for
  the minimal one.
- GNOME Files automatically mounts anything that is plugged in. In data recovery
  or forensics, that is exactly the gesture that writes to the system we are
  trying to save.

If a graphical flavor arrives, it will have to embed a policy with automount
disabled and a dedicated boot entry.

## Salvaged from `n8henrie/nixos-rescue` — and thrown away

The project has been inactive for three years, but two things are worth
reusing:

- **The flake structure**: `nixosModules.default` + `packages.default` +
  an app that boots the image in a VM. The reusable module makes it possible to
  later add a "Dépannix" boot entry on an installed machine.
- **The QEMU harness** (`graphics = false`, read-only cdrom disk, port
  forwarded) and two kernel parameters that change everything: `boot.shell_on_fail`
  and `console=ttyS0` — it is the latter that makes the automated boot test
  possible. Its `memorySize = 2048` is too tight for an ISO of ~1,4 GiB with
  `copytoram`: raised to 3072.
- **The intent behind `boot.kernelPackages = zfs.latestCompatibleLinuxPackages`**:
  to make the ZFS module and the kernel match up. The intent is right, the
  expression no longer is — see "The ZFS / kernel decision".
- **Extended `boot.supportedFilesystems`**: we add `bcachefs`, `f2fs`,
  `nilfs2`, `jfs`.

Thrown away:

- `nixpkgs/nixos-22.11` (the cause of the aging);
- `nixpkgs.config.allowUnfree = true` — incompatible with a public artifact whose
  composition we publish;
- `users.users.root.password = "rescue"` in cleartext, and above all
  `authorizedKeys.keyFiles = fetchurl github.com/n8henrie.keys`: a personal key
  baked into a public artifact. Here, `depannix.authorizedKeys` is empty by
  default;
- `binfmt.emulatedSystems = [ "aarch64-linux" ]`: embedded QEMU user to emulate
  arm64. Now useless with native arm64 runners;
- its package list, too sparse: neither `testdisk`/`photorec`, nor `lshw`, nor
  `dmidecode`, nor `fsarchiver`, nor `nwipe`, nor `nvme-cli`, nor explicit ZFS.

## The ZFS / kernel decision

Embedding ZFS imposes a kernel against which the ZFS module is built, hence an
LTS kernel rather than the very latest. This is a trade-off against support for
the most recent hardware. It is made deliberately: ZFS is a real differentiator
against SystemRescue, which excludes it for licensing reasons, and the NixOS
module is a natural user of it. For the new machine with unknown hardware,
`nomodeset` and the complete firmware cover the essentials.

**What the build revealed.** The inherited expression is deprecated. nixpkgs
now emits:

> `zfs.latestCompatibleLinuxPackages is deprecated and is now pointing at the`
> `default kernel.`

Measured: the default kernel *is* 6.18.55, i.e. exactly
`linuxPackages_6_18`. In other words, the expression produced the same result as
"writing nothing", while giving the illusion of a guarantee. With a
`flake.lock` that moves every month, the drift would have been silent until the
day the ZFS module stops compiling.

We therefore pin `pkgs.linuxPackages_6_18` explicitly. An LTS at end of life
makes the evaluation fail — loud, hence repairable — instead of drifting without
saying anything. This is the opposite of the choice made everywhere else in the
project, where we follow `nixos-unstable`: here, following the default is not
neutral, it is precisely losing the property we were after.

## CI constraints, verified

| Point | Finding |
|---|---|
| x86_64 runners | 4 vCPU / 16 GB / 14 GB of SSD, free and unlimited on public repo |
| `/dev/kvm` on x86_64 | **present** on the standard runners, but undocumented. Requires a udev rule (`static_node=kvm`, the runner user is not in the `kvm` group) and installing `qemu-system-x86`, absent from the image |
| `/dev/kvm` on arm64 | **absent at every level** — a limitation of the Azure ARM SKU, not of the image. The aarch64 boot test therefore remains manual |
| Disk | ~2,7 GiB of store + squashfs + ISO ≈ 5 GiB: ample within the 14 GB |
| Binary cache | `magic-nix-cache-action` was abandoned in February 2025 then resurrected — we do not build on it. Cachix is the durable choice, not configured in v0.1 |

The workflow fails explicitly if `/dev/kvm` is absent: without this guard rail,
QEMU silently falls back to software emulation and the job times out instead of
failing.

**Pitfall discovered at runtime, one level lower.** This guard rail was not
enough. The boot test is a `nix build`, so it runs inside the **Nix sandbox**,
which does not expose `/dev/kvm` to builds. The runner might well enable it, but
the test's QEMU did not see it and fell back to emulation — exactly the failure
the guard rail claimed to prevent, but located beneath it.
The device must be injected into the sandbox:

```bash
nix build --option extra-sandbox-paths /dev/kvm .#checks.<system>.boot-test-bios
```

Verified: the build log shows `[qemu] KVM active` **inside** the sandbox.

## The boot marker

The boot test cannot settle for "QEMU started". A systemd unit
`depannix-ready` writes `DEPANNIX_READY` to `/dev/ttyS0` explicitly — not via
`/dev/console`, whose destination depends on the order of the `console=` entries
on the command line. This is also the simplest way to prove that the system has
actually reached multi-user.

## The serial console, and why it was silent

An instructive diagnosis. The marker did appear, but `serial.log` contained only
20 lines: a boot failure would therefore have been undiagnosable in CI. The cause
was neither `quiet` nor a missing `console=`. It was the command line **actually
burned into the ISO** that revealed it:

```
init=… console=ttyS0,115200 console=tty1 boot.shell_on_fail nohibernate root=fstab loglevel=4 lsm=landlock,yama,bpf
```

`loglevel=4` is added by nixpkgs **after** the `boot.kernelParams`. Writing
`loglevel=7` in `boot.kernelParams` would therefore have changed nothing: the
value added last wins. The correct lever is the dedicated
`boot.consoleLogLevel` option, inserted in the right place.

General lesson: when an option does not produce the expected effect in an
assembly, read the final artifact rather than the source. A `grep` on the ISO
settled in one command what reading the nixpkgs modules had not yielded.

## Reproducibility: measured, not assumed

The project's promise rests on this: a third party must be able to rebuild the
image and obtain exactly the same one. This is measured, across two deliberately
dissimilar environments.

| | Development machine | GitHub runner |
|---|---|---|
| cores | 2 vCPU | 4 vCPU |
| Nix implementation | upstream Nix 2.35.2 | Determinate Nix |
| store | already populated | downloaded in full |
| nixpkgs revision | `7fd4004d` (`flake.lock`) | same |
| ISO sectors | 744 016 | 744 016 |
| sha256 | `85d2355b…10e355` | `85d2355b…10e355` |

The row that matters most is the second one: the two sides do not even run the
same Nix **implementation**. CI installs Determinate Nix (the
`nix-installer-action` default — its log says `Installing Determinate Nix using
the --determinate flag`), while the development host runs upstream Nix 2.35.2
from nixpkgs, with no `determinate-nixd` anywhere. The bytes come out identical
anyway. Reproducibility here does not rest on using the same tooling: it rests on
a pinned nixpkgs revision and on derivations that do not depend on which Nix
built them.

Three remarks on what makes it possible, of which only one is actually verified:

- Versioned `flake.lock`, hence the same nixpkgs revision on both sides
  (verified: it is indeed the same).
- `SOURCE_DATE_EPOCH` pinned in the recipe — this is the standard lever, but I
  have not dissected the `mksquashfs`/`xorriso` chain in nixpkgs to confirm
  that it is indeed what neutralizes the timestamps. Not to be presented as
  established.
- Two machines do not make a law. The result is solid because the environments
  differ along several axes at once (empty versus populated store, 4 versus 2
  cores), not because it was repeated a hundred times.

The practical consequence is clear: the provenance attestation produced by the CI
designates the same object as the local build. These are not two "equivalent"
artifacts — it is a single artifact, produced twice.

## Open points

- `boot.zfs.forceImportRoot`: by default, the live system can import the ZFS
  pools of the machine being rescued. On a recovery medium, an automatic
  writable import deserves close examination.
- Order `console=ttyS0` then `console=tty1`: measured, the **last** `console=`
  wins `/dev/console`, so it points at `tty1` (the screen). Consequence: in the
  event of failure, the rescue shell of `boot.shell_on_fail` shows on the screen
  and **not** on the serial line, hence invisible in the CI log. To be decided:
  accept a verbose serial log but without a rescue shell, or reverse the order
  for the machine with no screen.
- Bit-for-bit reproducibility: **settled**, see the section above.
- `isoImage.forceTextMode` and the additional boot entries (`copytoram`,
  forensic mode) are not yet wired up.
- aarch64 boot test: manual, for lack of `/dev/kvm` on the ARM runners.
