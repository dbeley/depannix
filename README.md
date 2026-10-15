# Dépannix

A NixOS rescue environment, built as a minimal, reproducible and verifiable ISO.
A medium you can extend on demand without reflashing it, and whose exact
composition you can publish.

**Status: the first release is published.**
[`v2026.10`](https://github.com/dbeley/depannix/releases/tag/v2026.10) was built
end to end by CI, tested in BIOS and EFI under KVM, its composition verified
against `cache.nixos.org`. The release is unsigned: no minisign key is configured
yet.

| | |
|---|---|
| ISO | 1453.2 MiB (1.419 GiB) |
| embedded store | 732 paths, 2467.7 MiB |
| hashes confirmed by `cache.nixos.org` | 685 out of 732, zero divergence |
| reproducibility | bit-for-bit, verified on two distinct machines |
| CI | green, x86_64 and aarch64 (boot tested on x86_64) |
| repository | https://github.com/dbeley/depannix |

The recipe for verifying it yourself is further down in this file.

## Download

[`v2026.10`](https://github.com/dbeley/depannix/releases/tag/v2026.10) — x86_64
and aarch64, plus the composition manifest. Write it to a USB stick with `dd`
(further down), never to a partition.

```bash
sha256sum -c SHA256SUMS
gh attestation verify depannix-minimal-2026.10-x86_64-linux.iso --repo dbeley/depannix
```

`gh attestation verify` exits 0 when the attestation is found and valid, and 1
with an HTTP 404 when the file has none.

## Getting started

```bash
nix build .#minimal-fast          # ISO, fast compression (local iteration)
nix build .#minimal               # release ISO, zstd-19 compression
nix run                           # boots the ISO in QEMU
MODE=efi nix run                  # same, with EFI firmware

nix build .#checks.x86_64-linux.boot-test-bios   # automated boot test
nix build .#packages.x86_64-linux.closure-manifest
nix flake check                   # BIOS + EFI boot test + size budget
```

Writing to a USB stick: `dd`, never a partition.

```bash
lsblk -o NAME,SIZE,TYPE,TRAN,MODEL     # identify the stick: TRAN=usb
sudo dd if=result/iso/depannix-*.iso of=/dev/sdX bs=4M status=progress conv=fsync
```

## What's in the image, and the real way to extend it

The selection lives in `modules/tools.nix`, split into **capability** (you can't
repair without it) and **convenience** (optional, sized). The detailed
measurements are in `docs/budget.md`.

The one thing that changes everything compared to SystemRescue or Grml: **the
catalogue isn't fixed at burn time**. A NixOS ISO ships a copy of nixpkgs and
`stdenv`, so on a machine you're rescuing that still has connectivity:

```bash
nix shell nixpkgs#outil-quelconque    # any of the ~100,000 packages
```

That's why 281 MiB of store is deliberately spent on a copy of nixpkgs +
`stdenvNoCC`: with no network, you can still build a package from source. A
rescue medium that assumes a healthy machine isn't a rescue medium.

## Project rules

1. **No tool goes into the ISO without its closure size** measured and recorded
   in `docs/budget.md`.
2. **Nothing that can't be redistributed.** `nixpkgs.config.allowUnfree = false`,
   and firmware is limited to what's redistributable
   (`hardware.enableAllHardware` is explicitly disabled). That's what makes it
   legitimate to publish the image's composition.
3. **No secrets or personal keys in the artifact.** `depannix.authorizedKeys` is
   empty by default; sshd accepts keys only, never passwords.
4. **No release ships if a test fails.** We stay on the last green month rather
   than publish an ISO that won't boot.

## Proving the contents

The project aims for an artifact whose composition anyone can verify without
trusting whoever produced it.

| Piece | What it proves |
|---|---|
| `flake.lock` (versioned) | the exact nixpkgs revision, and therefore the whole dependency tree |
| `closure-manifest` | the exhaustive list of embedded store paths + their hashes |
| `SHA256SUMS` | the published ISO is the one whose bytes were measured |
| minisign signature | that nobody altered it after the fact — **not configured yet** |
| provenance attestation (CI) | the artifact came out of this workflow, on this commit |

Verification:

```bash
# 1. the ISO is intact
sha256sum -c SHA256SUMS

# 2. its composition is the one in the published manifest — without Nix, and
#    without trusting whoever built the image: one plain GET per package
awk '!/^#/ {print $1}' closure-sri.tsv | while read -r p; do
  h=$(basename "$p")
  curl -s "https://cache.nixos.org/${h%%-*}.narinfo" | sed -n 's/^NarHash: //p'
done
# then compare each value against the narHash field of closure.json

# 3. you can rebuild the exact same system
git checkout <tag> && nix build .#minimal

# 4. the artifact came out of this workflow, on this commit (needs gh)
gh attestation verify depannix-minimal-2026.10-x86_64-linux.iso --repo dbeley/depannix
```

Measured on the 2026.10 image: **685 of the 732 paths** are confirmed identical
by `cache.nixos.org`, **zero divergence**. The other 47 are derived locally (the
NixOS system itself, the generated `/etc`, the systemd units): they exist in no
binary cache, and for those only a rebuild is authoritative.

The bit-for-bit reproducibility of the ISO is **established**, and it is the
most important result of the project. The same revision, built on the GitHub
runner (4 vCPU, store downloaded in full) and on a NixOS machine (2 vCPU, store
already populated), produces the **same hash** `85d2355b…10e355` and the **same
sector count** (744,016). Two distinct environments, a single artifact: a third
party can therefore rebuild the image and compare it to ours.

Two successive builds of the manifest likewise produced the same digests
(`closure.json` → `3140438d…`, `store-paths.txt` → `888e156f…`).

## Known limitations

- **Unsigned release.** No minisign key is configured yet, so `SHA256SUMS` ships
  without a signature; the provenance attestation is the available alternative.
- **Secure Boot: must be disabled.** The ISO isn't signed. This is the main gap
  compared to Parted Magic, and a project in its own right (signed shim, MOK
  enrollment).
- **No graphical interface** in v1. A deliberate choice: GNOME costs ~1.1 GiB of
  store for `nautilus` alone, and automatic disk mounting is precisely what you
  must not have during data recovery.
- **No persistence.** In v1, anything installed during a session disappears on
  reboot. Persistence is planned for v2.
- **Accounts with no password.** Like any live medium, `root` and `nixos` have no
  password in a session. Acceptable physically, but don't leave it sitting
  plugged into a networked machine.
- **`aarch64` not tested in CI.** Free arm64 runners don't expose `/dev/kvm`:
  the ISO is built, but its boot is tested by hand.
- **No Clonezilla.** Not in nixpkgs; cloning relies on `partclone`,
  `fsarchiver` and `ddrescue`, which cover the need.

## Roadmap

- **v0.1 — done.** Minimal flavor, ISO built end to end, boot tested in BIOS and
  EFI, composition manifest verified, size and boot guardrails in CI.
- **v0.2 — in progress.** CI is green on both architectures, the ISO rebuilds
  identically on another machine, and `v2026.10` is published. What remains is the
  signed release (minisign key to create, unencrypted: minisign doesn't read a
  password from the environment) and the `aarch64` boot test, to be done by hand.
- **v0.3** — automatic monthly release, blocking size budget and boot test.
- **v1.0** — complete verification documentation.
- **v2** — persistence, then possibly a graphical flavor.

## Tree

```
flake.nix                  inputs and outputs: ISO, tests, guardrails
modules/base.nix           foundation: firmware, kernel, licenses, SSH, boot marker
modules/tools.nix          tool selection, capability vs convenience, sized
modules/iso.nix            name, boot menu, compression, volume
nix/qemu-run.sh            QEMU launch: interactive or marker-based test
nix/closure-manifest.nix   composition manifest (the proof)
docs/budget.md             size measurements and the project rule
docs/design.md             architecture decisions and their rationale
```
