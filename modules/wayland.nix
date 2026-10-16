# The minimal image's graphical session: Wayland through labwc, and nothing on
# top of it.
#
# Why labwc, why nothing on top, and what each thing that was left out would
# have cost: docs/design.md, with the measurements in docs/budget.md. The short
# version is that this session has to stay worth less than the tools it exists
# to show.
{ config, lib, pkgs, ... }:

let
  cfg = config.depannix;

  # The session is a script, not a service: `depannix gui` runs it, exactly as
  # an operator would, so what the boot test exercises is the real path.
  session = pkgs.writeShellApplication {
    name = "depannix-session";
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
      grim
      labwc
      swaybg
      wayland-utils
    ];
    text = builtins.readFile ../nix/session-minimal.sh;
  };
in
{
  config = lib.mkIf (cfg.flavour == "minimal") {
    # Provides labwc, the Wayland session bits (portals, polkit, XWayland) and
    # registers the session for a display manager we deliberately do not run.
    programs.labwc.enable = true;

    # `programs.labwc.enable` imports wayland-session.nix, which turns on
    # services.graphical-desktop, which was written for a full desktop: OpenGL,
    # the default font set, the speech dispatcher, a default unit of
    # graphical.target. Measured, that defaults to +826 MiB of image, almost all
    # of it mesa and its LLVM. labwc renders through pixman and foot through
    # shared memory, so none of it is needed here, and each is turned back off
    # with its reason rather than silently inherited.
    hardware.graphics.enable = lib.mkForce false;
    fonts.enableDefaultPackages = lib.mkForce false;
    services.speechd.enable = lib.mkForce false;

    # The same import turns on xdg.portal, and with it a chain that has nothing
    # to do with drawing a window: xdg-desktop-portal-gtk pulls gnome-desktop,
    # gtk4 and gst-plugins-bad, which pull flite, freepats, ffmpeg, x265,
    # fluidsynth. Measured on the closure: 89 paths and 242 MiB of NAR out, 4.9
    # MiB of machinery back in, and 92.4 MiB of ISO - 5.4% of the image.
    #
    # Nothing here uses a portal. No application in this image is GTK: the menu,
    # the terminal and the background are plain Wayland clients, and grim reads
    # the screen through wlr-screencopy. Dropping the stack is not a saving
    # found in a corner, it is the removal of a default that was inherited by
    # accident. The desktop flavour keeps it, and needs it: GNOME's own
    # components and every file chooser in that session go through portals.
    #
    # `mkForce` because the assignment happens inside the module that imports
    # wayland-session.nix, where a plain one would be a definition conflict.
    # Measurements: docs/budget.md.
    xdg.portal.enable = lib.mkForce false;
    xdg.portal.extraPortals = lib.mkForce [ ];

    # A session with no font and no cursor is a black screen with extra steps.
    fonts.packages = [ pkgs.dejavu_fonts ];

    environment.systemPackages = [ session ];

    # The root menu is the interface: right-click on the background. labwc reads
    # it from the system-wide XDG directory, so every account gets it. Every
    # entry here starts a program that works without a GPU driver: this image
    # ships no graphical tool, and says why in docs/design.md.
    environment.etc."xdg/labwc/menu.xml".text = ''
      <?xml version="1.0"?>
      <openbox_menu>
        <menu id="root-menu" label="Dépannix">
          <item label="Terminal (foot)">
            <action name="Execute"><command>foot</command></action>
          </item>
          <item label="Screenshot a region">
            <action name="Execute"><command>grim -g "$(slurp)" /tmp/screenshot.png</command></action>
          </item>
          <item label="Copy the screen to /tmp/screenshot.png">
            <action name="Execute"><command>grim /tmp/screenshot.png</command></action>
          </item>
          <separator />
          <item label="Reconfigure">
            <action name="Reconfigure" />
          </item>
          <item label="Leave the session">
            <action name="Exit" />
          </item>
        </menu>
      </openbox_menu>
    '';

    # Keybindings on top of labwc's built-in set (`<default />`), picked to be
    # reachable with one hand and to cover what the menu offers.
    environment.etc."xdg/labwc/rc.xml".text = ''
      <?xml version="1.0"?>
      <openbox_config xmlns="http://openbox.org/3.4/rc">
        <core>
          <primarySelection>yes</primarySelection>
        </core>
        <keyboard>
          <default />
          <keybind key="W-Return">
            <action name="Execute"><command>foot</command></action>
          </keybind>
          <keybind key="W-p">
            <action name="Execute"><command>grim -g "$(slurp)" /tmp/screenshot.png</command></action>
          </keybind>
          <keybind key="W-l">
            <action name="Execute"><command>swaylock -f</command></action>
          </keybind>
          <keybind key="A-F4">
            <action name="Close" />
          </keybind>
        </keyboard>
      </openbox_config>
    '';
  };
}
