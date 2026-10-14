# Socle de Dépannix : ce qui n'est pas négociable, par opposition aux outils.
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
      description = "Version CalVer du média, réutilisée dans le nom de l'ISO.";
    };

    flavour = mkOption {
      type = types.enum [ "minimal" ];
      default = "minimal";
      description = "Saveur construite. Une seule pour l'instant, par choix.";
    };

    squashfsCompression = mkOption {
      type = types.str;
      default = "zstd -Xcompression-level 19";
      description = ''
        Options passées à mksquashfs. zstd-19 est le défaut de nixpkgs et offre
        un bon rapport taille/temps ; le niveau 3 sert à itérer vite.
      '';
    };

    enableZfs = mkOption {
      type = types.bool;
      default = true;
      description = ''
        ZFS est présent ici et redistribuable, contrairement à SystemRescue qui
        l'exclut pour raisons de licence.
      '';
    };

    enableSsh = mkOption {
      type = types.bool;
      default = true;
      description = ''
        sshd actif, mais clé uniquement : PermitRootLogin est forcé à
        « prohibit-password » et aucun mot de passe n'est défini.
        Indispensable pour intervenir sur une machine sans écran.
      '';
    };

    authorizedKeys = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Clés publiques des comptes root et nixos. Vide par défaut : on ne
        bave jamais une clé personnelle dans un artefact destiné à être publié.
        On peut toujours en déposer une à la main sur la clé USB.
      '';
    };

    extraTools = mkOption {
      type = types.listOf types.package;
      default = [ ];
      description = "Outils additionnels, à réserver aux greffons et aux tests.";
    };
  };

  config = {
    # ── Identité ─────────────────────────────────────────────────────────────
    system.nixos.distroName = "Dépannix";
    networking.hostName = "depannix";

    # ── Firmware : redistribuable uniquement ────────────────────────────────
    # installation-cd-base active enableAllHardware, qui embarque aussi du
    # firmware sous licence non redistribuable (b43, facetimehd…). On garde le
    # périmètre redistribuable : c'est ce qui rend légitime la publication de
    # la composition de l'image. Coût mesuré : 1884 MiB de store (76 % du socle).
    hardware.enableAllHardware = mkForce false;
    hardware.enableAllFirmware = mkForce false;
    hardware.enableRedistributableFirmware = true;

    # ── Documentation : inutile sur un média de rescue ───────────────────────
    # installation-cd-minimal la réactive à l'override 500 → mkForce obligatoire.
    # Les pages man des paquets ne sont pas concernées, seulement les manuels
    # NixOS/nixpkgs.
    documentation.enable = mkForce false;
    documentation.nixos.enable = mkForce false;
    documentation.man.enable = mkForce false;
    documentation.doc.enable = mkForce false;

    # ── Noyau ────────────────────────────────────────────────────────────────
    # boot.kernelParams alimente bien les entrées de boot de l'ISO
    # (iso-image.nix : `params = "init=… ${toString cfg.boot.kernelParams}"`).
    boot.kernelParams = [
      "console=ttyS0,115200" # ce qui rend le test de boot automatisé possible
      "console=tty1"
      "boot.shell_on_fail" # un shell plutôt qu'un écran mort
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

    # Avec ZFS dans l'image, le noyau doit être celui contre lequel le module
    # ZFS a été construit — sinon la compilation du module échoue ou le pool
    # n'est pas montable. C'est l'astuce la plus utile récupérée de n8henrie.
    boot.kernelPackages = mkIf cfg.enableZfs config.boot.zfs.package.latestCompatibleLinuxPackages;

    # ── Licences ─────────────────────────────────────────────────────────────
    # Implicite (défaut) mais on l'écrit, parce que c'est une règle du projet :
    # tout ce qui est dans l'ISO doit pouvoir être redistribué. Corollaire :
    # pas de memtest86-efi (édition Passmark), on garde memtest86plus (GPL).
    nixpkgs.config.allowUnfree = false;

    # ── Comptes ──────────────────────────────────────────────────────────────
    # Le profil « installation device » met un mot de passe vide sur root et
    # nixos et active l'autologin au terminal. C'est le comportement attendu
    # d'un média live — mais il est documenté dans le README, pas caché.
    users.users.root.openssh.authorizedKeys.keys = cfg.authorizedKeys;
    users.users.nixos.openssh.authorizedKeys.keys = cfg.authorizedKeys;

    services.openssh = {
      enable = mkIf cfg.enableSsh true;
      # Jamais d'authentification par mot de passe sur un artefact public.
      settings.PermitRootLogin = mkForce "prohibit-password";
      settings.PasswordAuthentication = mkForce false;
    };

    # ── Marqueur de disponibilité ────────────────────────────────────────────
    # Sert au test de boot en CI : on écrit sur ttyS0 explicitement, pour ne
    # pas dépendre de l'ordre des `console=` sur la ligne de commande.
    systemd.services.depannix-ready = {
      description = "Annonce que Dépannix est prêt";
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
