#!/usr/bin/env bash
# Lance une ISO Dépannix dans QEMU.
#
#   ISO=<chemin>            chemin de l'ISO (obligatoire)
#   MODE=bios|efi           firmware de démarrage (défaut : bios)
#   QEMU=/chemin/qemu-...   binaire QEMU (défaut : déduit)
#   MACHINE=q35|virt        machine QEMU (défaut : q35)
#   OVMF_FIRMWARE=...       firmware EFI (requis si MODE=efi)
#   MEM=3072  CPUS=2
#
# Sans MARKER  : QEMU est lancé en avant-plan, interactif (`nix run`).
# Avec MARKER  : mode test — on attend la chaîne MARKER sur la console série,
#                on tue QEMU dès qu'elle apparaît, et on sort en erreur si
#                TIMEOUT secondes s'écoulent sans la voir.
set -uo pipefail

ISO="${ISO:?la variable ISO doit pointer sur une image a demarrer}"
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
[ -n "$QEMU" ] || { echo "QEMU introuvable" >&2; exit 2; }

args=(
  -machine "$MACHINE"
  -m "$MEM"
  -smp "$CPUS"
  -nographic # tout part sur la console série, ce qui rend le test observable
  -no-reboot
  -cdrom "$ISO"
)

# KVM change tout : sans lui l'accélération est logicielle (TCG) et un boot
# complet prend des dizaines de minutes au lieu de quelques dizaines de secondes.
if [ -w /dev/kvm ]; then
  args+=( -enable-kvm -cpu host )
  echo "[qemu] KVM actif" >&2
else
  args+=( -cpu max )
  echo "[qemu] KVM indisponible — émulation logicielle, ce sera lent" >&2
fi

case "$MODE" in
  bios) ;;
  efi)
    [ -n "${OVMF_FIRMWARE:-}" ] || { echo "OVMF_FIRMWARE requis en mode efi" >&2; exit 2; }
    args+=( -drive "if=pflash,format=raw,readonly=on,file=$OVMF_FIRMWARE" )
    ;;
  *) echo "MODE inconnu : $MODE" >&2; exit 2 ;;
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
  echo "OK : marqueur « $MARKER » observé sur la console série (mode $MODE)"
  exit 0
fi

echo "ÉCHEC : marqueur « $MARKER » absent après ${TIMEOUT}s (mode $MODE)" >&2
echo "--- 40 dernières lignes de $log ---" >&2
tail -40 "$log" >&2
exit 1
