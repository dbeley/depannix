# Tout ce qui touche au média lui-même (nom, menu de boot, compression).
{ config, lib, pkgs, ... }:

let
  cfg = config.depannix;
in
{
  # Nom affiché dans le menu de boot. Le défaut de nixpkgs ajoute « Installer »,
  # ce qui n'a aucun sens pour un média de dépannage.
  isoImage.prependToMenuLabel = "Dépannix — ";
  isoImage.appendToMenuLabel = lib.mkForce "";
  isoImage.edition = cfg.flavour;

  # Étiquette ISO9660 : 32 caractères maximum.
  isoImage.volumeID = "DEPANNIX_${lib.toUpper cfg.flavour}";

  isoImage.makeBiosBootable = pkgs.stdenv.hostPlatform.isx86_64;
  isoImage.makeEfiBootable = true;
  isoImage.makeUsbBootable = true;

  # zstd plutôt que xz : rapport taille/temps nettement meilleur, et c'est
  # désormais le défaut de nixpkgs. Le niveau est paramétrable pour pouvoir
  # itérer vite en local sans reconstruire une ISO de release.
  isoImage.squashfsCompression = cfg.squashfsCompression;

  # iso-image.nix définit image.baseName sans mkDefault → mkForce requis.
  image.baseName = lib.mkForce
    "depannix-${cfg.flavour}-${cfg.version}-${pkgs.stdenv.hostPlatform.system}";

  # Fichier de version lisible depuis la machine dépannée, sans avoir à
  # remonter à la source : utile pour vérifier ce qu'on a sous la main.
  isoImage.contents = [
    {
      source = pkgs.writeText "depannix-version" "${cfg.version}\n";
      target = "/depannix-version";
    }
  ];
}
