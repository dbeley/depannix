# Dépannix

Environnement de dépannage NixOS, construit en ISO minimale, reproductible et
vérifiable. Un média qu'on peut étendre à la demande sans le reflasher, et dont
on peut publier la composition exacte.

**État : l'ISO se construit et démarre.** Construite de bout en bout, testée en
BIOS et en EFI sous KVM, composition vérifiée contre `cache.nixos.org`. Aucune
release publiée pour l'instant : la première sortira de la CI.

| | |
|---|---|
| ISO | 1453,2 MiB (1,419 GiB) |
| store embarqué | 732 chemins, 2467,7 MiB |
| hachages confirmés par `cache.nixos.org` | 685 sur 732, zéro divergence |
| dépôt | https://github.com/dbeley/depannix |

La recette pour vérifier soi-même est plus bas dans ce fichier.

## Démarrage

```bash
nix build .#minimal-fast          # ISO, compression rapide (itération locale)
nix build .#minimal               # ISO de release, compression zstd-19
nix run                           # démarre l'ISO dans QEMU
MODE=efi nix run                  # idem, en firmware EFI

nix build .#checks.x86_64-linux.boot-test-bios   # test de boot automatisé
nix build .#packages.x86_64-linux.closure-manifest
nix flake check                   # test de boot BIOS + EFI + budget de taille
```

Écrire sur une clé : `dd`, jamais une partition.

```bash
lsblk -o NAME,SIZE,TYPE,TRAN,MODEL     # repérer la clé : TRAN=usb
sudo dd if=result/iso/depannix-*.iso of=/dev/sdX bs=4M status=progress conv=fsync
```

## Ce qu'il y a dans l'image, et la vraie façon de l'étendre

La sélection est dans `modules/tools.nix`, séparée en **capacité** (on ne peut
pas réparer sans) et **confort** (optionnel, chiffré). Le détail des mesures est
dans `docs/budget.md`.

Le point qui change tout par rapport à SystemRescue ou Grml : **le catalogue
n'est pas figé à la gravure**. Une ISO NixOS embarque la copie de nixpkgs et
`stdenv`, donc sur une machine dépannée mais connectée :

```bash
nix shell nixpkgs#outil-quelconque    # n'importe lequel des ~100 000 paquets
```

C'est pour cette raison que 281 MiB de store sont volontairement dépensés en
copie de nixpkgs + `stdenvNoCC` : sans réseau, on peut encore construire un
paquet depuis les sources. Un média de dépannage qui suppose une machine saine
n'est pas un média de dépannage.

## Les règles du projet

1. **Aucun outil n'entre dans l'ISO sans son chiffre de closure** mesuré et
   inscrit dans `docs/budget.md`.
2. **Rien de non redistribuable.** `nixpkgs.config.allowUnfree = false`, et le
   firmware est limité au périmètre redistribuable (`hardware.enableAllHardware`
   est explicitement désactivé). C'est ce qui rend légitime de publier la
   composition de l'image.
3. **Aucun secret ni clé personnelle dans l'artefact.** `depannix.authorizedKeys`
   est vide par défaut ; sshd n'accepte que les clés, jamais les mots de passe.
4. **Une release ne part pas si un test échoue.** On reste sur le dernier mois
   vert plutôt que de publier une ISO qui ne boote pas.

## Prouver le contenu

Le projet vise un artefact dont n'importe qui peut vérifier la composition sans
faire confiance à celui qui l'a produit.

| Pièce | Ce qu'elle prouve |
|---|---|
| `flake.lock` (versionné) | la révision nixpkgs exacte, et donc tout l'arbre des dépendances |
| `closure-manifest` | la liste exhaustive des chemins du store embarqués + leur hachage |
| `SHA256SUMS` + signature minisign | l'ISO publiée est bien celle qui a été construite |
| attestation de provenance (CI) | l'artefact sort de ce workflow, sur ce commit |

Vérification, de la plus faible à la plus forte :

```bash
# 1. l'ISO est intacte
sha256sum -c SHA256SUMS

# 2. sa composition est celle du manifeste publié — sans Nix, et sans accorder
#    aucune confiance à celui qui a construit l'image : un simple GET par paquet
awk '!/^#/ {print $1}' closure-sri.tsv | while read -r p; do
  h=$(basename "$p")
  curl -s "https://cache.nixos.org/${h%%-*}.narinfo" | sed -n 's/^NarHash: //p'
done
# puis comparer chaque valeur au champ narHash de closure.json

# 3. on peut reconstruire le même système à l'identique
git checkout <tag> && nix build .#minimal
```

Mesure sur l'image 2026.10 : **685 des 732 chemins** sont confirmés à l'identique
par `cache.nixos.org`, **zéro divergence**. Les 47 autres sont dérivés localement
(le système NixOS lui-même, les `/etc` générés, les unités systemd) : ils
n'existent dans aucun cache binaire, et pour eux seule la reconstruction fait foi.

La reproductibilité bit-à-bit de l'ISO n'est **pas affirmée** : deux constructions
identiques doivent produire le même hachage, ce n'est pas encore mesuré. Première
indication favorable : deux constructions successives du manifeste ont donné les
mêmes empreintes (`closure.json` → `79fb15ce…`, `store-paths.txt` → `c3fd0045…`).

## Limites connues

- **Secure Boot : à désactiver.** L'ISO n'est pas signée. C'est le principal
  manque par rapport à Parted Magic, et un chantier à part entière (shim signé,
  enrôlement MOK).
- **Pas d'interface graphique** en v1. Choix assumé : GNOME coûte ~1,1 GiB de
  store pour `nautilus` seul, et le montage automatique des disques est
  précisément ce qu'il ne faut pas en récupération de données.
- **Pas de persistance.** En v1, tout ce qui est installé en session disparaît au
  redémarrage. La persistance est prévue en v2.
- **Comptes sans mot de passe.** Comme tout média live, `root` et `nixos` n'ont
  pas de mot de passe en session. Acceptable physiquement, à ne pas laisser
  traîner branché sur une machine réseau.
- **`aarch64` non testée en CI.** Les runners arm64 gratuits n'exposent pas
  `/dev/kvm` : l'ISO est construite, mais son démarrage se teste à la main.
- **Pas de Clonezilla.** Absent de nixpkgs ; le clonage repose sur `partclone`,
  `fsarchiver` et `ddrescue`, qui couvrent le besoin.

## Feuille de route

- **v0.1 — fait.** Saveur minimale, ISO construite de bout en bout, démarrage
  testé en BIOS et en EFI, manifeste de composition vérifié, garde-fous de taille
  et de boot en CI.
- **v0.2 — en cours.** Il reste la release signée (clé minisign à créer, non
  chiffrée : minisign ne lit pas de mot de passe dans l'environnement) et le test
  de démarrage `aarch64`, à faire à la main.
- **v0.3** — release mensuelle automatique, budget de taille et test de boot
  bloquants.
- **v1.0** — documentation de vérification complète.
- **v2** — persistance, puis éventuellement une saveur graphique.

## Arborescence

```
flake.nix                  entrées et sorties : ISO, tests, garde-fous
modules/base.nix           socle : firmware, noyau, licences, SSH, marqueur de boot
modules/tools.nix          sélection d'outils, capacité vs confort, chiffrée
modules/iso.nix            nom, menu de boot, compression, volume
nix/qemu-run.sh            lancement QEMU : interactif ou test à marqueur
nix/closure-manifest.nix   manifeste de composition (la preuve)
docs/budget.md             mesures de taille et règle du projet
docs/design.md             décisions d'architecture et leurs raisons
```
