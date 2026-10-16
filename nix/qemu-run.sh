#!/usr/bin/env bash
# Boot a Dépannix ISO in QEMU.
#
#   ISO=<path>              path to the ISO (required)
#   MODE=bios|efi           boot firmware (default: bios)
#   QEMU=/path/qemu-...     QEMU binary (default: detected)
#   MACHINE=q35|virt        QEMU machine (default: q35)
#   OVMF_FIRMWARE=...       EFI firmware (required when MODE=efi)
#   MEM=3072  CPUS=2
#   GUI=1                   give the guest a real display (virtio card, monitor
#                           socket, VNC on ./vnc.sock)
#   GUI_COMMAND="..."       type this on the guest's tty1, once it is up
#
# Without MARKER : QEMU runs in the foreground, interactive (`nix run`).
#                  With GUI=1, watch the session with a VNC client on
#                  unix:vnc.sock; the console stays on this terminal.
# With MARKER    : test mode - we wait for the MARKER string on the serial
#                  console, kill QEMU as soon as it appears, and exit non-zero
#                  if TIMEOUT seconds pass without seeing it.
# With MARKER and GUI:
#                  we do not stop at the first marker. A session has to announce
#                  itself on the console afterwards (DEPANNIX_SESSION), and the
#                  screen is captured to session.ppm and session.png, so that
#                  "the session came up" is a fact rather than a claim.
set -uo pipefail

ISO="${ISO:?ISO must point to an image to boot}"
MODE="${MODE:-bios}"
MACHINE="${MACHINE:-q35}"
MEM="${MEM:-3072}"
CPUS="${CPUS:-2}"
MARKER="${MARKER:-}"
TIMEOUT="${TIMEOUT:-900}"
GUI="${GUI:-}"
GUI_COMMAND="${GUI_COMMAND:-}"
# How long to wait before typing at the guest. The autologin shell on tty1 is
# started around multi-user.target, a moment after the readiness marker.
GUI_DELAY="${GUI_DELAY:-20}"

log="serial.log"

QEMU="${QEMU:-}"
if [ -z "$QEMU" ]; then
  for c in qemu-system-x86_64 qemu-system-aarch64; do
    if command -v "$c" >/dev/null 2>&1; then QEMU="$(command -v "$c")"; break; fi
  done
fi
[ -n "$QEMU" ] || { echo "QEMU not found" >&2; exit 2; }

args=(
  -machine "$MACHINE"
  -m "$MEM"
  -smp "$CPUS"
  -no-reboot
  -cdrom "$ISO"
)

if [ -n "$GUI" ]; then
  # A graphical console, and a card the guest's kernel can drive: virtio-gpu
  # provides a DRM device with atomic modesetting, which is what a compositor
  # needs, unlike the default emulated VGA.
  #
  # VNC rather than `-display none`: with no display frontend at all, whether
  # frames are still drawn into the console surface is a per-device
  # implementation detail, and this harness should not depend on one. On a unix
  # socket rather than TCP, because a Nix build sandbox has no network.
  command -v socat >/dev/null 2>&1 || {
    echo "socat is required for GUI mode: it is what drives the QEMU monitor" >&2
    exit 2
  }
  args+=( -vga virtio -monitor "unix:$PWD/monitor.sock,server=on,wait=off" )
  args+=( -vnc "unix:$PWD/vnc.sock" )
  if [ -n "$MARKER" ]; then
    # In test mode nothing reads the terminal, so the console goes to a file.
    args+=( -serial "file:$log" )
  else
    args+=( -serial stdio )
  fi
else
  # Everything to the serial console, which makes the test observable.
  args+=( -nographic )
fi

# KVM changes everything: without it, acceleration is software (TCG) and a full
# boot takes tens of minutes instead of tens of seconds.
if [ -w /dev/kvm ]; then
  args+=( -enable-kvm -cpu host )
  echo "[qemu] KVM enabled" >&2
else
  args+=( -cpu max )
  echo "[qemu] KVM unavailable - software emulation, this will be slow" >&2
fi

case "$MODE" in
  bios) ;;
  efi)
    [ -n "${OVMF_FIRMWARE:-}" ] || { echo "OVMF_FIRMWARE required in efi mode" >&2; exit 2; }
    args+=( -drive "if=pflash,format=raw,readonly=on,file=$OVMF_FIRMWARE" )
    ;;
  *) echo "unknown MODE: $MODE" >&2; exit 2 ;;
