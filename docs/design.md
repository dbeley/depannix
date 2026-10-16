# Architecture decisions

Why the image is what it is, including the choices that cost, so that they are not
re-litigated in six months without the context.

## Why NixOS rather than a Debian or Arch remaster

The problem with SystemRescue, Grml or Hiren's is not the tool selection, it is
that the list is frozen at burn time. That is what ages badly. With NixOS:

- the catalogue extends on demand (`nix shell nixpkgs#...`) without reflashing;
- the composition of the image is a computable value, hence publishable;
- the monthly update is a `flake.lock` that moves, not a manual rebuild.

Accepted trade-offs: a larger ISO than SystemRescue (measured figures in
`docs/budget.md`), and the obligation to disable Secure Boot.

## What the image does not do: build without a network

An earlier revision of this file, and of the README, claimed that the image
carried a copy of nixpkgs and `stdenv` so a package could be built from source
with no network. It does not, and it never did:

- `isoImage.storeContents` holds the system toplevel alone, and
  `includeSystemBuildDependencies` (which would add the build dependencies, and
  with them the sources) defaults to `false` and is set nowhere in nixpkgs nor in
  this repository;
- the published manifest lists no source tree at all;
- the 200 MiB path the budget once called a nixpkgs copy is `nixos-<label>`, which
  contains `nixos/` alone: no `pkgs/`, no `lib/`. It is a dependency of
  `nixos-install`, and it is there because that tool is.

What survives is the real property, and it is enough: on a machine that still has
network, any of the ~100,000 packages is one `nix shell nixpkgs#<name>` away. The
medium says so, rather than implying more.

## Why only redistributable firmware

`installation-cd-base.nix` enables `hardware.enableAllHardware`, which embeds
firmware under non-redistributable licences. We force it to `false` and enable
`enableRedistributableFirmware`. This is what makes rule 2 possible: the
composition is published, so everything in it must be redistributable.

Cost, measured on the manifest of the real image rather than on a model of it:
firmware is 836.4 MiB, 34% of the closure, with `linux-firmware-...-zstd` alone at
809.5 MiB.

A method correction along the way: the figure of 1884 MiB that appeared here came
from the **monolithic** `linux-firmware` package, whereas the image embeds the
`-zstd` variant, and it ignored the 546 other paths of the system. Firmware is the
largest line item, but at 34% and not 70%: the hierarchy of priorities was wrong,
not only the amount.

## The two flavours, and why these two

For a long time this image had no graphical interface, for a quantified reason:
`nautilus` alone is 1162 MiB of closure, and the graphical ISO of NixOS weighs
3574 MiB against 1533 MiB for the minimal one. The question is not whether a
session with a screen is pleasant, it is what it costs and what it buys - and the
answer differs between two jobs, so the project now ships two images.

**`minimal`: the console, plus a Wayland session on demand.** `depannix gui`
starts `labwc`, a compositor with no desktop environment on top of it. The
cheapest session worth having, and the ceiling is not where hand-composed
measurements put it: the module that brings labwc pulls `services.graphical-desktop`
with it, which turns OpenGL on by default and adds **826 MiB** of mesa, more than
half the image. Composed by hand at the narinfo level, the session looked like
+170 MiB of NAR; built, it was +790 MiB of ISO. The trims below are therefore real
measurements, but the thing that had to be refused first was the graphics stack
itself:

| candidate | marginal cost | kept |
|---|---|---|
| `swaybg`, `grim`, `slurp`, `wlr-randr`, `swaylock`, `mako`, `kanshi` | +7.9 MiB | yes |
| `wl-clipboard` | +3.1 MiB | yes |
| `fuzzel`, a launcher | +41.3 MiB | no, labwc has a root menu |
| `yambar`, a bar | +248.8 MiB: it pulls ffmpeg and pipewire | no |
| `dolphin`, a file manager | +988 MiB | no |
| `gparted` | +14 MiB over labwc, which is not the driver's cost | desktop only |
| `mesa`, to have any GTK program at all | **+826 MiB** | **no** |

