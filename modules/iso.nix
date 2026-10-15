# Everything that concerns the medium itself (name, boot menu, compression).
{ config, lib, pkgs, ... }:

let
  cfg = config.depannix;
in
{
  # Name shown in the boot menu. Both the nixpkgs default ("Installer") and a
  # "Dépannix — " prefix are wrong: the label already begins with the
  # distribution name, so the prefix produced entries reading
  # "Dépannix — Dépannix 26.11.20261011.7fd4004".
  #
  # What the menu was actually missing is the release. It carries the nixpkgs
  # label and the revision, not the CalVer that the file name and
  # /depannix-version use, so a stick in hand could not be identified.
  isoImage.prependToMenuLabel = "";
  isoImage.appendToMenuLabel = lib.mkForce " (release ${cfg.version})";
  isoImage.edition = cfg.flavour;

  # ISO9660 label: 32 characters maximum.
  isoImage.volumeID = "DEPANNIX_${lib.toUpper cfg.flavour}";

  isoImage.makeBiosBootable = pkgs.stdenv.hostPlatform.isx86_64;
  isoImage.makeEfiBootable = true;
  isoImage.makeUsbBootable = true;

  # zstd rather than xz: a clearly better size/time trade-off, and now the
  # nixpkgs default. The level is configurable so we can iterate quickly
  # locally without rebuilding a release ISO.
  isoImage.squashfsCompression = cfg.squashfsCompression;

  # iso-image.nix sets image.baseName without mkDefault → mkForce is required.
  image.baseName = lib.mkForce
    "depannix-${cfg.flavour}-${cfg.version}-${pkgs.stdenv.hostPlatform.system}";

  # Version file readable from the machine being rescued, without having to go
  # back to the source: handy to check what you actually have in hand.
  isoImage.contents = [
    {
      source = pkgs.writeText "depannix-version" "${cfg.version}\n";
      target = "/depannix-version";
    }
  ];
}
