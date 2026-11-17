# Dépannix

A minimal NixOS rescue environment, for diagnosing, benchmarking and repairing a
machine that no longer works.

It is a live ISO. It carries what you need to recover data from a failing disk,
repair a filesystem or a bootloader, open an encrypted volume, clone a disk, and
measure the hardware before and after a repair. Three things set it apart from
the rescue distributions you already know:

- **It tells you what it carries.** `depannix tools` lists everything by
  capability, `depannix help <subject>` gives you the procedure for a failure.
- **Its catalogue is not fixed at burn time.** On a machine that still has
  network, any of the ~100,000 nixpkgs packages is one command away.
- **Its composition is published and provable.** Every release ships the list of
  embedded store paths with their hashes, and the image rebuilds bit for bit.

## Two images

The project ships two flavours, because a rescue medium and a usable desktop are
not the same budget:

- **`minimal`**, about 1.6 GiB: a console, plus `depannix gui`, a bare Wayland
  session to start on demand. It carries no graphical application, measured
  rather than assumed: on Wayland a GTK program cannot draw a pixel without
  OpenGL, and OpenGL costs 826 MiB here, half the image. Nor does it carry the
  portal stack a desktop needs, since nothing in it is a GTK program and `grim`
  reads the screen without one.
- **`desktop`**, about 3 GiB: the same, plus GNOME on Wayland and Firefox, for the
  machine whose own system no longer boots and where the answer is on a page you
  have to fetch. It carries the graphical rescue tools as well - partitioning,
  SMART, disk images - because GNOME has already paid for the driver they need.

Both are built for x86_64 and aarch64. The x86_64 images are boot tested under KVM
by CI; the aarch64 ones are built and measured but never booted, because the ARM
runners offer no KVM, and that gap is stated rather than papered over. Both flavours
report the session they started on the serial console. "The session works" is checked
there, screenshot and all, rather than asserted.

## Download

