# Dépannix

Environnement de dépannage NixOS, construit en ISO minimale, reproductible et
vérifiable. Un média qu'on peut étendre à la demande sans le reflasher, et dont
on peut publier la composition exacte.

**État : v0.1 — échafaudage.** Aucune release publiée. L'ISO n'a pas encore été
construite de bout en bout : le budget annoncé dans `docs/budget.md` est mesuré,
la taille finale ne l'est pas encore.

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

# 2. sa composition correspond au manifeste publié
nix path-info --json -r <chemin-du-système> | diff - closure.json

# 3. on peut reconstruire le même système à l'identique
git checkout <tag> && nix build .#minimal
```

La reproductibilité bit-à-bit de l'ISO elle-même reste **à vérifier** : un
deuxième build identique doit produire le même hachage. C'est un objectif, pas
une affirmation tant qu'il n'a pas été mesuré.

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

- **v0.1** — échafaudage, saveur minimale, test de boot, manifeste de composition.
- **v0.2** — premier build réel, chiffre de taille définitif, CI verte sur les
  deux architectures, release signée.
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
