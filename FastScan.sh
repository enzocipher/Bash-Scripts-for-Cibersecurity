# fastscan: full TCP sweep -> parse open ports -> scan only detected ports
# Usage: fastscan <IP> [--no-sweep] [--copy]
#   --no-sweep : use an existing 'ports' file instead of doing the full sweep
#   --copy     : copy the detected ports to clipboard (xclip/xsel/pbcopy)
# I recommend to use this in Easy Difficulty Machines only.
fastscan() {
  local TARGET="${1:-}" MODE_SWEEP=1 COPY_CLIP=0
  shift || true
  while [ $# -gt 0 ]; do
    case "$1" in
      --no-sweep) MODE_SWEEP=0; shift ;;
      --copy) COPY_CLIP=1; shift ;;
      *) echo "usage: fastscan <IP> [--no-sweep] [--copy]" >&2; return 2 ;;
    esac
  done

  if [ -z "$TARGET" ]; then
    echo "usage: fastscan <IP> [--no-sweep] [--copy]" >&2
    return 2
  fi

  local PORTS_FILE="ports"
  local TS OUT_FILE PORTS_STR

  TS=$(date +%Y%m%d_%H%M%S)
  OUT_FILE="scan_${TARGET}_${TS}.nmap"

  if [ "$MODE_SWEEP" -eq 1 ]; then
    echo "[*] Running full TCP sweep -> $PORTS_FILE"
    sudo nmap --source-port 53 -T4 --min-rate 3000 -p- -n -Pn "$TARGET" -oG "$PORTS_FILE"
    if [ $? -ne 0 ]; then
      echo "error: nmap discovery failed" >&2
      return 3
    fi
  else
    if [ ! -f "$PORTS_FILE" ]; then
      echo "error: --no-sweep but '$PORTS_FILE' does not exist." >&2
      return 4
    fi
    echo "[*] Using existing $PORTS_FILE"
  fi

  # parse open ports from -oG output (robust for typical nmap grepable output)
  PORTS_STR=$(grep -oP '\d{1,5}(?=/open)' "$PORTS_FILE" 2>/dev/null | sort -n | uniq | paste -sd, - || true)

  if [ -z "$PORTS_STR" ]; then
    echo "error: no open ports found in $PORTS_FILE" >&2
    return 5
  fi

  echo "[*] Detected ports: $PORTS_STR"

  # optional: copy to clipboard
  if [ "$COPY_CLIP" -eq 1 ]; then
    if command -v xclip >/dev/null 2>&1; then
      printf '%s' "$PORTS_STR" | xclip -selection clipboard && echo "[*] ports copied (xclip)"
    elif command -v xsel >/dev/null 2>&1; then
      printf '%s' "$PORTS_STR" | xsel --clipboard --input && echo "[*] ports copied (xsel)"
    elif command -v pbcopy >/dev/null 2>&1; then
      printf '%s' "$PORTS_STR" | pbcopy && echo "[*] ports copied (pbcopy)"
    else
      echo "warning: no clipboard tool found; ports not copied"
    fi
  fi

  echo "[*] Launching detailed scan -> $OUT_FILE"
  sudo nmap --source-port 53 --min-rate 3000 -T4 -p"$PORTS_STR" -n -Pn "$TARGET" -oN "$OUT_FILE"
  local rc=$?
  if [ $rc -ne 0 ]; then
    echo "warning: nmap finished with exit code $rc" >&2
  else
    echo "[+] scan saved to $OUT_FILE"
  fi
  return $rc
}
