# Budget de taille

Tous les chiffres de ce document sont **mesurés**, pas estimés.

Deux sources, et elles ne se remplacent pas :

| Source | Ce qu'elle mesure | Usage |
|---|---|---|
| Le manifeste de l'ISO (`nix build .#closure-manifest`) | La closure **réelle** du système construit : 732 chemins, hachages compris | **Le budget.** C'est la seule valeur qui décrit l'artefact |
| `nix path-info --store https://cache.nixos.org` sur un paquet isolé | La closure d'un paquet, sans rien construire | Le **classement** des coûts, pour décider quoi embarquer |

```bash
# closure individuelle d'un paquet, sans rien construire
nix eval --raw -f '<nixpkgs>' <paquet>.outPath        # -> /nix/store/...
nix path-info --store https://cache.nixos.org -rs --json --json-format 1 <chemin>
```

Précaution de lecture : une **closure individuelle** compte les dépendances
communes en entier. Additionner plusieurs closures surestime donc toujours le
total. Ces valeurs servent à comparer des outils entre eux, jamais à additionner.

## La closure de l'image (2026.10)

Mesurée sur le manifeste de l'ISO, donc sur l'artefact lui-même.

| Poste | Store | Chemins |
|---|---|---|
| Firmware (11 paquets) | **836,4 MiB** | 11 |
| dont `linux-firmware-20260916-zstd` | 809,5 MiB | 1 |
| Modules du noyau | 145,2 MiB | 1 |
| Copie de nixpkgs (`nixos-26.11…`) | 200,0 MiB | 1 |
| `python3-3.14.7` | 136,6 MiB | 1 |
| `systemd-261.3` | 63,0 MiB | 1 |
| `git-2.55.0` | 56,5 MiB | 1 |
| `vim-9.2.1001` | 43,6 MiB | 1 |
| tout le reste (716 chemins) | ~986 MiB | 716 |
| **Total** | **2467,7 MiB** (2,41 GiB) | **732** |

**Le firmware pèse 34 % du total**, pas 70 %. C'est le premier poste isolé, mais
il ne domine pas la discussion autant qu'on le croyait — voir la correction
ci-dessous. Les 716 autres chemins, qui incluent toute la tuyauterie du système
(systemd, la pile Nix, Python, Perl, git, vim), pèsent à eux seuls plus que le
double du firmware.

## Ce que la mesure réelle a corrigé

La version précédente de ce document annonçait **186 chemins / 2675,6 MiB** avec
un firmware à 70 %. Les deux chiffres étaient faux, et pour deux raisons
distinctes :

- **Le firmware était surévalué.** Le chiffre de 1884 MiB portait sur le paquet
  `linux-firmware` **monolithique**, alors que l'image embarque la variante
  `-zstd`, à 809,5 MiB. Le facteur d'erreur est de 2,3.
- **Le système était sous-évalué.** Les 186 chemins étaient l'union des
  composants *choisis explicitement* (firmware, noyau, outils listés). La
  closure réelle en compte 732 : les 546 autres viennent du profil
  `installation-cd-base` — systemd, les outils Nix, la pile Perl de `git`,
  Python, vim, `nixos-rebuild`.

Le total se trouvait donc par hasard à peu près juste (2675,6 contre 2467,7 MiB,
soit 8 % d'écart) alors que **sa composition était fausse**. C'est le pire cas :
un chiffre qui a l'air bon et qui oriente mal les décisions. La leçon est que la
seule mesure qui vaut est celle de l'artefact, jamais celle d'un modèle de
l'artefact.

## Coût des outils optionnels

Closure individuelle, mesurée sur le cache binaire. Ce sont des postes de
dépannage supplémentaires, à activer en connaissance —
`depannix.optionalTools = [ … ]`.

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
média de récupération coûte à lui seul autant que tout le reste, parce qu'il
embarque la pile Qt. `gparted` et `gsmartcontrol` paient le même écot (interface
graphique) — c'est pourquoi la saveur `minimal` ne les embarque pas et s'en
remet à `parted`, `gptfdisk` et `smartctl`.

## Taille d'ISO mesurée (2026.10)

**1453,2 MiB (1,419 GiB).**

| | |
|---|---|
| octets | 1 523 744 768 |
| MiB / GiB | 1453,2 / 1,419 |
| sha256 | `943614f5cdd5fcd947f8947013e4e1dae5b5cc98338180d1df3559eee0d4728a` |
| compression | squashfs, `zstd -Xcompression-level 19`, 2 processeurs |
| durée de compression | ~14 min sur 2 vCPU |
| rapport store → ISO | 2467,7 MiB → 1453,2 MiB, soit **59 %** |

Repères de contexte :

- SystemRescue 13.02 : 1318 MiB
- ISO NixOS minimale officielle : 1533 MiB
- ISO NixOS graphique (GNOME) officielle : 3574 MiB

Dépannix est à **135 MiB au-dessus** de SystemRescue et **80 MiB sous** l'ISO
NixOS minimale officielle. L'objectif n'est pas de battre SystemRescue en taille :
c'est d'arriver dans la même zone **avec** un moyen d'étendre l'outillage sans
reflasher, et avec une composition publiable. Le surcoût par rapport à
SystemRescue est le firmware redistribuable complet et la copie de nixpkgs.

## Contenu vérifié indépendamment

Le manifeste publie chaque chemin avec son hachage, en base32 **et** en SRI. La
vérification se fait donc par un simple GET, sans Nix et sans accorder aucune
confiance à l'auteur du build :

```bash
awk '!/^#/ {print $1}' closure-sri.tsv | while read -r p; do
  h=$(basename "$p")
  curl -s "https://cache.nixos.org/${h%%-*}.narinfo" | sed -n 's/^NarHash: //p'
done
```

Résultat mesuré sur l'image 2026.10 :

| | |
|---|---|
| chemins au manifeste | 732 |
| hachages **identiques** à cache.nixos.org | **685** |
| absents de tout cache (dérivés localement) | 47 |
| divergences | **0** |

Les 47 chemins non vérifiables ainsi sont le système NixOS lui-même, les fichiers
`/etc` générés et les unités systemd. Pour ceux-là, seule la reconstruction fait
foi — d'où l'intérêt de la stabilité observée : deux constructions successives
ont produit les mêmes empreintes pour `closure.json`
(`79fb15ce…`) et `store-paths.txt` (`c3fd0045…`).

## La règle

> **Aucun outil n'entre dans l'ISO sans son chiffre de closure.**

Non pas par avarice, mais parce qu'un média de dépannage dont on ignore la
composition n'est pas un média de dépannage. Le garde-fou
`checks.size-budget` (1800 MiB) échoue en CI si l'ISO dérive, et ce document doit
être mis à jour en même temps que `modules/tools.nix`.

Corollaire, appris à la dure : le chiffre doit venir de l'**artefact**, pas d'un
modèle de l'artefact. `nix build .#closure-manifest` est là pour ça — c'est lui
qui fait autorité, y compris contre ce document.
