# Décisions d'architecture

Ce document explique les choix, y compris ceux qui coûtent, pour qu'ils ne
soient pas rediscutés dans six mois sans contexte.

## Pourquoi NixOS plutôt qu'un remaster Debian/Arch

La sélection d'outils n'est pas le problème : dans SystemRescue, Grml ou Hiren's,
la liste est figée à la gravure. C'est ça qui vieillit mal. Avec NixOS :

- le catalogue s'étend à la demande (`nix shell nixpkgs#…`) sans reflasher ;
- la composition de l'image est une valeur calculable, donc publiable ;
- la mise à jour mensuelle est un `flake.lock` qui bouge, pas une reconstruction
  à la main.

Contrepartie acceptée : une ISO de ~1,3-1,5 GiB contre 1,29 GiB pour SystemRescue,
et l'obligation de désactiver Secure Boot.

## Pourquoi la copie de nixpkgs reste dans l'ISO

`profiles/installation-device.nix` embarque la source complète de nixpkgs
(200 MiB de store), `stdenvNoCC`, `busybox` et `jq` (81 MiB) — mesuré, soit
~281 MiB de store, une centaine de mégaoctets d'ISO. C'est délibéré : ça permet de
**construire un paquet depuis les sources sans réseau**. Un média de dépannage
qui suppose une machine saine est un contresens.

## Pourquoi le firmware redistribuable seulement

`installation-cd-base.nix` active `hardware.enableAllHardware`, qui embarque du
firmware sous licence non redistribuable. On le force à `false` et on active
`enableRedistributableFirmware`. C'est le socle de la règle n°2 : on publie la
composition de l'image, donc tout ce qu'elle contient doit être redistribuable.
Coût : 1884 MiB de store, 70 % du socle. Le firmware est **le** poste de dépense,
pas les outils.

## Pourquoi pas d'interface graphique en v1

Deux raisons, chiffrées et non esthétiques :

- `nautilus` seul = 1162 MiB de closure, `gparted` = 385 MiB, `gsmartcontrol` =
  317 MiB. L'ISO graphique officielle de NixOS pèse 3574 MiB contre 1533 MiB pour
  la minimale.
- GNOME Files monte automatiquement tout ce qu'on branche. En récupération de
  données ou en forensique, c'est exactement le geste qui écrit sur le système
  qu'on essaie de sauver.

Si une saveur graphique arrive, elle devra embarquer une politique d'automount
désactivée et une entrée de boot dédiée.

## Récupéré de `n8henrie/nixos-rescue` — et jeté

Le projet est inactif depuis trois ans, mais deux choses valent la reprise :

- **La structure du flake** : `nixosModules.default` + `packages.default` +
  une app qui démarre l'image en VM. Le module réutilisable permet d'ajouter plus
  tard une entrée de boot « Dépannix » sur une machine installée.
- **Le harnais QEMU** (`graphics = false`, disque en cdrom lecture seule, port
  forwardé) et deux paramètres noyau qui changent tout : `boot.shell_on_fail` et
  `console=ttyS0` — c'est ce dernier qui rend le test de boot automatisé possible.
  Son `memorySize = 2048` est trop juste pour une ISO de ~1,4 GiB avec
  `copytoram` : passé à 3072.
- **`boot.kernelPackages = zfs.latestCompatibleLinuxPackages`** : garantit que le
  module ZFS colle au noyau. Utile dès qu'on embarque ZFS.
- **`boot.supportedFilesystems` étendu** : on ajoute `bcachefs`, `f2fs`,
  `nilfs2`, `jfs`.

Jeté :

- `nixpkgs/nixos-22.11` (la cause du vieillissement) ;
- `nixpkgs.config.allowUnfree = true` — incompatible avec un artefact public dont
  on publie la composition ;
- `users.users.root.password = "rescue"` en clair, et surtout
  `authorizedKeys.keyFiles = fetchurl github.com/n8henrie.keys` : une clé
  personnelle bakée dans un artefact public. Ici, `depannix.authorizedKeys` est
  vide par défaut ;
- `binfmt.emulatedSystems = [ "aarch64-linux" ]` : embarquait QEMU user pour
  émuler arm64. Devenu inutile avec les runners arm64 natifs ;
- sa liste de paquets, trop maigre : ni `testdisk`/`photorec`, ni `lshw`, ni
  `dmidecode`, ni `fsarchiver`, ni `nwipe`, ni `nvme-cli`, ni ZFS explicite.

## La décision ZFS / noyau

Embarquer ZFS impose `zfs.latestCompatibleLinuxPackages`, donc un noyau LTS
plutôt que le tout dernier. C'est un arbitrage contre le support du matériel le
plus récent. Il est assumé : ZFS est un différenciateur réel face à SystemRescue,
qui l'exclut pour raisons de licence, et le module NixOS en est un utilisateur
naturel. Pour la machine neuve au matériel inconnu, `nomodeset` et le firmware
complet couvrent l'essentiel.

## Contraintes CI, vérifiées

| Point | Constat |
|---|---|
| Runners x86_64 | 4 vCPU / 16 Go / 14 Go de SSD, gratuits et illimités sur repo public |
| `/dev/kvm` sur x86_64 | **présent** sur les runners standard, mais non documenté. Nécessite une règle udev (`static_node=kvm`, l'utilisateur du runner n'est pas dans le groupe `kvm`) et l'installation de `qemu-system-x86`, absent de l'image |
| `/dev/kvm` sur arm64 | **absent à tous les niveaux** — limitation du SKU Azure ARM, pas de l'image. Le test de boot aarch64 reste donc manuel |
| Disque | ~2,7 GiB de store + squashfs + ISO ≈ 5 GiB : large dans les 14 Go |
| Cache binaire | `magic-nix-cache-action` a été abandonné en février 2025 puis ressuscité — on ne bâtit pas dessus. Cachix est le choix durable, non configuré en v0.1 |

Le workflow échoue explicitement si `/dev/kvm` est absent : sans ce garde-fou,
QEMU retombe silencieusement en émulation logicielle et le job expire au lieu
d'échouer.

## Le marqueur de boot

Le test de boot ne peut pas se contenter de « QEMU a démarré ». Une unité systemd
`depannix-ready` écrit `DEPANNIX_READY` sur `/dev/ttyS0` explicitement — pas via
`/dev/console`, dont la destination dépend de l'ordre des `console=` sur la ligne
de commande. C'est aussi la manière la plus simple de prouver que le système est
réellement arrivé au multi-utilisateur.

## Points ouverts

- `boot.zfs.forceImportRoot` : par défaut, le système live peut importer les pools
  ZFS de la machine dépannée. Sur un média de récupération, un import automatique
  en écriture mérite d'être examiné de près.
- Ordre `console=ttyS0` puis `console=tty1` : sur une machine sans écran, à
  vérifier ; sur une machine avec écran, le message du marqueur doit rester
  discret.
- Reproductibilité bit-à-bit de l'ISO : à mesurer, pas à supposer.
- `isoImage.forceTextMode` et les entrées de boot additionnelles (`copytoram`,
  mode forensic) ne sont pas encore câblées.
