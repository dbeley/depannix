# Manifeste de composition de l'ISO.
#
# Publie la liste exhaustive des chemins du store embarqués, avec leur hachage.
# C'est la pièce qui rend la promesse « je peux prouver le contenu » vérifiable :
# n'importe qui peut comparer ce manifeste avec son propre store, ou avec
# cache.nixos.org, sans faire confiance à l'auteur du build.
{ pkgs, toplevel }:

let
  closure = pkgs.closureInfo { rootPaths = [ toplevel ]; };
in
pkgs.runCommand "depannix-closure-manifest"
  {
    nativeBuildInputs = [ pkgs.nix ];
    preferLocalBuild = true;
  }
  ''
    mkdir -p $out

    # Liste des chemins, un par ligne (fournie par closureInfo).
    cp ${closure}/store-paths $out/store-paths.txt

    # Enregistrement nix : permet de réinjecter la base de données du store.
    cp ${closure}/registration $out/nix-path-registration.txt

    # Manifeste détaillé : chemin + narHash + taille, au format JSON.
    # `--store daemon` évite toute tentative de substitution réseau.
    nix path-info --json --json-format 1 -r ${toplevel} > $out/closure.json

    # Empreinte du manifeste lui-même : c'est la valeur à épingler dans une
    # release, et celle qu'un tiers compare après avoir reconstruit l'image.
    sha256sum $out/closure.json $out/store-paths.txt > $out/MANIFEST.sha256

    echo "système    : ${toplevel}"
    echo "chemins    : $(wc -l < $out/store-paths.txt)"
    echo "manifeste  :"
    cat $out/MANIFEST.sha256
  ''