That last row is the decision the rest of this section follows from. On Wayland a
GTK application cannot draw a pixel without a GL driver, so "a session with a
partition editor in it" is not a session plus 14 MiB, it is a session plus 826 MiB.
The image takes the half that fits on a small stick: a session with no taskbar, no
icon to click and no graphical application, where the root menu on the right-click
is the interface and `foot` is the point - a wide terminal with fonts, several
windows, copy and paste, and screenshots for a bug report. Everything with a screen
in the minimal image is GPU-free: labwc renders through pixman, foot through shared
memory.

**`desktop`: GNOME on Wayland, with Firefox.** This is the flavour that stops
being small, and the reason is the browser. On a machine that will not boot,
being able to read the documentation of the hardware is the most useful thing an
image can offer, and Firefox costs what it costs. Measured: +383 paths, 2707.5
MiB of NAR, 1083 to 1557 MiB of ISO on top of the console image. XFCE would have
saved 12% of that (1300 against 1477 MiB of NAR) and was refused: it is not what
someone reaching for a desktop expects, and 12% does not pay for a second set of
habits.

It is also the flavour where the graphical rescue tools become affordable, which
is the same measurement read the other way: GNOME has already paid for mesa, GTK4
and udisks2, so `gnome-disk-utility` costs **+15.1 MiB** there against 318 MiB
over the minimal session, `gparted` +20.7 MiB, `gnome-system-monitor` +25.7,
`gsmartcontrol` +20.1. `gnome-disk-utility` and `gparted` ship in the desktop
image; the other two stay in the catalogue, one flag away.

Three consequences of shipping a desktop, each a safety matter rather than a
taste one:

- **Automount is off.** `org.gnome.desktop.media-handling` is forced to
  `automount=false` and `automount-open=false`, through `extraGSettingsOverrides`
  in `modules/desktop.nix`. A rescue medium that silently mounts, writes to, and
  replays the journal of the disk it is examining is the one failure this project
  cannot afford, and GNOME does exactly that by default. This is the one claim
  about the desktop image that no file listing can check, so the session reads it
  back from the running GNOME - `gsettings get org.gnome.desktop.media-handling
  automount` - writes the answer on the serial console with the rest of its
  report, and the boot test refuses anything other than `false`.
- **The session logs itself in.** No password to type, and nobody to type it: the
  same choice the official NixOS graphical installer makes.
- **It has its own size guard**, 3800 MiB. The minimal image's 1800 MiB ceiling
  has nothing to say about a flavour whose whole point is the browser.

Both sessions are verified the same way, and the mechanism is worth stating,
because it is what makes the claim checkable rather than asserted. The session
writes a line to the serial console from *inside* itself, as a Wayland client that
had to connect to the compositor to do so:

```
DEPANNIX_SESSION type=wayland session=labwc outputs=1
```

The boot test then captures the guest's framebuffer through the QEMU monitor and
refuses a screenshot whose mean is zero, which is exactly a black screen. A
session that starts and draws nothing is the failure mode this catches. And the
minimal flavour is driven the way a person drives it: the test types `depannix
gui` on the console, through the monitor, because testing a command nobody types
would prove nothing.

One level below that, a single environment variable decided whether any of this
worked, and it is worth writing down because the test is what found it. wlroots
falls back to its software renderer only when the machine has **no** DRM render
node at all. A virtual GPU is enough to have one: virtio-gpu exposes `renderD128`.
So `auto` took the GLES2 path, found no driver, tried Vulkan, found none, and the
compositor exited, its log saying `unable to create renderer` and nothing more.
The variable that used to cover exactly this case, `WLR_RENDERER_ALLOW_SOFTWARE`,
no longer exists in wlroots 0.19; the image now sets `WLR_RENDERER=pixman`
explicitly. In a GPU-free image that is not a preference, it is a statement of
fact about what is installed - and it is the sort of thing that can only be found
by starting the session, not by pricing it.

