# Start the minimal image's Wayland session, and say on the serial console
# whether it really started. Called by `depannix gui`; see help/help.txt.
#
# The claim this script makes is not "labwc was executed" but "a Wayland client
# connected to a compositor that has an output". The difference is the whole
# point on a machine whose GPU this kernel does not drive, where the compositor
# exits at once and the screen would otherwise just stay black.
#
# No shebang and no `set` line: pkgs.writeShellApplication supplies both, and
# runs shellcheck over this text at build time.
set -uo pipefail

report() {
  printf '%s\n' "$*"
  # The serial console is where an operator with no screen, and the CI boot
  # test, are actually looking.
  if [ -w /dev/ttyS0 ]; then
    printf '%s\n' "$*" > /dev/ttyS0
  fi
  return 0
}

if [ ! -e /dev/dri/card0 ]; then
  report "DEPANNIX_SESSION failed no-drm-device"
  cat > /tmp/depannix-session-failure.txt <<'EOF'
No /dev/dri/card0 on this machine: no DRM device, so no Wayland session is
possible here. Nothing has been changed, and everything else still works.

Which driver was expected, and what the kernel made of the card:

    lspci -k | grep -A3 -i vga
    dmesg | grep -i -e drm -e "Direct Rendering"
EOF
  # Twice: on stderr, where the session was started from, and on the serial
  # console, which is all an operator on a headless machine has.
  cat /tmp/depannix-session-failure.txt >&2
  if [ -w /dev/ttyS0 ]; then cat /tmp/depannix-session-failure.txt > /dev/ttyS0; fi
  exit 1
fi

export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=labwc
export XDG_SESSION_DESKTOP=labwc
export XCURSOR_SIZE=24

# This image ships no OpenGL driver: mesa alone would cost +826 MiB of ISO, and
# labwc renders through pixman quite well enough for a rescue session. Naming the
# renderer is not a preference here, it is a statement about the image: there is
# no GL driver to fall back to.
#
# `auto` is not enough, and the reason is worth writing down, because it cost a
# build to find. wlroots falls back to its software renderer only when the
# machine has no DRM render node at all. On a machine that has one - and a
# virtual GPU is enough, virtio-gpu exposes renderD128 - it tries GLES2, then
# Vulkan, then gives up and the compositor exits. The `WLR_RENDERER_ALLOW_SOFTWARE`
# variable that used to cover this case no longer exists in wlroots 0.19; the
# current names are `WLR_RENDERER` and `WLR_RENDERER_FORCE_SOFTWARE`.
export WLR_RENDERER=pixman

# labwc reads /etc/xdg/labwc, where the root menu lives: with no bar and no
# launcher, that menu is the only way to start anything with a screen.
runtime="${XDG_RUNTIME_DIR:-}"
if [ -z "$runtime" ] || [ ! -d "$runtime" ]; then
  runtime="/run/user/$(id -u)"
  [ -d "$runtime" ] || runtime="/tmp"
  export XDG_RUNTIME_DIR="$runtime"
fi

labwc >/tmp/labwc-session.log 2>&1 &
compositor=$!

# A socket that exists is not a compositor that answers: a client has to connect
# to it and get a registry back. wayland-info is that client.
connected=0
for _ in $(seq 1 60); do
  if wayland-info >/tmp/wayland-info.txt 2>/dev/null; then
    connected=1
    break
  fi
  if ! kill -0 "$compositor" 2>/dev/null; then
    break
  fi
  sleep 0.5
done

if [ "$connected" != 1 ]; then
  report "DEPANNIX_SESSION failed compositor-unreachable"
  {
    echo "The compositor started but never answered a client, so there is nothing"
    echo "to show and the console is untouched. What it had to work with:"
    echo
    echo "  session:    $(id)"
    echo "  runtime:    $XDG_RUNTIME_DIR (WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-unset})"
    echo "  outputs:    $(find /dev/dri -maxdepth 1 -type c -printf '%f ' 2>/dev/null)"
    echo "  labwc said:"
    tail -20 /tmp/labwc-session.log 2>/dev/null | sed 's/^/    /' || echo "    (nothing)"
    echo
    echo "  wayland-info said:"
    tail -5 /tmp/wayland-info.txt 2>/dev/null | sed 's/^/    /' || echo "    (nothing)"
  } > /tmp/depannix-session-failure.txt
  cat /tmp/depannix-session-failure.txt >&2
  if [ -w /dev/ttyS0 ]; then cat /tmp/depannix-session-failure.txt > /dev/ttyS0; fi
  exit 1
fi

# A compositor with no connected output draws nothing at all, and the operator
# gets a black screen with no explanation. Count the outputs and report them.
outputs="$(grep -c 'wl_output' /tmp/wayland-info.txt || true)"

# A colour rather than black, so that "the session is up" is visible on the
# screen itself, and not only in a log.
swaybg -c '#1a1a2e' >/tmp/swaybg.log 2>&1 &

# A terminal, because that is what this session is for: it is the same TTY you
# left, with fonts, several windows and a mouse. Opening it also means the
# screen shows something a screenshot can tell apart from a blank one.
foot >/tmp/foot.log 2>&1 &

# What this image promises, checked rather than assumed. The root menu and the
# help both offer a screenshot, and this image has just had its portal stack
# removed on the strength of a claim: that grim reads the screen through
# wlr-screencopy and not through a portal. A claim like that is exactly the kind
# that is true the day it is written. One pixel at the origin, so the probe
# exercises the whole path and writes nothing worth keeping.
screenshot=no
for _ in $(seq 1 20); do
  if grim -g '0,0 1x1' /tmp/depannix-screenshot-probe.ppm 2>/tmp/grim.log \
    && [ -s /tmp/depannix-screenshot-probe.ppm ]; then
    screenshot=yes
    break
  fi
  if ! kill -0 "$compositor" 2>/dev/null; then
    break
  fi
  sleep 0.5
done

if [ "$screenshot" != yes ]; then
  {
    echo "The session is up, but it cannot capture the screen. grim said:"
    tail -5 /tmp/grim.log 2>/dev/null | sed 's/^/    /' || echo "    (nothing)"
  } > /tmp/depannix-screenshot-failure.txt
  cat /tmp/depannix-screenshot-failure.txt >&2
  if [ -w /dev/ttyS0 ]; then cat /tmp/depannix-screenshot-failure.txt > /dev/ttyS0; fi
fi

report "DEPANNIX_SESSION type=wayland session=labwc outputs=$outputs screenshot=$screenshot"

wait "$compositor"
report "DEPANNIX_SESSION ended session=labwc"
