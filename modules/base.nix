# The Dépannix foundation: what is not negotiable, as opposed to the tools.
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:

let
  inherit (lib)
    mkForce
    mkIf
    mkOption
    optional
    types
    ;

  cfg = config.depannix;
in
{
  imports = [
    (modulesPath + "/installer/cd-dvd/installation-cd-base.nix")
  ];

  options.depannix = {
    version = mkOption {
      type = types.str;
      default = "2026.10";
      description = "CalVer version of the medium, reused in the ISO file name.";
    };

    flavour = mkOption {
      type = types.enum [ "minimal" ];
      default = "minimal";
      description = "Flavour being built. Only one so far, by choice.";
    };

    squashfsCompression = mkOption {
      type = types.str;
      default = "zstd -Xcompression-level 19";
      description = ''
        Options passed to mksquashfs. zstd-19 is the nixpkgs default and offers
        a good size/time trade-off; level 3 is there to iterate fast.
      '';
    };

    enableZfs = mkOption {
      type = types.bool;
      default = true;
      description = ''
        ZFS ships here, and it is redistributable, unlike SystemRescue which
        excludes it for licensing reasons.
      '';
    };

    enableSsh = mkOption {
      type = types.bool;
      default = true;
      description = ''
        sshd runs, but keys only: PermitRootLogin is forced to
        "prohibit-password" and no password is ever set.
        Indispensable to work on a machine with no screen.
      '';
    };

    authorizedKeys = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Public keys for the root and nixos accounts. Empty by default: a
        personal key is never baked into an artefact meant to be published.
        One can always drop a key on the USB stick by hand.
      '';
    };

    extraTools = mkOption {
      type = types.listOf types.package;
      default = [ ];
      description = "Additional tools, reserved for plugins and tests.";
    };
  };

  config = {
    # ── Identity ─────────────────────────────────────────────────────────────
    system.nixos.distroName = "Dépannix";
    networking.hostName = "depannix";

    # ── Firmware: redistributable only ───────────────────────────────────────
    # installation-cd-base enables enableAllHardware, which also pulls in
    # firmware under non-redistributable licences (b43, facetimehd…). We keep
    # to the redistributable set: that is what makes publishing the image
    # composition legitimate.
    #
    # Measured cost, taken from the image manifest itself: 836.4 MiB, i.e. 34 %
    # of the closure, with linux-firmware-20260916-zstd alone at 809.5 MiB.
    # See docs/budget.md — an earlier revision of this comment claimed 1884 MiB
    # and 76 %, which was wrong by a factor of two.
    hardware.enableAllHardware = mkForce false;
    hardware.enableAllFirmware = mkForce false;
    hardware.enableRedistributableFirmware = true;

    # ── Documentation: pointless on a rescue medium ──────────────────────────
    # installation-cd-minimal re-enables it with override 500 → mkForce needed.
    # Package man pages are not affected, only the NixOS/nixpkgs manuals.
    documentation.enable = mkForce false;
    documentation.nixos.enable = mkForce false;
    documentation.man.enable = mkForce false;
    documentation.doc.enable = mkForce false;

    # ── Kernel ───────────────────────────────────────────────────────────────
    # Console log level. An ordering trap: nixpkgs appends `loglevel=` AFTER
    # kernelParams, so writing "loglevel=7" in boot.kernelParams does nothing —
    # the default (4) wins and the serial console stays mute, which makes a boot
    # failure undiagnosable in CI. Verified on the command line burned into the
    # ISO:
    #   init=… console=ttyS0,115200 console=tty1 boot.shell_on_fail
    #   nohibernate root=fstab loglevel=4 lsm=landlock,yama,bpf
    boot.consoleLogLevel = 7;

    # boot.kernelParams does feed the ISO boot entries
    # (iso-image.nix: `params = "init=… ${toString cfg.boot.kernelParams}"`).
    boot.kernelParams = [
      "console=ttyS0,115200" # this is what makes the automated boot test possible
      "console=tty1"
      "boot.shell_on_fail" # a shell rather than a dead screen
    ];

    boot.supportedFilesystems = [
      "btrfs"
      "exfat"
      "ext2"
      "ext4"
      "f2fs"
      "jfs"
      "nilfs2"
      "ntfs"
      "vfat"
      "xfs"
      "bcachefs"
    ]
    ++ optional cfg.enableZfs "zfs";

    # With ZFS in the image, the kernel must be the one the ZFS module was built
    # against — otherwise the module fails to build or the pool cannot be
    # mounted.
    #
    # We pin an explicit LTS, and NOT
    # `config.boot.zfs.package.latestCompatibleLinuxPackages`: that one is
    # deprecated and now points at the default kernel, so it guarantees nothing
    # while giving the illusion that it does (observed: default kernel = 6.18.55
    # = linuxPackages_6_18). With a flake that bumps every month, drift would be
    # silent until the day the ZFS module no longer builds. An explicit LTS that
    # reaches end of life fails evaluation instead: loud, therefore fixable.
    boot.kernelPackages = mkIf cfg.enableZfs pkgs.linuxPackages_6_18;

    # ── Licences ─────────────────────────────────────────────────────────────
    # Implicit (default) but spelled out, because it is a project rule:
    # everything inside the ISO must be redistributable. Corollary: no
    # memtest86-efi (Passmark edition), we keep memtest86plus (GPL).
    nixpkgs.config.allowUnfree = false;

    # ── Accounts ─────────────────────────────────────────────────────────────
    # The "installation device" profile sets an empty password on root and nixos
    # and enables autologin on the terminal. That is the expected behaviour of a
    # live medium — but it is documented in the README, not hidden.
    users.users.root.openssh.authorizedKeys.keys = cfg.authorizedKeys;
    users.users.nixos.openssh.authorizedKeys.keys = cfg.authorizedKeys;

    services.openssh = {
      enable = mkIf cfg.enableSsh true;
      # Never password authentication on a public artefact.
      settings.PermitRootLogin = mkForce "prohibit-password";
      settings.PasswordAuthentication = mkForce false;
    };

    # ── Readiness marker ─────────────────────────────────────────────────────
    # Used by the CI boot test: we write to ttyS0 explicitly, so as not to
    # depend on the order of the `console=` arguments on the command line.
    systemd.services.depannix-ready = {
      description = "Announce that Dépannix is ready";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        msg="DEPANNIX_READY version=${cfg.version} ${config.system.nixos.label}"
        echo "$msg" > /dev/ttyS0 || true
        echo "$msg" > /dev/console || true
      '';
    };
  };
}