Two limits, stated rather than left to be discovered: the desktop flavour is boot
tested in BIOS mode only, the EFI path being covered by the minimal flavour; and a
machine whose GPU this kernel does not drive cannot run the session at all. That
last one is handled rather than hidden: `depannix gui` reports the missing
`/dev/dri/card0` and leaves the console exactly as it was.

## Salvaged from `n8henrie/nixos-rescue`, and thrown away

The project has been inactive for three years, but four things were worth
reusing: the flake structure (`nixosModules.default`, `packages.default`, and an
app that boots the image in a VM), the QEMU harness (`graphics = false`, read-only
cdrom, and above all `console=ttyS0`, which is what makes the automated boot test
possible), the intent behind pinning the kernel to the one ZFS was built against,
and the extended `boot.supportedFilesystems` list.

Thrown away: `nixos-22.11`, which is what caused the aging;
`nixpkgs.config.allowUnfree = true`, incompatible with publishing a composition; a
cleartext root password and `authorizedKeys.keyFiles` pointing at a personal
GitHub account, a private key baked into a public artifact;
`binfmt.emulatedSystems`, useless now that arm64 runners are native; and its
package list, too sparse for the job: no `testdisk`, no `lshw`, no `dmidecode`, no
`fsarchiver`, no `nwipe`, no `nvme-cli`, no ZFS.

## The ZFS and kernel decision

Embedding ZFS imposes a kernel against which the module is built, hence an LTS
kernel rather than the newest one, at the cost of support for the most recent
hardware. It is deliberate: ZFS is a real differentiator against SystemRescue,
which excludes it for licensing reasons.

The inherited expression, `zfs.latestCompatibleLinuxPackages`, is now deprecated,
and the build said so:

> `zfs.latestCompatibleLinuxPackages is deprecated and is now pointing at the`
> `default kernel.`

Measured: the default kernel is 6.18.55, exactly `linuxPackages_6_18`. The
expression therefore produced the same result as writing nothing, while giving the
illusion of a guarantee. With a `flake.lock` that moves every month, the drift
would have stayed silent until the day the ZFS module stopped compiling.

We pin `pkgs.linuxPackages_6_18` explicitly. An LTS at end of life makes the
evaluation fail, loud and repairable, instead of drifting quietly. It is the
opposite of the choice made everywhere else in this project, where
`nixos-unstable` is followed on purpose: here, following the default is precisely
losing the property we wanted.

## Discoverability: the medium describes itself

The project spent its effort making the composition provable by a third party, and
almost none making it legible to the person holding the stick. That inverts what a
rescue medium is for: it is picked up because a machine is dead, with no network
and nobody to ask.

`depannix` is the answer to the five questions that matter. `docs/discovery.md`
holds the design and the measurements (56.8 KiB of store, because the tools it
describes were already in the closure). Two implementation notes belong here:

- **NixOS does not source `/etc/profile.d`.** Verified on a running system rather
  than assumed: `/etc/profile` has no such loop, and the directory does not exist.
  The greeting therefore hangs off `programs.bash.interactiveShellInit`.
- **The greeting and the in-image self-test are asserted by the boot test.** The
  unit writes them to the serial console before the readiness marker, so a broken
  `depannix` fails CI rather than the operator.

## CI constraints, verified

| Point | Finding |
|---|---|
| x86_64 runners | 4 vCPU / 16 GB / 14 GB SSD, free and unlimited on a public repository |
| `/dev/kvm` on x86_64 | present, but undocumented. Needs a udev rule (`static_node=kvm`: the runner user is not in the `kvm` group) and `qemu-system-x86`, which the image lacks |
| `/dev/kvm` on arm64 | absent at every level, an Azure ARM SKU limitation. The aarch64 boot test therefore stays manual |
| Disk | ~2.7 GiB of store plus squashfs plus ISO, about 5 GiB: ample in 14 GB |
| Binary cache | `magic-nix-cache-action` was abandoned in February 2025 and then resurrected, so we do not build on it. Cachix is the durable choice, not configured here |

