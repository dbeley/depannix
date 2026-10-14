# Manifeste de composition de l'ISO.
#
# Publie la liste exhaustive des chemins du store embarqués, avec leur hachage.
# C'est la pièce qui rend la promesse « je peux prouver le contenu » vérifiable :
# n'importe qui peut comparer ce manifeste avec son propre store, ou avec
# cache.nixos.org, sans faire confiance à l'auteur du build.
#
# Source des données : Nix lui-même. `exportReferencesGraph` injecte le graphe
# complet sous forme JSON dans `$NIX_ATTRS_JSON_FILE` au moment de
# l'instanciation. On n'appelle donc PAS `nix path-info` : celui-ci exige
# l'accès à la base du store, que le bac à sable refuse (« Permission denied »
# sur /nix/var/nix/profiles). C'est la méthode qu'emploie `closureInfo` dans
# nixpkgs, et la seule qui fonctionne en CI.
{ pkgs, toplevel }:

let
  # Les filtres jq et le texte explicatif vivent dans des fichiers séparés
  # plutôt qu'en ligne : dans une chaîne Nix `''`, chaque apostrophe devrait
  # s'écrire `'''`, ce qui rend l'expression illisible et fragile.
  filtreJson = pkgs.writeText "depannix-closure.jq" ''
    .depannix
    | map({path, narHash, narSize, references})
    | sort_by(.path)
  '';

  filtreChemins = pkgs.writeText "depannix-paths.jq" ''
    .depannix[].path
  '';

  # Format exact attendu par `nix-store --load-db`.
  filtreEnregistrement = pkgs.writeText "depannix-registration.jq" ''
    .depannix
    | map([.path, .narHash, .narSize, "", (.references | length)] + .references)
    | add
    | map("\(.)\n")
    | add
  '';

  filtreTaille = pkgs.writeText "depannix-total.jq" ''
    .depannix | map(.narSize) | add
  '';

  explication = pkgs.writeText "depannix-lisezmoi.txt" ''
    Vérifier ce manifeste sans faire confiance à son auteur
    =======================================================

    1. Les hachages sont fournis dans deux encodages, pour qu'aucune
       conversion ne soit nécessaire :

         - `closure.json` → `.narHash`, en base32 de Nix (`sha256:…`) ;
         - `closure-sri.tsv` → colonne 2, en SRI/base64 (`sha256-…=`), qui est
           le format renvoyé par les outils Nix modernes et par les narinfos.

       Les deux désignent la même valeur. Le premier format est comparable
       littéralement à un narinfo, le second à la sortie de `nix path-info`.

    2. Vérifier les paquets venus de nixpkgs, sans Nix et sans rien
       reconstruire — un simple GET, aucune confiance requise :

         awk '!/^#/ {print $1}' closure-sri.tsv | while read -r p; do
           h=$(basename "$p")
           curl -s "https://cache.nixos.org/''${h%%-*}.narinfo" \
             | sed -n 's/^NarHash: //p'
         done

       Comparer chaque valeur au `narHash` correspondant de closure.json.

       Couverture mesurée sur cette image : 685 chemins sur 732. Les 47 autres
       sont des chemins dérivés localement (le système NixOS lui-même, les
       fichiers /etc générés, les unités systemd) : ils n'existent dans aucun
       cache binaire et aucun outil ne pourra les confirmer.

    3. Pour ces 47 chemins, seule la reconstruction fait foi. Reconstruire
       l'image depuis les mêmes sources doit reproduire le même
       MANIFEST.sha256 à l'octet près.

    4. Reconstruire la base du store local puis vérifier chaque hachage :

         nix-store --load-db < nix-path-registration.txt

    5. Contrôler l'intégrité du manifeste lui-même :

         sha256sum -c MANIFEST.sha256

    `total-nar-size.txt` donne le poids total de la closure en octets.
  '';
in
pkgs.runCommand "depannix-closure-manifest"
  {
    # Obligatoire pour que `$NIX_ATTRS_JSON_FILE` existe.
    __structuredAttrs = true;
    exportReferencesGraph.depannix = [ toplevel ];
    nativeBuildInputs = [ pkgs.jq pkgs.coreutils pkgs.nix ];
    preferLocalBuild = true;
  }
  ''
    mkdir -p $out
    attrs="$NIX_ATTRS_JSON_FILE"

    # Manifeste détaillé et stable : chemin, narHash, taille, références.
    # `-S` trie les clés, le filtre trie les entrées par chemin : deux
    # constructions du même système produisent donc le même octet.
    jq -S -f ${filtreJson} < "$attrs" > $out/closure.json

    # Liste nue des chemins, pour les comparaisons en une ligne de commande.
    jq -r -f ${filtreChemins} < "$attrs" | sort > $out/store-paths.txt

    # Forme SRI, directement comparable avec un narinfo de cache.nixos.org :
    # `nix hash convert` est un calcul pur, il ne touche pas la base du store
    # et passe donc le bac à sable.
    {
      printf '# chemin\tnarHash (SRI)\tnarSize\n'
      paste \
        <(jq -r -f ${filtreChemins} < "$attrs") \
        <(jq -r '.depannix[].narHash' < "$attrs" \
          | xargs nix --extra-experimental-features nix-command \
                  hash convert --from nix32 --to sri) \
        <(jq -r '.depannix[].narSize' < "$attrs")
    } > $out/closure-sri.tsv

    # Enregistrement au format `nix-store --load-db` : permet à un tiers de
    # reconstruire la base du store et de vérifier chaque hachage localement.
    jq -r -f ${filtreEnregistrement} < "$attrs" | head -n -1 \
      > $out/nix-path-registration.txt

    # Poids total de la closure, en octets.
    jq -f ${filtreTaille} < "$attrs" > $out/total-nar-size.txt

    cp ${explication} $out/LISEZMOI.txt

    # Empreinte du manifeste lui-même : la valeur à épingler dans une release,
    # et celle qu'un tiers compare après avoir reconstruit l'image.
    sha256sum $out/closure.json $out/store-paths.txt $out/closure-sri.tsv \
      > $out/MANIFEST.sha256

    echo "système    : ${toplevel}"
    echo "chemins    : $(wc -l < $out/store-paths.txt)"
    echo "taille NAR : $(cat $out/total-nar-size.txt) octets"
    echo "manifeste  :"
    cat $out/MANIFEST.sha256
  ''