esac

if [ -z "$MARKER" ]; then
  exec "$QEMU" "${args[@]}"
fi

: > "$log"
"$QEMU" "${args[@]}" >> "$log" 2>&1 &
qpid=$!

deadline=$(( $(date +%s) + TIMEOUT ))

await() { # await <pattern> : 0 when the pattern reaches the serial log in time
  local pattern="$1"
  while kill -0 "$qpid" 2>/dev/null; do
    if grep -q -- "$pattern" "$log" 2>/dev/null; then return 0; fi
    if [ "$(date +%s)" -ge "$deadline" ]; then return 1; fi
    sleep 5
  done
  # QEMU died on its own: one last look before giving up.
  grep -q -- "$pattern" "$log" 2>/dev/null
}

monitor() { # monitor <command> : one command on the QEMU monitor
  printf '%s\n' "$*" | socat - "UNIX-CONNECT:$PWD/monitor.sock" >/dev/null 2>&1 || true
}

inject() { # inject <text> : type it on the guest's console, then press Enter
  # The set of keys is small and closed on purpose: what the tests type is a
  # command name and its arguments, not shell syntax. The punctuation below is
  # for diagnosing a failure by hand, not for the tests themselves.
  local text="$1" i char key
  for (( i=0; i<${#text}; i++ )); do
    char="${text:i:1}"
    case "$char" in
      " ") key="spc" ;;
      "-") key="minus" ;;
      "_") key="shift-minus" ;;
      "/") key="slash" ;;
      ".") key="dot" ;;
      ";") key="semicolon" ;;
      ":") key="shift-semicolon" ;;
      ",") key="comma" ;;
      "=") key="equal" ;;
      ">") key="shift-dot" ;;
      "<") key="shift-comma" ;;
      "|") key="shift-backslash" ;;
      "'") key="apostrophe" ;;
      "(") key="shift-9" ;;
      ")") key="shift-0" ;;
      *) key="$char" ;;
    esac
    monitor "sendkey $key"
    sleep 0.05
  done
  monitor "sendkey ret"
}

status=1
if await "$MARKER"; then
  echo "[qemu] marker \"$MARKER\" seen" >&2

  if [ -n "$GUI" ]; then
    # The minimal image has no display manager: the session starts because
    # somebody typed the command. So does the test.
    if [ -n "$GUI_COMMAND" ]; then
      echo "[qemu] typing \"$GUI_COMMAND\" on the guest console" >&2
      sleep "$GUI_DELAY"
      inject "$GUI_COMMAND"
    fi

    # Then the session has to report itself. Waiting for the failure line too,
    # rather than only the success one, so a broken session fails the test in a
    # few seconds instead of at the timeout.
    if await 'DEPANNIX_SESSION'; then
      # Let the frame be drawn: a compositor reports itself before it has
      # necessarily painted the whole screen.
      sleep 5
      monitor "screendump $PWD/session.ppm"
      sleep 3
      if [ -f session.ppm ]; then
        if magick session.ppm session.png 2>/dev/null || convert session.ppm session.png 2>/dev/null; then
          echo "[qemu] screen captured to session.ppm and session.png" >&2
        else
          echo "[qemu] warning: captured session.ppm but could not convert it" >&2
        fi
      else
        echo "[qemu] warning: the screendump produced no file" >&2
      fi
      status=0
    else
      echo "[qemu] no session marker within ${TIMEOUT}s" >&2
    fi
  else
    status=0
  fi
fi

kill -TERM "$qpid" 2>/dev/null
for _ in 1 2 3 4 5; do kill -0 "$qpid" 2>/dev/null || break; sleep 1; done
kill -KILL "$qpid" 2>/dev/null
wait "$qpid" 2>/dev/null

if [ "$status" = 0 ]; then
  echo "OK: marker \"$MARKER\" seen on the serial console (mode $MODE${GUI:+, gui})"
  exit 0
fi

echo "FAILURE: marker \"$MARKER\" not seen after ${TIMEOUT}s (mode $MODE)" >&2
echo "--- last 40 lines of $log ---" >&2
tail -40 "$log" >&2
exit 1
