{
  imports = [
    ./base.nix
    ./tools.nix
    ./iso.nix
    ./discovery.nix
    # The two graphical flavours. Each one is inert unless its flavour is the
    # one being built, so importing both costs nothing and keeps the choice in
    # one readable place.
    ./wayland.nix
    ./desktop.nix
  ];
}
