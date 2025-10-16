# Creates a http server in the peass directory and copies the url with wget to the clipboard for pillaging 
sol() {
  HOST="127.0.0.1"
  USE_WINPEAS=0

  # switch -w for winpeas
  if [ "$1" = "-w" ] || [ "$1" = "--win" ]; then
    USE_WINPEAS=1
  fi

  # peass routes
  LINPEAS_DIR="/usr/share/peass/linpeas"
  LINPEAS_FILE="linpeas.sh"

  WINPEAS_DIR="/usr/share/peass/winpeas"
  WINPEAS_FILE="winPEAS.bat"

  if [ "$USE_WINPEAS" -eq 1 ]; then
    SRC_DIR="$WINPEAS_DIR"
    SRC_BASENAME="$WINPEAS_FILE"
  else
    SRC_DIR="$LINPEAS_DIR"
    SRC_BASENAME="$LINPEAS_FILE"
  fi

  if [ ! -f "${SRC_DIR}/${SRC_BASENAME}" ]; then
    echo "error: no se encontró ${SRC_DIR}/${SRC_BASENAME}"
    return 1
  fi

  # obtener puerto libre (usa python)
  if command -v python3 >/dev/null 2>&1; then
    PORT=$(python3 - <<'PY'
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.bind(("127.0.0.1", 0))
port = s.getsockname()[1]
s.close()
print(port)
PY
)
  elif command -v python >/dev/null 2>&1; then
    PORT=$(python - <<'PY'
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.bind(("127.0.0.1", 0))
port = s.getsockname()[1]
s.close()
print(port)
PY
)
  else
    echo "error: se necesita python3 o python para detectar puerto libre."
    return 1
  fi

  if ! printf "%s" "$PORT" | grep -qE '^[0-9]+$'; then
    echo "error: no se pudo obtener puerto libre."
    return 1
  fi

  URL="http://${HOST}:${PORT}/${SRC_BASENAME}"

  echo "serviendo desde: $SRC_DIR"
  echo "archivo: $SRC_BASENAME"
  echo "url: $URL (puerto: $PORT)"

  # copiar URL al portapapeles (portable: usa printf)
  _copy_url_to_clipboard() {
    u="$1"
    if command -v pbcopy >/dev/null 2>&1; then
      printf '%s' "$u" | pbcopy && echo "url copiada al portapapeles (pbcopy)"
    elif command -v xclip >/dev/null 2>&1; then
      printf '%s' "$u" | xclip -selection clipboard && echo "url copiada al portapapeles (xclip)"
    elif command -v xsel >/dev/null 2>&1; then
      printf '%s' "$u" | xsel --clipboard --input && echo "url copiada al portapapeles (xsel)"
    else
      echo "aviso: no se encontró herramienta de portapapeles; URL impresa arriba"
    fi
  }
  _copy_url_to_clipboard "$URL"

  # cambiar al directorio del archivo y arrancar servidor ligado a localhost
  if ! pushd "$SRC_DIR" >/dev/null 2>&1; then
    echo "error: no se pudo acceder a $SRC_DIR"
    return 1
  fi

  # limpieza: mata servidor y vuelve al dir original
  _sol_cleanup() {
    if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" >/dev/null 2>&1; then
      kill "$SERVER_PID" >/dev/null 2>&1 || true
      wait "$SERVER_PID" 2>/dev/null || true
    fi
    popd >/dev/null 2>&1 || true
  }
  trap '_sol_cleanup; trap - INT TERM EXIT; return 0' INT TERM EXIT

  # arrancar servidor en background en el puerto detectado
  if command -v python3 >/dev/null 2>&1; then
    python3 -m http.server "$PORT" --bind "$HOST" >/dev/null 2>&1 &
  else
    python -m http.server "$PORT" --bind "$HOST" >/dev/null 2>&1 &
  fi
  SERVER_PID=$!
  echo "servidor http iniciado en $HOST:$PORT (pid $SERVER_PID)"
  echo "presiona Ctrl-C o ENTER para detener el servidor."

  # permitir detener con Enter: read en background; al recibir entrada, mata servidor
  ( read -r && kill "$SERVER_PID" 2>/dev/null ) &
  _READ_PID=$!

  # esperar al servidor principal
  wait "$SERVER_PID" 2>/dev/null

  # si llegamos aquí, servidor terminó; matar el read si sigue vivo
  if kill -0 "$_READ_PID" >/dev/null 2>&1; then
    kill "$_READ_PID" 2>/dev/null || true
  fi

  # limpieza final
  _sol_cleanup
  trap - INT TERM EXIT
  return 0
}
