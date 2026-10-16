# The desktop image: GNOME on Wayland, with Firefox.
#
# This is the flavour that stops being small, on purpose: a browser is the
# single most useful tool on a machine that will not boot, because it is how you
# read the documentation, and it costs what it costs. Measurements, including
# why XFCE was not chosen instead: docs/design.md.
{ config, lib, pkgs, ... }:

let
  cfg = config.depannix;

  report = pkgs.writeShellApplication {
    name = "depannix-session-report";
    runtimeInputs = with pkgs; [
      coreutils
      glib # gsettings: reads the automount setting as the session sees it
      gnugrep
      wayland-utils
    ];
    text = builtins.readFile ../nix/session-report.sh;
  };
in
{
  config = lib.mkIf (cfg.flavour == "desktop") {
    # GNOME's Wayland session needs the X server infrastructure for XWayland and
    # for GDM, and a GL implementation for the shell itself: without a GPU this
    # falls back to software rendering, which is slow but works.
    services.xserver.enable = true;
    hardware.graphics.enable = true;

    services.desktopManager.gnome.enable = true;
    services.displayManager.gdm.enable = true;

    # A rescue medium has no password to type, and nobody to type it: the
    # session logs itself in, exactly as the nixpkgs graphical installer does.
    services.displayManager.autoLogin.enable = true;
    services.displayManager.autoLogin.user = "nixos";

    # The catalogue ships the package; this is what actually starts it. A
    # desktop session with no sound server fails in ways that look like
    # something else.
    services.pipewire.enable = true;

    fonts.packages = [ pkgs.dejavu_fonts ];

    environment.systemPackages = [ report ];

    # A rescue medium must not touch the disks it is examining. Plugging in a
    # disk and finding it silently mounted, written to, and its journal replayed
    # is the one failure this project cannot afford, and GNOME does it by
    # default: this is the setting that decides the matter.
    services.desktopManager.gnome.extraGSettingsOverrides = ''
      [org.gnome.desktop.media-handling]
      automount=false
      automount-open=false
    '';

    # Says, from inside the session, that it is up and that it is a Wayland one.
    # The CI boot test greps for it: see docs/design.md.
    environment.etc."xdg/autostart/depannix-session-report.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=Dépannix session report
      Comment=Report the running session on the serial console
      Exec=${report}/bin/depannix-session-report
      Terminal=false
      NoDisplay=true
    '';
  };
}
