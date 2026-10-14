# Budget de taille

Tous les chiffres de ce document sont **mesurés**, pas estimés. Méthode : on
interroge le cache binaire officiel, qui connaît la taille de chaque chemin du
store, sans rien télécharger ni construire.

```bash
# closure d'un paquet, en octets, sans rien construire
nix eval --raw -f '<nixpkgs>' <paquet>.outPath        # -> /nix/store/...
nix path-info --store https://cache.nixos.org -rs --json --json-format 1 <chemin>
```

Deux précautions de lecture :

- une **closure individuelle** compte les dépendances communes en entier :
  additionner plusieurs closures surestime le total. Ces valeurs servent au
  **classement**, pas au budget.
- le budget exact, c'est l'**union dédoublonnée** de tous les chemins du store
  embarqués. C'est le chiffre de la section « Socle ».

## Socle `minimal` (2026.10)

| Poste | Store | Chemins |
|---|---|---|
| `linux-firmware` (redistribuable) | **1883,6 MiB** | 1 |
| noyau | 22,0 MiB | 1 |
| modules du noyau | 145,2 MiB | 1 |
| 51 outils (cœur + `zfs` + `fzf`/`ripgrep`/`fd`) | ~625 MiB | |
| **Total union** | **2675,6 MiB** (2,61 GiB) | 186 |

**Le firmware pèse 70 % du socle.** C'est le seul levier qui compte vraiment :
les 51 outils réunis coûtent moins de 625 MiB. Toute discussion sur « quel outil
ajouter » est donc marginale à côté de la question du firmware.

## Coût des outils optionnels

Closure individuelle. Ce sont des postes de dépannage supplémentaires, à activer
en connaissance — `depannix.optionalTools = [ … ]`.

| Outil | Store | Chemins |
|---|---|---|
| `fd` | 50,9 MiB | 7 |
| `fzf` | 50,1 MiB | 11 |
| `ripgrep` | 55,7 MiB | 8 |
| `eza` | 62,4 MiB | 13 |
| `bat` | 72,5 MiB | 16 |
| `hwinfo` | 135,3 MiB | 27 |
| `inxi` | 140,0 MiB | 35 |
| `neovim` | 261,7 MiB | 115 |
| `fish` | 309,4 MiB | 45 |
| `gsmartcontrol` | 317,2 MiB | 112 |
| `gparted` | 385,1 MiB | 132 |
| `phoronix-test-suite` | 606,0 MiB | 139 |
| `guymager` | 2539,6 MiB | 259 |

`guymager` (2,5 GiB de closure) illustre le piège : un outil « évident » pour un
média de récupération coûte à lui seul autant que tout le reste du socle, parce
qu'il embarque la pile Qt. `gparted` et `gsmartcontrol` paient le même écot
(interface graphique) — c'est pourquoi la saveur `minimal` ne les embarque pas et
s'en remet à `parted`, `gptfdisk` et `smartctl`.

## Taille d'ISO attendue

**~1,3 à 1,5 GiB**, à confirmer au premier build réel — c'est le seul chiffre de
ce document qui n'est pas mesuré, parce qu'il dépend de mksquashfs.

Repères de contexte :

- SystemRescue 13.02 : 1318 MiB
- ISO NixOS minimale officielle : 1533 MiB (noyau + firmware + la copie de
  nixpkgs + les outils d'installation)
- ISO NixOS graphique (GNOME) officielle : 3574 MiB

L'objectif n'est donc pas de battre SystemRescue en taille : c'est d'arriver dans
la même zone **avec** un moyen d'étendre l'outillage sans reflasher, et avec une
composition publiable.

## La règle

> **Aucun outil n'entre dans l'ISO sans son chiffre de closure.**

Non pas par avarice, mais parce qu'un média de dépannage dont on ignore la
composition n'est pas un média de dépannage. Le garde-fou `checks.size-budget`
(1800 MiB) échoue en CI si l'ISO dérive, et `docs/budget.md` doit être mis à jour
en même temps que `modules/tools.nix`.
