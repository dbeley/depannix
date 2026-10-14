# Tool selection.
#
# Project rule: no tool enters the ISO without its closure figure. The sizes
# below are measured offline, without building anything:
#
#   nix path-info --store https://cache.nixos.org -rs --json <outPath>
#
# The core / optional split is not cosmetic: it separates *capability* (you
# cannot repair without it) from *convenience* (cosmetic or redundant).
{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    mkOption
    types
    ;

  # ── Capability: every entry maps to a repair gesture ──────────────────────
  core = with pkgs; [
    # Partitioning and filesystems
    parted # partition table manipulation
    gptfdisk # GPT, including rebuilding a corrupted table
    dosfstools # FAT/exFAT: EFI partitions
    e2fsprogs # fsck.ext4, dumpe2fs, debugfs
    exfatprogs
    ntfs3g
    xfsprogs
    btrfs-progs
    f2fs-tools
    jfsutils
    nilfs-utils
    bcachefs-tools
    mdadm # software RAID arrays
    lvm2 # LVM: the most common "my volumes disappeared" case
    cryptsetup # LUKS: open an encrypted disk from a live medium
    squashfs-tools
    partclone # block-level cloning, filesystem-aware
    fsarchiver # filesystem backup/restore across another filesystem

    # Data recovery and cloning
    testdisk # testdisk + photorec: partition tables and deleted files
    ddrescue # read a dying disk, resumable
    nwipe # secure erasure
    dcfldd # instrumented dd, hashes on the fly
    sleuthkit # raw filesystem inspection (fls, icat, mmls)

    # Hardware diagnostics
    smartmontools # smartctl: disk health
    nvme-cli
    hdparm
    sdparm
    lshw # readable hardware inventory
    dmidecode # DMI/firmware: serial number, BIOS, memory slots
    pciutils # lspci
    usbutils # lsusb
    ethtool # link-layer state: autoneg, speed, errors

    # Network
    iperf3
    nmap
    tcpdump
    socat

    # Command-line working comfort (useful for diagnosis, not decorative)
    jq
    zstd
    file # identify content when extensions lie
    lsof
    strace
    tmux
    screen
    rsync
    nano
    less
  ];

  # ── Convenience: measured, therefore accepted as optional ─────────────────
  # Figures = closure of the package alone, measured through the official
  # binary cache. Beware: these values do not add up (shared dependencies are
  # counted several times). They rank the cost, they do not budget it.
  # The exact budget is the union — see docs/budget.md.
  optional = {
    fzf = pkgs.fzf; # 50 MiB   11 paths
    fd = pkgs.fd; # 51 MiB    7 paths
    ripgrep = pkgs.ripgrep; # 56 MiB    8 paths
    eza = pkgs.eza; # 62 MiB   13 paths  — modern ls
    bat = pkgs.bat; # 73 MiB   16 paths  — cat with colour
    hwinfo = pkgs.hwinfo; # 135 MiB  27 paths
    inxi = pkgs.inxi; # 140 MiB  35 paths — system summary in one command
    neovim = pkgs.neovim; # 262 MiB 115 paths — editor
    fish = pkgs.fish; # 309 MiB  45 paths — the most expensive luxury here
    gsmartcontrol = pkgs.gsmartcontrol; # 317 MiB 112 paths — smartctl GUI
    gparted = pkgs.gparted; # 385 MiB 132 paths — partitioning GUI
    phoronix-test-suite = pkgs.phoronix-test-suite; # 606 MiB 139 paths (PHP)
    guymager = pkgs.guymager; # 2540 MiB 259 paths — Qt forensic imager
  };
in
{
  options.depannix.optionalTools = mkOption {
    type = types.listOf (types.enum (builtins.attrNames optional));
    default = [
      "fzf"
      "ripgrep"
      "fd"
    ];
    description = ''
      Convenience tools that are enabled. By default only three, weighing
      ~157 MiB together (individual closures): even comfort has a price.
      Enabling `fish`, `gparted` or `guymager` costs hundreds of MiB; the CI
      size guard will flag it. Measurements: docs/budget.md.
    '';
  };

  config.environment.systemPackages =
    core
    ++ lib.optionals config.depannix.enableZfs [ pkgs.zfs ]
    ++ map (n: optional.${n}) config.depannix.optionalTools
    ++ config.depannix.extraTools;
}
