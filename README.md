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

## Download

[`v2026.10`](https://github.com/dbeley/depannix/releases/tag/v2026.10) has the
x86_64 and the aarch64 image. The image is the file named
`depannix-minimal-<release>-<system>.iso`: the other assets are the proof of what
is inside it.

Write it to a whole device, never to a partition:

```bash
lsblk -o NAME,SIZE,TYPE,TRAN,MODEL     # find your stick: TRAN=usb
sudo dd if=depannix-minimal-2026.10-x86_64-linux.iso of=/dev/sdX bs=4M status=progress conv=fsync
```

Then check what you hold, before trusting it:

```bash
sha256sum -c SHA256SUMS
minisign -V -p depannix.pub -m SHA256SUMS
gh attestation verify depannix-minimal-*.iso --repo dbeley/depannix
```

`gh attestation verify` exits 0 when the attestation is found and valid, and 1
with an HTTP 404 when the file has none. The signing key id is
`9B9991F6C6D6836C`: compare it out of band, since `depannix.pub` ships from the
same place as the signature it validates.

## Once it boots

You get a root shell on a live medium, and the medium introduces itself:

```
Dépannix 2026.10 - minimal rescue image (x86_64-linux)

You are root on a live medium: nothing here survives a reboot.
  depannix tools        what this image carries
  depannix help         what to do about a failure (subjects, one per file)
  ~/depannix-help.txt   the same as a file, and on the stick at /iso
```

`depannix` answers the question you actually have at that point, which is not
"which packages are installed" but "which of these tools do I want":

```bash
depannix tools                    # the catalogue, by capability, through less
depannix tools --search raid      # fuzzy, through fzf
depannix tools --category benchmark
depannix help                     # the 17 subjects covered
depannix help dying-disk          # one of them, in full
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
boots, cloning a disk, erasing one, SMART, the network, memory, benchmarks, and
how to verify this very medium.

The catalogue and the help are also plain files, in the home directory you land
in (`~/depannix-tools.txt`, `~/depannix-help.txt`) and at the root of the stick,
readable from a machine you cannot boot at all.

## What is inside

The selection is small on purpose: **58 tools**, so that every failure mode has a
tool and every tool has a reason.

| | |
|---|---|
| partitioning, filesystems | parted, gptfdisk, e2fsprogs, xfsprogs, btrfs-progs, ntfs3g, exfatprogs, f2fs-tools, jfsutils, nilfs-utils, bcachefs-tools, mdadm, lvm2, cryptsetup, partclone, fsarchiver, squashfs-tools |
| recovery | testdisk (photorec), ddrescue, dcfldd, nwipe, sleuthkit |
| diagnostics | smartmontools, nvme-cli, hdparm, sdparm, lshw, dmidecode, pciutils, usbutils, ethtool |
| benchmarks | openssl, p7zip, lz4, sysbench, stress-ng, fio, hyperfine, ioping, john |
| network | iperf3, nmap, tcpdump, socat |
| comfort | jq, zstd, file, lsof, strace, tmux, screen, rsync, nano, less |
| discovery | fzf, ripgrep, fd, and the `depannix` command itself |

The heavy tools stay in the catalogue with their measured size, one build flag
away: gparted (385 MiB), phoronix-test-suite (606 MiB), guymager (2540 MiB),
gsmartcontrol (317 MiB), neovim (262 MiB), fish (309 MiB). `docs/budget.md` holds
the measured closure of everything.

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

Each release publishes four things per architecture:

| file | what it is for |
|---|---|
| `depannix-minimal-<release>-<system>.iso` | the image |
| `closure-<system>.json` | every embedded store path, with its NAR hash and size |
| `closure-sri-<system>.tsv` | the same paths and hashes, in the encoding narinfo files use |
| `SHA256SUMS` and `SHA256SUMS.minisig` | the hashes of all of the above, signed |

Checking the composition needs no Nix and no trust in whoever ran the build, only
one plain HTTP request per package against the public binary cache:

```bash
# 1. the image and the manifests are intact, and the sums are signed
sha256sum -c SHA256SUMS
minisign -V -p depannix.pub -m SHA256SUMS

# 2. every package that came from nixpkgs matches the published hash. Take the
#    manifest whose name matches the image you downloaded: the closure differs
#    between architectures.
awk '!/^#/ {print $1}' closure-sri-x86_64-linux.tsv | while read -r p; do
  h=$(basename "$p")
  curl -s "https://cache.nixos.org/${h%%-*}.narinfo" | sed -n 's/^NarHash: //p'
done
# then compare each value against the narHash field of closure-x86_64-linux.json

# 3. the image came out of this repository, on a known commit
gh attestation verify depannix-minimal-*.iso --repo dbeley/depannix
```

Most paths are confirmed this way. The rest are the NixOS system itself, the
generated `/etc` and the systemd units: they exist in no binary cache, so nothing
can confirm them except a rebuild, which is what the next section is for.

## Building it yourself

```bash
nix build .#minimal          # the release image, zstd-19 compression
nix build .#minimal-fast     # the same, fast compression, for iterating
nix run                      # boot it in QEMU
MODE=efi nix run             # the same, with EFI firmware
nix flake check              # BIOS and EFI boot tests, then the size guard
```

Two builds of the same revision, on two different machines, produce the same
bytes: same sha256, same sector count. That is what makes the published manifest
worth anything.

## Project rules

1. No tool enters the image without its measured closure size, and without one
   line saying what it is for. Both are mechanical: the catalogue in
   `nix/tool-catalog.nix` builds the image, and an assertion refuses to evaluate
   when an entry lacks either.
2. Nothing that cannot be redistributed. `allowUnfree` is off and firmware is
   limited to the redistributable set, which is what makes publishing the
   composition legitimate.
3. No secret and no personal key in the artifact. SSH accepts keys only, never a
   password, and no key ships by default.
4. No release ships if a test fails. Better to stay on the last green month than
   to publish an image that does not boot.

## Limitations

- **Secure Boot must be disabled.** The image carries no Secure Boot signature:
  minisign signs the checksums, not the boot chain. This is the main gap
  compared with commercial rescue media, and a project of its own.
- **Write the stick with `dd`, or use a launcher's plain entry.** The image boots
  on its own, which is the path CI exercises, or from a launcher that provides
  `iso_path`, the convention grubfm follows and the nixpkgs ISO template uses in
  `findiso=${iso_path}`. Ventoy does not provide it: it injects its own hook
  instead, and only on its normal path, so its "Grub2 Mode" cannot boot this
  image.
- **The aarch64 boot test is manual.** Free arm64 runners expose no `/dev/kvm`,
  so the aarch64 image is built and attested but not booted in CI.
- **No persistence, and no graphical interface.** Both are deliberate: automatic
  disk mounting is the last thing you want during data recovery. A graphical
  flavour would cost about 1.1 GiB for `nautilus` alone.
- **`root` and `nixos` have no password** in a session, like any live medium. Do
  not leave the stick plugged into a networked machine.

## Documentation and layout

`docs/design.md` has the architecture decisions and their rationale,
`docs/budget.md` the measured closure of everything in the image, and
`docs/discovery.md` how the medium describes itself.

```
flake.nix                    inputs and outputs: image, boot tests, size guard
modules/base.nix             foundation: firmware, kernel, licences, SSH, marker
modules/tools.nix            wiring built from the catalogue, with assertions
modules/iso.nix              name, boot menu, compression, volume
modules/discovery.nix        greeting, shell hook, files on the medium
nix/tool-catalog.nix         the catalogue: name, category, gesture
nix/discovery-bundle.nix     generates the command, the catalogue and the help
nix/depannix.sh              the `depannix` command itself
help/help.txt                the procedures, written by hand
nix/qemu-run.sh              QEMU launch: interactive, or marker-based test
nix/closure-manifest.nix     the composition manifest, which is the proof
```