[The latest release](https://github.com/dbeley/depannix/releases/latest) has four
images, two flavours by two architectures, named
`depannix-<flavour>-<release>-<system>.iso`. On an ordinary PC take `x86_64`, and
take `minimal` unless you want GNOME and Firefox.

The minimal images download as a single file. The desktop ones are about 2.9 GiB,
above the 2 GiB GitHub allows for one release asset, so they ship in parts: byte
slices, `part-00` first. Join them before writing the stick.

```bash
# the minimal image: one file, nothing to join
gh release download --repo dbeley/depannix -p 'depannix-minimal-*-x86_64-linux.iso'

# the desktop image: parts, then joined. `release` is the version in the asset
# names, not a tag you have to look up: gh takes the latest release by itself.
release=<release>
gh release download --repo dbeley/depannix \
  -p "depannix-desktop-$release-x86_64-linux.iso.part-*" \
  -p SHA256SUMS -p SHA256SUMS.minisig
cat depannix-desktop-$release-x86_64-linux.iso.part-* \
  > depannix-desktop-$release-x86_64-linux.iso
sha256sum -c SHA256SUMS --ignore-missing   # skips the manifests, which you did not take
```

`part-00` begins with the boot sector, so there is nothing to unpack: `cat` in
order is the whole step. The joined file then matches its own line in
`SHA256SUMS`, published for exactly that check, since the image itself is not
downloadable whole.

With Nix installed, build those same bytes instead. The image is reproducible, so
the tagged commit yields the released file:

```bash
nix build .#desktop          # or .#minimal;  .#desktop-fast skips the slow compression
ls result/iso/
```

Either way, write to a whole device, never to a partition:

```bash
lsblk -o NAME,SIZE,TYPE,TRAN,MODEL     # find your stick: TRAN=usb
sudo dd if=<image>.iso of=/dev/sdX bs=4M status=progress conv=fsync
```

Then check what you hold, before trusting it:

```bash
sha256sum -c SHA256SUMS
minisign -V -p depannix.pub -m SHA256SUMS
gh attestation verify <image>.iso --repo dbeley/depannix
```

`gh attestation verify` exits 0 when the attestation is found and valid, and 1
with an HTTP 404 when the file has none. The signing key id is
`9B9991F6C6D6836C`: compare it out of band, since `depannix.pub` ships from the
same place as the signature it validates.

## Once it boots

You get a root shell on a live medium, and the medium introduces itself:

```
Dépannix <release> - minimal rescue image (x86_64-linux)

You are root on a live medium: nothing here survives a reboot.
  depannix tools        what this image carries
  depannix help         what to do about a failure (subjects, one per file)
  ~/depannix-help.txt   the same as a file, and on the stick at /iso
  depannix gui          a Wayland session, without a desktop on top
```

`depannix` answers the question you actually have at that point, which is not
"which packages are installed" but "which of these tools do I want":

```bash
depannix tools                    # the catalogue, by capability, through less
depannix tools --search raid      # fuzzy, through fzf
depannix tools --category benchmark
depannix help                     # the 18 subjects covered
depannix help dying-disk          # one of them, in full
depannix gui                      # a graphical session, if the console is not enough
depannix missing photorec         # is it here? and how to get it if not
```

Type a command that is not installed and the shell tells you where it is, instead
of leaving you at `command not found`:

```
$ phoronix-test-suite
bash: phoronix-test-suite: command not found
phoronix-test-suite: in the catalogue, but not in this image.
  benchmark: benchmark and compare machines  [606 MiB, 139 paths]
  with network:  nix shell nixpkgs#phoronix-test-suite
```

The subjects covered are: a disk that is failing, deleted files, a lost partition
table, a damaged filesystem, LVM, LUKS, RAID, ZFS, a machine that no longer
boots, cloning a disk, erasing one, SMART, the network, memory, benchmarks, a
graphical session, and how to verify this very medium.

The catalogue and the help are also plain files, in the home directory you land
in (`~/depannix-tools.txt`, `~/depannix-help.txt`) and at the root of the stick,
readable from a machine you cannot boot at all.

## What is inside

The selection is small on purpose: **69 tools** in the minimal image, **66** in
the desktop one, so that every failure mode has a tool and every tool has a
reason.

| | |
|---|---|
| partitioning, filesystems | parted, gptfdisk, e2fsprogs, xfsprogs, btrfs-progs, ntfs3g, exfatprogs, f2fs-tools, jfsutils, nilfs-utils, bcachefs-tools, mdadm, lvm2, cryptsetup, partclone, fsarchiver, squashfs-tools |
| recovery | testdisk (photorec), ddrescue, dcfldd, nwipe, sleuthkit |
| diagnostics | smartmontools, nvme-cli, hdparm, sdparm, lshw, dmidecode, pciutils, usbutils, ethtool |
| benchmarks | openssl, p7zip, lz4, sysbench, stress-ng, fio, hyperfine, ioping, john |
| network | iperf3, nmap, tcpdump, socat |
| comfort | jq, zstd, file, lsof, strace, tmux, screen, rsync, nano, less |
| discovery | fzf, ripgrep, fd, and the `depannix` command itself |
| graphics | minimal: labwc, foot, swaybg, grim, slurp, wl-clipboard, mako, wlr-randr, kanshi, swaylock, wayland-utils. desktop, in addition: gnome-shell, firefox, pipewire, gparted, gnome-disk-utility, glmark2, vkmark, clpeak |

The heavy tools stay in the catalogue with their measured size, one build flag
away: guymager (2540 MiB), gnome-system-monitor (1009 MiB), phoronix-test-suite
(606 MiB), gsmartcontrol (317 MiB), fish (309 MiB), neovim (262 MiB). Those
figures are individual closures, which is a way of ranking and not a way of
budgeting: over a running GNOME session, `gnome-system-monitor` costs 26 MiB and
`gsmartcontrol` 20 MiB. `docs/budget.md` holds both sets of measurements.

## Extending it without reflashing

On a machine that still has network, any nixpkgs package is one command away:

```bash
nix shell nixpkgs#some-package
```

That is the point of building on Nix, and it costs nothing in the image. What the
image does **not** do is build from source offline: it carries the NixOS module
tree (200 MiB, pulled in by `nixos-install`) and a `stdenv` without a C
compiler, but no nixpkgs checkout. `depannix missing <tool>` says the same thing
from inside the image.

## Verifying the contents

Each release publishes, per flavour and per architecture, the image, its manifest
in two encodings, and the signed checksums:

| file | what it is for |
|---|---|
| `depannix-<flavour>-<release>-<system>.iso` | the image |
| `closure-<flavour>-<system>.json` | every embedded store path, with its NAR hash and size |
| `closure-sri-<flavour>-<system>.tsv` | the same paths and hashes, in the encoding narinfo files use |
| `SHA256SUMS` and `SHA256SUMS.minisig` | the hashes of all of the above, signed |

The desktop images are the one exception to the naming: they ship as
`depannix-desktop-<release>-<system>.iso.part-00`, `.part-01`, ... because of the
2 GiB asset limit. Join them as shown in [Download](#download).

Checking the composition needs no Nix and no trust in whoever ran the build, only
one plain HTTP request per package against the public binary cache:

```bash
# 1. the image and the manifests are intact, and the sums are signed
sha256sum -c SHA256SUMS
minisign -V -p depannix.pub -m SHA256SUMS

# 2. every package that came from nixpkgs matches the published hash. Take the
#    manifest whose name matches the image you downloaded: the closure differs
#    between flavours and between architectures.
awk '!/^#/ {print $1}' closure-sri-minimal-x86_64-linux.tsv | while read -r p; do
  h=$(basename "$p")
  curl -s "https://cache.nixos.org/${h%%-*}.narinfo" | sed -n 's/^NarHash: //p'
done
# then compare each value against the narHash field of
# closure-minimal-x86_64-linux.json

# 3. the image came out of this repository, on a known commit
gh attestation verify depannix-minimal-*.iso --repo dbeley/depannix
```

Most paths are confirmed this way. The rest are the NixOS system itself, the
generated `/etc` and the systemd units: they exist in no binary cache, so nothing
can confirm them except a rebuild, which is what the next section is for.

## Building it yourself

```bash
nix build .#minimal            # the console image, zstd-19 compression
nix build .#desktop            # the GNOME image, same compression
nix build .#minimal-fast       # either one with fast compression, to iterate
nix run                        # boot the minimal image in QEMU
GUI=1 nix run .#vm-desktop     # the desktop one, with a VNC display to watch
MODE=efi nix run               # the same, with EFI firmware
nix flake check                # boot tests, session tests, size guards
```

Two builds of the same revision, on two different machines, produce the same
bytes: same sha256, same sector count. That is what makes the published manifest
worth anything.

## Limitations

- **Secure Boot must be disabled.** The image carries no Secure Boot signature:
  minisign signs the checksums, not the boot chain.
- **Write it with `dd`.** A launcher works only if it provides `iso_path`, the
  convention the nixpkgs ISO template uses; Ventoy does not, and cannot boot this
  image.
- **`root` and `nixos` have no password**, like any live medium. Do not leave the
  stick plugged into a networked machine.
