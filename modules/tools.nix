# Sélection des outils.
#
# Règle du projet : aucun outil n'entre dans l'ISO sans son chiffre de closure.
# Les tailles ci-dessous sont mesurées hors ligne, sans rien construire :
#
#   nix path-info --store https://cache.nixos.org -rs --json <outPath>
#
# Le tri « core / optional » n'est pas esthétique : il sépare la *capacité*
# (on ne peut pas réparer sans) du *confort* (cosmétique ou redondant).
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

  # ── Capacité : chaque entrée correspond à un geste de dépannage ────────────
  core = with pkgs; [
    # Partitionnement et systèmes de fichiers
    parted # manipulation de tables de partitions
    gptfdisk # GPT, notamment la reconstruction de table corrompue
    dosfstools # FAT/exFAT : partitions EFI
    e2fsprogs # fsck.ext4, dumpe2fs, debugfs
    exfatprogs
    ntfs3g
    xfsprogs
    btrfs-progs
    f2fs-tools
    jfsutils
    nilfs-utils
    bcachefs-tools
    mdadm # grappes RAID logicielles
    lvm2 # LVM : le cas le plus fréquent de « mes volumes ont disparu »
    cryptsetup # LUKS : ouvrir un disque chiffré depuis un live
    squashfs-tools
    partclone # clonage au niveau bloc, avec conscience du FS
    fsarchiver # sauvegarde/restauration de FS par-dessus un autre FS

    # Récupération de données et clonage
    testdisk # testdisk + photorec : tables de partitions et fichiers effacés
    ddrescue # lecture d'un disque qui meurt, avec reprise
    nwipe # effacement sécurisé
    dcfldd # dd instrumenté, hachage à la volée
    sleuthkit # inspection de FS brut (fls, icat, mmls)

    # Diagnostic matériel
    smartmontools # smartctl : santé des disques
    nvme-cli
    hdparm
    sdparm
    lshw # inventaire matériel lisible
    dmidecode # DMI/firmware : numéro de série, BIOS, slots mémoire
    pciutils # lspci
    usbutils # lsusb
    ethtool # état de la couche liaison : autoneg, vitesse, erreurs

    # Réseau
    iperf3
    nmap
    tcpdump
    socat

    # Confort de travail en ligne de commande (utile au diagnostic, pas décoratif)
    jq
    zstd
    file # identifier un contenu quand les extensions mentent
    lsof
    strace
    tmux
    screen
    rsync
    nano
    less
  ];

  # ── Confort : mesuré, donc assumé comme optionnel ─────────────────────────
  # Chiffres = closure du paquet seul, mesurée via le cache binaire officiel.
  # Attention : ces valeurs ne s'additionnent pas (les dépendances communes
  # sont comptées plusieurs fois). Elles servent au classement, pas au budget.
  # Le budget exact, c'est l'union — voir docs/budget.md.
  optional = {
    fzf = pkgs.fzf; # 50 MiB   11 chemins
    fd = pkgs.fd; # 51 MiB    7 chemins
    ripgrep = pkgs.ripgrep; # 56 MiB    8 chemins
    eza = pkgs.eza; # 62 MiB   13 chemins  — ls moderne
    bat = pkgs.bat; # 73 MiB   16 chemins  — cat avec coloration
    hwinfo = pkgs.hwinfo; # 135 MiB  27 chemins
    inxi = pkgs.inxi; # 140 MiB  35 chemins — résumé système en une commande
    neovim = pkgs.neovim; # 262 MiB 115 chemins — éditeur
    fish = pkgs.fish; # 309 MiB  45 chemins — le luxe le plus cher du lot
    gsmartcontrol = pkgs.gsmartcontrol; # 317 MiB 112 chemins — GUI smartctl
    gparted = pkgs.gparted; # 385 MiB 132 chemins — GUI de partitionnement
    phoronix-test-suite = pkgs.phoronix-test-suite; # 606 MiB 139 chemins (PHP)
    guymager = pkgs.guymager; # 2540 MiB 259 chemins — imageur forensic Qt
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
      Outils de confort activés. Par défaut, seulement trois qui pèsent
      ~157 MiB à eux trois (closures individuelles) : même la commodité se paie.
      Activer `fish`, `gparted` ou `guymager` se compte en centaines de MiB ;
      le garde-fou de taille en CI le signalera. Mesures : docs/budget.md.
    '';
  };

  config.environment.systemPackages =
    core
    ++ lib.optionals config.depannix.enableZfs [ pkgs.zfs ]
    ++ map (n: optional.${n}) config.depannix.optionalTools
    ++ config.depannix.extraTools;
}
