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

Contrepartie acceptée : une ISO de 1,42 GiB contre 1,29 GiB pour SystemRescue
(chiffres mesurés, voir `docs/budget.md`), et l'obligation de désactiver Secure
Boot.

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

Coût, **mesuré sur le manifeste de l'image réelle** et non sur une maquette : la
closure fait 732 chemins pour 2467,7 MiB, dont 836,0 MiB de firmware, soit 34 %.
Le plus gros poste isolé est `linux-firmware-20260916-zstd` à 809,5 MiB.

Correction de méthode au passage : le chiffre de 1884 MiB qui figurait ici venait
du paquet `linux-firmware` **monolithique**, alors que l'image embarque la variante
`-zstd`, nettement plus légère — et il ignorait les 546 autres chemins du système
(systemd, outils Nix, pile Perl, Python, git). Le firmware reste le premier poste
de dépense, mais à 34 % du total et non 70 % : c'est la hiérarchie des priorités
qui était fausse, pas seulement le montant.

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
- **L'intention de `boot.kernelPackages = zfs.latestCompatibleLinuxPackages`** :
  faire coller le module ZFS et le noyau. L'intention est juste, l'expression ne
  l'est plus — voir « La décision ZFS / noyau ».
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

Embarquer ZFS impose un noyau contre lequel le module ZFS est construit, donc un
noyau LTS plutôt que le tout dernier. C'est un arbitrage contre le support du
matériel le plus récent. Il est assumé : ZFS est un différenciateur réel face à
SystemRescue, qui l'exclut pour raisons de licence, et le module NixOS en est un
utilisateur naturel. Pour la machine neuve au matériel inconnu, `nomodeset` et le
firmware complet couvrent l'essentiel.

**Ce que la construction a révélé.** L'expression héritée est dépréciée. nixpkgs
émet désormais :

> `zfs.latestCompatibleLinuxPackages is deprecated and is now pointing at the`
> `default kernel.`

Mesuré : le noyau par défaut *est* 6.18.55, soit exactement
`linuxPackages_6_18`. Autrement dit, l'expression produisait le même résultat que
« ne rien écrire », tout en donnant l'illusion d'une garantie. Avec un
`flake.lock` qui bouge tous les mois, la dérive aurait été silencieuse jusqu'au
jour où le module ZFS cesse de compiler.

On épingle donc explicitement `pkgs.linuxPackages_6_18`. Une LTS en fin de vie
fait échouer l'évaluation — bruyant, donc réparable — au lieu de dériver sans
rien dire. C'est l'inverse du choix fait partout ailleurs dans le projet, où l'on
suit `nixos-unstable` : ici, suivre le défaut n'est pas neutre, c'est précisément
perdre la propriété qu'on cherchait.

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

**Piège découvert à l'exécution, un cran plus bas.** Ce garde-fou ne suffisait
pas. Le test de boot est un `nix build`, donc il s'exécute dans le **bac à sable
Nix**, qui n'expose pas `/dev/kvm` aux constructions. Le runner avait beau
l'activer, le QEMU du test ne le voyait pas et retombait en émulation — soit
exactement la panne que le garde-fou prétendait empêcher, mais placée sous lui.
Il faut injecter le périphérique dans le bac à sable :

```bash
nix build --option extra-sandbox-paths /dev/kvm .#checks.<system>.boot-test-bios
```

Vérifié : le journal de construction affiche `[qemu] KVM actif` **dans** le bac à
sable.

## Le marqueur de boot

Le test de boot ne peut pas se contenter de « QEMU a démarré ». Une unité systemd
`depannix-ready` écrit `DEPANNIX_READY` sur `/dev/ttyS0` explicitement — pas via
`/dev/console`, dont la destination dépend de l'ordre des `console=` sur la ligne
de commande. C'est aussi la manière la plus simple de prouver que le système est
réellement arrivé au multi-utilisateur.

## La console série, et pourquoi elle était muette

Diagnostic instructif. Le marqueur apparaissait bien, mais `serial.log` ne
contenait que 20 lignes : un échec de démarrage aurait donc été indiagnosticable
en CI. La cause n'était ni `quiet`, ni un `console=` manquant. C'est la ligne de
commande **réellement gravée dans l'ISO** qui l'a dit :

```
init=… console=ttyS0,115200 console=tty1 boot.shell_on_fail nohibernate root=fstab loglevel=4 lsm=landlock,yama,bpf
```

`loglevel=4` est ajouté par nixpkgs **après** les `boot.kernelParams`. Écrire
`loglevel=7` dans `boot.kernelParams` n'aurait donc rien changé : la valeur
ajoutée en dernier l'emporte. Le levier correct est l'option dédiée
`boot.consoleLogLevel`, insérée à la bonne place.

Leçon générale : quand une option ne produit pas l'effet attendu dans un
assemblage, lire l'artefact final plutôt que la source. Un `grep` sur l'ISO a
tranché en une commande ce que la lecture des modules nixpkgs n'avait pas donné.

## Points ouverts

- `boot.zfs.forceImportRoot` : par défaut, le système live peut importer les pools
  ZFS de la machine dépannée. Sur un média de récupération, un import automatique
  en écriture mérite d'être examiné de près.
- Ordre `console=ttyS0` puis `console=tty1` : mesuré, le **dernier** `console=`
  emporte `/dev/console`, donc il pointe sur `tty1` (l'écran). Conséquence : en
  cas d'échec, le shell de secours de `boot.shell_on_fail` s'affiche sur l'écran
  et **pas** sur la série, donc invisible dans le journal de la CI. À trancher :
  accepter un journal série bavard mais sans shell de secours, ou inverser
  l'ordre pour la machine sans écran.
- Reproductibilité bit-à-bit de l'ISO : à mesurer, pas à supposer.
- `isoImage.forceTextMode` et les entrées de boot additionnelles (`copytoram`,
  mode forensic) ne sont pas encore câblées.
- Test de boot aarch64 : manuel, faute de `/dev/kvm` sur les runners ARM.