The workflow fails explicitly when `/dev/kvm` is missing: without that guard rail,
QEMU silently falls back to emulation and the job times out instead of failing.

**One level lower, discovered at runtime.** The guard rail was not enough. The
boot test is a `nix build`, so it runs inside the Nix sandbox, which does not
expose `/dev/kvm` to builds. The runner could enable the device and the test's
QEMU would still not see it. It has to be injected:

```bash
nix build --option extra-sandbox-paths /dev/kvm .#checks.<system>.boot-test-bios
```

Verified: the build log shows `[qemu] KVM enabled` inside the sandbox.

## The boot marker

The boot test cannot settle for "QEMU started". A systemd unit, `depannix-ready`,
writes `DEPANNIX_READY` to `/dev/ttyS0` explicitly, rather than through
`/dev/console`, whose destination depends on the order of the `console=` entries
on the command line. It is also the simplest way to prove that the system reached
multi-user.

## The serial console, and why it was silent

The marker did appear, but `serial.log` held twenty lines, which would have made a
boot failure undiagnosable in CI. The cause was neither `quiet` nor a missing
`console=`. It was the command line actually burned into the ISO:

```
init=... console=ttyS0,115200 console=tty1 boot.shell_on_fail nohibernate root=fstab loglevel=4 lsm=landlock,yama,bpf
```

`loglevel=4` is added by nixpkgs *after* `boot.kernelParams`, so writing
`loglevel=7` there would have changed nothing: the value added last wins. The lever
is the dedicated `boot.consoleLogLevel`.

The general lesson, which recurred during the discovery work: when an option does
not produce the expected effect, read the final artifact rather than the source.

## Reproducibility: measured, not assumed

The promise rests on this: a third party must be able to rebuild the image and
obtain exactly the same one. It is measured across two deliberately dissimilar
environments.

| | Development machine | GitHub runner |
|---|---|---|
| cores | 2 vCPU | 4 vCPU |
| store | already populated | downloaded in full |
| nixpkgs revision | `7fd4004d` (`flake.lock`) | same |
| ISO sectors | 744 016 | 744 016 |
| sha256 | `85d2355b...10e355` | `85d2355b...10e355` |

Earlier runs are more interesting on the tooling row: while CI still installed
Determinate Nix, the development host already ran upstream Nix from nixpkgs, and
the bytes came out identical anyway. CI now installs upstream Nix too, and that
switch did not change the hash either. The artifact survived a change of Nix
implementation on one side, which says reproducibility here rests on a pinned
nixpkgs revision and on derivations that do not depend on which Nix built them.

Three remarks, only one of them verified:

- The versioned `flake.lock` gives the same nixpkgs revision on both sides
  (verified: it is the same).
- `SOURCE_DATE_EPOCH` is pinned in the recipe. That is the standard lever, but the
  `mksquashfs`/`xorriso` chain has not been dissected to confirm that it is what
  neutralizes the timestamps. Not to be presented as established.
- Two machines do not make a law. The result is solid because the environments
  differ along several axes at once, not because it was repeated a hundred times.

The practical consequence is clear: the provenance attestation produced by CI
designates the same object as a local build. Not two equivalent artifacts, but one
artifact produced twice.

## Open points

- `boot.zfs.forceImportRoot`: by default the live system can import the ZFS pools
  of the machine being rescued. On a recovery medium, an automatic writable import
  deserves a closer look.
- `console=ttyS0` then `console=tty1`: the last one wins `/dev/console`, so it
  points at the screen. In the event of a failure, the `boot.shell_on_fail` rescue
  shell is therefore invisible in the CI log. To decide: accept a verbose serial
  log without a rescue shell, or reverse the order for machines with no screen.
- `isoImage.forceTextMode` is not wired up, and there is no forensic-mode entry.
  The other secondary entries (`copytoram`, `nomodeset`, `debug`, the framebuffer
  rotations, the serial console) are not ours: the nixpkgs ISO profile generates
  them, and they were verified present in the built image.
- The aarch64 boot test stays manual, for lack of `/dev/kvm` on the ARM runners.
