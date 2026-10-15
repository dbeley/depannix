#!/usr/bin/env bash
# Boot a Dépannix ISO in QEMU.
#
#   ISO=<path>              path to the ISO (required)
#   MODE=bios|efi           boot firmware (default: bios)
#   QEMU=/path/qemu-...     QEMU binary (default: detected)
#   MACHINE=q35|virt        QEMU machine (default: q35)
#   OVMF_FIRMWARE=...       EFI firmware (required when MODE=efi)
#   MEM=3072  CPUS=2
#
# Without MARKER : QEMU runs in the foreground, interactive (`nix run`).
# With MARKER    : test mode - we wait for the MARKER string on the serial
#                  console, kill QEMU as soon as it appears, and exit non-zero
#                  if TIMEOUT seconds pass without seeing it.
set -uo pipefail

ISO="${ISO:?ISO must point to an image to boot}"
MODE="${MODE:-bios}"
MACHINE="${MACHINE:-q35}"
MEM="${MEM:-3072}"
CPUS="${CPUS:-2}"
MARKER="${MARKER:-}"
TIMEOUT="${TIMEOUT:-900}"

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
  -nographic # everything goes to the serial console, which makes the test observable
  -no-reboot
  -cdrom "$ISO"
)

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

log="serial.log"
: > "$log"
"$QEMU" "${args[@]}" >> "$log" 2>&1 &
qpid=$!

deadline=$(( $(date +%s) + TIMEOUT ))
found=0
while kill -0 "$qpid" 2>/dev/null; do
  if grep -q -- "$MARKER" "$log" 2>/dev/null; then found=1; break; fi
  if [ "$(date +%s)" -ge "$deadline" ]; then break; fi
  sleep 5
done

kill -TERM "$qpid" 2>/dev/null
for _ in 1 2 3 4 5; do kill -0 "$qpid" 2>/dev/null || break; sleep 1; done
kill -KILL "$qpid" 2>/dev/null
wait "$qpid" 2>/dev/null

if [ "$found" = 1 ]; then
  echo "OK: marker \"$MARKER\" seen on the serial console (mode $MODE)"
  exit 0
fi

echo "FAILURE: marker \"$MARKER\" not seen after ${TIMEOUT}s (mode $MODE)" >&2
echo "--- last 40 lines of $log ---" >&2
tail -40 "$log" >&2
exit 1
