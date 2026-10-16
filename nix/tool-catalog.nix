# The catalogue of tools that ship in the image.
#
# This is data, not wiring, and it exists because of a rule: a tool that enters
# the ISO carries its closure figure, and now also the gesture it covers. A list
# of package names with prose comments beside it cannot be displayed, searched or
# verified - it drifts the moment someone adds a tool. This file is the single
# source that the image, the catalogue command and the documentation all read.
#
# `category` drives the grouping the operator sees. `gesture` is what a person
# looking at a dead machine is actually searching for: "my volumes disappeared",
# not "lvm2". Keep both short; they are printed.
#
# `figure` is the closure measured through the official binary cache, recorded
# for the optional tools only, as in the original list. The core set is measured
# in docs/budget.md. A tool without a figure is refused for the optional set.
#
# `flavours` says which images carry the entry. The minimal flavour is a console
# plus a bare Wayland session; the desktop flavour is GNOME and a browser. An
# entry with no `flavours` ships in both. Without this field the catalogue would
# have to claim that the minimal image carries a browser, or that the desktop one
# carries labwc, and it would be lying in both directions.
#
# Order matters here for one reason: it is the order the packages are wired into
# the system, and keeping it makes a change to this file provably inert. The
# catalogue's own display order is a separate concern.
{ pkgs }:

rec {
  knownFlavours = [
    "minimal"
    "desktop"
  ];

  # One place decides what an entry with no explicit scope means. The image and
  # the catalogue command both read it here, so they cannot disagree.
  flavoursOf = e: e.flavours or knownFlavours;

  # ── Capability: every entry maps to a repair gesture ──────────────────────
  core = [
    # Partitioning and filesystems
    { name = "parted"; category = "partitioning"; gesture = "create, resize and move partitions"; }
    { name = "gptfdisk"; category = "partitioning"; gesture = "GPT, including rebuilding a corrupted table"; }
    { name = "dosfstools"; category = "partitioning"; gesture = "FAT32: the EFI partition, and old USB sticks"; }
    { name = "e2fsprogs"; category = "partitioning"; gesture = "ext2/3/4: fsck, dumpe2fs, debugfs"; }
    { name = "exfatprogs"; category = "partitioning"; gesture = "exFAT, the norm on large SD cards"; }
    { name = "ntfs3g"; category = "partitioning"; gesture = "mount and repair Windows filesystems"; }
    { name = "xfsprogs"; category = "partitioning"; gesture = "XFS: xfs_repair, xfs_db"; }
    { name = "btrfs-progs"; category = "partitioning"; gesture = "check, repair and inspect Btrfs"; }
    { name = "f2fs-tools"; category = "partitioning"; gesture = "F2FS, common on Android"; }
    { name = "jfsutils"; category = "partitioning"; gesture = "JFS: check and repair"; }
    { name = "nilfs-utils"; category = "partitioning"; gesture = "NILFS2, still met in the wild"; }
    { name = "bcachefs-tools"; category = "partitioning"; gesture = "the newest copy-on-write filesystem"; }
    { name = "mdadm"; category = "partitioning"; gesture = "assemble and inspect software RAID"; }
    { name = "lvm2"; category = "partitioning"; gesture = "LVM, the most common \"my volumes disappeared\""; }
    { name = "cryptsetup"; category = "partitioning"; gesture = "open a LUKS disk from outside its system"; }
    { name = "squashfs-tools"; category = "partitioning"; gesture = "the very filesystem this medium runs on"; }
    { name = "partclone"; category = "partitioning"; gesture = "block-level cloning that understands filesystems"; }
    { name = "fsarchiver"; category = "partitioning"; gesture = "filesystem backup and restore, across filesystems"; }

    # Data recovery and cloning
    { name = "testdisk"; category = "recovery"; gesture = "recover lost partitions, and deleted files with photorec"; }
    { name = "ddrescue"; category = "recovery"; gesture = "read a dying disk, and resume where it stopped"; }
    { name = "nwipe"; category = "recovery"; gesture = "secure erasure of a disk"; }
    { name = "dcfldd"; category = "recovery"; gesture = "dd with a hash computed as it writes"; }
    { name = "sleuthkit"; category = "recovery"; gesture = "raw filesystem inspection: fls, icat, mmls"; }

    # Hardware diagnostics
    { name = "smartmontools"; category = "diagnostics"; gesture = "smartctl: disk health and self-tests"; }
    { name = "nvme-cli"; category = "diagnostics"; gesture = "NVMe state, firmware and SMART log"; }
    { name = "hdparm"; category = "diagnostics"; gesture = "ATA parameters and throughput"; }
    { name = "sdparm"; category = "diagnostics"; gesture = "SCSI parameters"; }
    { name = "lshw"; category = "diagnostics"; gesture = "hardware inventory in one readable pass"; }
    { name = "dmidecode"; category = "diagnostics"; gesture = "serial number, BIOS version, memory slots"; }
    { name = "pciutils"; category = "diagnostics"; gesture = "what sits on the PCI bus"; }
    { name = "usbutils"; category = "diagnostics"; gesture = "what sits on the USB bus"; }
    { name = "ethtool"; category = "diagnostics"; gesture = "link state: autonegotiation, speed, errors"; }

    # Network
    { name = "iperf3"; category = "network"; gesture = "measure throughput between two machines"; }
    { name = "nmap"; category = "network"; gesture = "what listens, and what is on this network"; }
    { name = "tcpdump"; category = "network"; gesture = "capture traffic when nothing else explains it"; }
    { name = "socat"; category = "network"; gesture = "connect two sockets, whatever their type"; }

    # Benchmarking: measure a machine before a repair and after it, and make an
    # intermittent fault happen on purpose. Deliberately light: the heavy
    # benchmark suites stay in the optional set, with their size shown.
    { name = "openssl"; category = "benchmark"; gesture = "openssl speed: CPU throughput, algorithm by algorithm"; }
    { name = "p7zip"; category = "benchmark"; gesture = "7z b: compress and decompress, in MIPS"; }
    { name = "lz4"; category = "benchmark"; gesture = "lz4 -b: the fast compressor, in benchmark mode"; }
    { name = "sysbench"; category = "benchmark"; gesture = "cpu, memory, threads and file I/O"; }
    { name = "stress-ng"; category = "benchmark"; gesture = "load every subsystem until something breaks"; }
    { name = "fio"; category = "benchmark"; gesture = "the reference disk benchmark"; }
    { name = "hyperfine"; category = "benchmark"; gesture = "time any command, with statistics"; }
    { name = "ioping"; category = "benchmark"; gesture = "disk latency, probe by probe"; }
    { name = "john"; category = "benchmark"; gesture = "john --test: hash throughput, a classic CPU number"; }

    # Command-line working comfort - useful for diagnosis, not decorative
    { name = "jq"; category = "comfort"; gesture = "read and reshape JSON"; }
    { name = "zstd"; category = "comfort"; gesture = "compress, and decompress what you find"; }
    { name = "file"; category = "comfort"; gesture = "identify content when the extension lies"; }
    { name = "lsof"; category = "comfort"; gesture = "which process is holding that file"; }
    { name = "strace"; category = "comfort"; gesture = "what a program is actually doing"; }
    { name = "tmux"; category = "comfort"; gesture = "keep a session when the link drops"; }
    { name = "screen"; category = "comfort"; gesture = "the same, present on most machines you take over"; }
    { name = "rsync"; category = "comfort"; gesture = "copy, resume, and verify"; }
    { name = "nano"; category = "comfort"; gesture = "edit a file without learning an editor"; }
    { name = "less"; category = "comfort"; gesture = "read a file, including the awkward ones"; }

    # ── Graphical session: the minimal flavour ───────────────────────────────
    # Everything below is deliberately GPU-free: labwc renders through pixman,
    # foot through shared memory, and grim, slurp, swaybg, kanshi, swaylock,
    # mako and wl-clipboard are plain Wayland clients. That is not a detail, it
    # is the whole budget. Enabling OpenGL costs a mesa that weighs +826 MiB of
    # ISO, and a GTK application on Wayland cannot draw a pixel without it:
    # that is why no graphical tool appears in this block, and why gparted
    # moved to the desktop flavour. Measurements: docs/budget.md.
    { name = "labwc"; category = "graphics"; flavours = [ "minimal" ]; gesture = "the session itself: a compositor, no desktop on top"; }
    { name = "foot"; category = "graphics"; flavours = [ "minimal" ]; gesture = "a terminal inside the session, not another TTY"; }
    { name = "swaybg"; category = "graphics"; flavours = [ "minimal" ]; gesture = "something other than black behind the windows"; }
    { name = "grim"; category = "graphics"; flavours = [ "minimal" ]; gesture = "capture the screen: evidence for a bug report"; }
    { name = "slurp"; category = "graphics"; flavours = [ "minimal" ]; gesture = "pick the region grim should capture"; }
    { name = "wl-clipboard"; category = "graphics"; flavours = [ "minimal" ]; gesture = "copy between the session and the shell"; }
    { name = "mako"; category = "graphics"; flavours = [ "minimal" ]; gesture = "notifications, for what has none on a console"; }
    { name = "wlr-randr"; category = "graphics"; flavours = [ "minimal" ]; gesture = "arrange the outputs when the screen stays black"; }
    { name = "kanshi"; category = "graphics"; flavours = [ "minimal" ]; gesture = "the same arrangements, declared in a file"; }
    { name = "swaylock"; category = "graphics"; flavours = [ "minimal" ]; gesture = "lock a screen you are leaving behind"; }
    { name = "wayland-utils"; category = "graphics"; flavours = [ "minimal" ]; gesture = "wayland-info: what the compositor really offers"; }

    # ── Graphical session: the desktop flavour ───────────────────────────────
    # Here a driver is paid for anyway, because GNOME's shell needs one.
    { name = "gnome-shell"; category = "graphics"; flavours = [ "desktop" ]; gesture = "the GNOME session, on Wayland"; }
    { name = "firefox"; category = "graphics"; flavours = [ "desktop" ]; gesture = "read the documentation of the machine that will not boot"; }
    { name = "pipewire"; category = "graphics"; flavours = [ "desktop" ]; gesture = "sound, which a desktop session expects"; }

    # ── Graphical rescue tools: affordable once somebody else paid ───────────
    # Same packages, same question, opposite answer. Measured over the desktop
    # session: gparted costs +20.7 MiB of NAR and gnome-disk-utility +15.1 MiB,
    # because GTK4 and udisks2 are already there. In the minimal image neither
    # has a working driver, and the second would cost +318 MiB on top of it.
    { name = "gparted"; category = "partitioning"; flavours = [ "desktop" ]; gesture = "partitioning, with a screen"; }
    { name = "gnome-disk-utility"; category = "partitioning"; flavours = [ "desktop" ]; gesture = "gnome-disks: SMART, images and mounting, with a screen"; }

    # ── GPU benchmarks: only where a driver is paid for anyway ───────────────
    # In the minimal flavour these would each drag in mesa, measured at
    # +1304 MiB of NAR. On the desktop mesa is part of the session, and all
    # three together cost +37 MiB.
    { name = "glmark2"; category = "benchmark"; flavours = [ "desktop" ]; gesture = "OpenGL throughput, where a driver exists"; }
    { name = "vkmark"; category = "benchmark"; flavours = [ "desktop" ]; gesture = "Vulkan throughput, the modern equivalent"; }
    { name = "clpeak"; category = "benchmark"; flavours = [ "desktop" ]; gesture = "compute throughput of the GPU"; }
  ];

  # ── Convenience: measured, therefore accepted as optional ─────────────────
  # Figures are the closure of the package alone, through the official binary
  # cache. Beware: they do not add up - shared dependencies are counted several
  # times. They rank the cost, they do not budget it. The exact budget is the
  # union, see docs/budget.md, which also carries the marginal cost of each of
  # these over a running desktop session, where several of them are far cheaper
  # than the figure below suggests.
  optional = [
    { name = "fzf"; category = "comfort"; figure = "50 MiB, 11 paths"; gesture = "fuzzy-find anything, including this catalogue"; }
    { name = "fd"; category = "comfort"; figure = "51 MiB, 7 paths"; gesture = "find files by name, faster than find"; }
    { name = "ripgrep"; category = "comfort"; figure = "56 MiB, 8 paths"; gesture = "search inside files"; }
    { name = "eza"; category = "comfort"; figure = "62 MiB, 13 paths"; gesture = "ls with colour and structure"; }
    { name = "bat"; category = "comfort"; figure = "73 MiB, 16 paths"; gesture = "cat with syntax colouring"; }
    { name = "hwinfo"; category = "diagnostics"; figure = "135 MiB, 27 paths"; gesture = "hardware probes, verbosely"; }
    { name = "inxi"; category = "diagnostics"; figure = "140 MiB, 35 paths"; gesture = "system summary in one command"; }
    { name = "neovim"; category = "comfort"; figure = "262 MiB, 115 paths"; gesture = "edit files when nano is not enough"; }
    { name = "fish"; category = "comfort"; figure = "309 MiB, 45 paths"; gesture = "a shell that suggests as you type"; }
    { name = "gsmartcontrol"; category = "diagnostics"; figure = "317 MiB, 112 paths"; gesture = "smartctl, with a screen"; }
    { name = "phoronix-test-suite"; category = "benchmark"; figure = "606 MiB, 139 paths"; gesture = "benchmark and compare machines"; }
    { name = "gnome-system-monitor"; category = "diagnostics"; figure = "1009 MiB, 302 paths"; gesture = "what is running, and what it is eating"; }
    { name = "guymager"; category = "recovery"; figure = "2540 MiB, 259 paths"; gesture = "forensic imaging of a disk, with hashes"; }
  ];

  # Display order for the catalogue command: capability first, then comfort, then
  # what only makes sense with a screen. Within a category the order above holds.
  categoryOrder = [
    "partitioning"
    "recovery"
    "diagnostics"
    "benchmark"
    "network"
    "comfort"
    "graphics"
  ];
}
