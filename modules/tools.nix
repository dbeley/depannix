# Tool selection: the wiring, and the guard.
#
# The list itself lives in nix/tool-catalog.nix so that the image, the discovery
# command and the documentation all read one source. This module turns it into
# packages, and refuses to evaluate if an entry is incomplete.
#
# The order below is the order the packages are wired in, kept identical to the
# hand-written list it replaced. That is what makes a catalogue change provably
# inert: the ISO derivation does not move.
{ config, lib, pkgs, ... }:

let
  inherit (lib)
    mkOption
    types
    ;

  catalog = import ../nix/tool-catalog.nix { inherit pkgs; };

  optionalNames = map (e: e.name) catalog.optional;

  flavoursOf = catalog.flavoursOf;

  # Exactly what ships, so the guard covers exactly that. The flavour decides
  # which catalogue entries become packages; a flavour name with a typo in it
  # would silently drop tools from the image, hence the assertion below.
  inFlavour = builtins.filter (e: builtins.elem config.depannix.flavour (flavoursOf e));

  shippedCore = inFlavour catalog.core;

  # Optional tools are deliberately NOT filtered by flavour: enabling one is an
  # explicit request, and dropping it quietly because it belongs to the other
  # image would be the kind of quiet lie this catalogue exists to prevent.
  shippedOptional = builtins.filter (e: lib.elem e.name config.depannix.optionalTools) catalog.optional;

  unknownFlavours = builtins.filter
    (e: builtins.any (f: !(lib.elem f catalog.knownFlavours)) (flavoursOf e))
    (catalog.core ++ catalog.optional);

  unknownNames = builtins.filter (e: !(builtins.hasAttr e.name pkgs)) (catalog.core ++ catalog.optional);
  missingMetadata = builtins.filter (e: e.category == "" || e.gesture == "") (catalog.core ++ shippedOptional);
  missingFigures = builtins.filter (e: !(e ? figure)) shippedOptional;
  unknownCategories = builtins.filter (e: !(lib.elem e.category catalog.categoryOrder)) (catalog.core ++ catalog.optional);

  names = es: lib.concatStringsSep ", " (map (e: e.name) es);
in
{
  options.depannix.optionalTools = mkOption {
    type = types.listOf (types.enum optionalNames);
    default = [
      "fzf"
      "ripgrep"
      "fd"
    ];
    description = ''
      Convenience tools that are enabled. By default only three, weighing
      ~157 MiB together (individual closures): even comfort has a price.
      Enabling `neovim`, `gnome-disk-utility` or `guymager` costs hundreds of
      MiB; the CI size guard will flag it. Measurements: docs/budget.md.
    '';
  };

  config = {
    # The rule was "no tool enters the ISO without its closure figure". It is now
    # mechanical, and it covers the other half too: no tool without a gesture
    # either, because a catalogue that silently omits one is a catalogue that
    # lies. docs/discovery.md is what the catalogue is for.
    assertions = [
      {
        assertion = unknownNames == [ ];
        message = "tool catalogue names packages nixpkgs does not have: ${names unknownNames}";
      }
      {
        assertion = missingMetadata == [ ];
        message = "tool catalogue entries with no category or no gesture: ${names missingMetadata}";
      }
      {
        assertion = missingFigures == [ ];
        message = "optional tools enabled with no measured figure: ${names missingFigures}";
      }
      {
        # A category nobody listed would silently drop the tool from the
        # generated catalogue: the medium would lie by omission.
        assertion = unknownCategories == [ ];
        message = "tool catalogue entries whose category is not in categoryOrder, so they would vanish from the catalogue: ${names unknownCategories}";
      }
      {
        assertion = unknownFlavours == [ ];
        message = "tool catalogue entries naming a flavour that does not exist, so they would ship in no image at all: ${names unknownFlavours}";
      }
    ];

    environment.systemPackages =
      map (e: pkgs.${e.name}) shippedCore
      ++ lib.optionals config.depannix.enableZfs [ pkgs.zfs ]
      ++ map (n: pkgs.${n}) config.depannix.optionalTools
      ++ config.depannix.extraTools;
  };
}
