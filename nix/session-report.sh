# Report, on the serial console, that a graphical session is up and that it is a
# Wayland one. Run as an XDG autostart program of the desktop image's session,
# so it inherits the session's own environment: XDG_SESSION_TYPE and
# WAYLAND_DISPLAY here are the session's, not ours. That is what makes this
# evidence rather than a self-declaration.
#
# The CI boot test greps for the line it prints.
#
# No shebang and no `set` line: pkgs.writeShellApplication supplies both, and
# runs shellcheck over this text at build time.
set -uo pipefail

# Let the shell finish drawing before announcing that it has.
sleep 8

report() {
  printf '%s\n' "$*"
  if [ -w /dev/ttyS0 ]; then
    printf '%s\n' "$*" > /dev/ttyS0
  fi
  return 0
}

# The same claim as in the minimal image: a client that connects proves the
# compositor answers, where a running process proves only that it started.
if wayland-info >/dev/null 2>&1; then
  outputs="$(wayland-info 2>/dev/null | grep -c 'wl_output' || true)"

  # The one promise this image makes about the disks, read here rather than
  # declared. GNOME mounts, writes to and replays the journal of any disk that
  # appears, and a rescue medium cannot afford that; the setting that turns it
  # off is asserted by the boot test, from inside the session, where it applies.
  # `gsettings` reads it as the session's user sees it, which is the only reading
  # that means anything.
  automount="$(gsettings get org.gnome.desktop.media-handling automount 2>/dev/null || echo unknown)"

  report "DEPANNIX_SESSION type=${XDG_SESSION_TYPE:-unknown} session=${XDG_CURRENT_DESKTOP:-unknown} display=${WAYLAND_DISPLAY:-none} outputs=$outputs automount=$automount"
else
  report "DEPANNIX_SESSION failed compositor-unreachable session=${XDG_CURRENT_DESKTOP:-unknown}"
  exit 1
fi
