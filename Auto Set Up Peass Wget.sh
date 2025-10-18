sol() {
  # valores por defecto
  USE_WINPEAS=0
  IFACE="tun0"   # interfaz por defecto si no se pasa -i
  PORT=4444      # puerto fijo como pediste

  # parseo simple de argumentos: -w/--win y -i/--iface <name>
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -w|--win) USE_WINPEAS=1; shift ;;
      -i|--iface) 
        if [ -z "$2" ]; then
          echo "error: faltó el nombre de la interfaz después de $1" >&2
          return 1
        fi
        IFACE="$2"
        shift 2
        ;;
      --) shift; break ;;
      -*)
        echo "error: opción desconocida: $1" >&2
        return 1
        ;;
      *) break ;;
    esac
  done

  # función para obtener IPv4 de una interfaz dada
  detect_ip_of_iface() {
    iface="$1"
    # preferir ip (linux moderno)
    if command -v ip >/dev/null 2>&1; then
      ip -4 addr show dev "$iface" 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1 && return 0
    fi
    # fallback ifconfig (posible en sistemas antiguos)
    if command -v ifconfig >/dev/null 2>&1; then
      # distintos formatos posibles
      ifconfig "$iface" 2>/dev/null | awk '/inet /{print $2}' | head -n1 && return 0
      ifconfig "$iface" 2>/dev/null | sed -n 's/.inet addr:\([0-9.]\).*/\1/p' | head -n1 && return 0
    fi
    return 1
  }

  # comprobar que la interfaz existe (mejor mensaje si no existe)
  if command -v ip >/dev/null 2>&1; then
    if ! ip link show "$IFACE" >/dev/null 2>&1; then
      echo "error: la interfaz '$IFACE' no existe (según 'ip link')." >&2
      return 1
    fi
  elif command -v ifconfig >/dev/null 2>&1; then
    if ! ifconfig "$IFACE" >/dev/null 2>&1; then
      echo "error: la interfaz '$IFACE' no existe (según 'ifconfig')." >&2
      return 1
    fi
  fi

  HOST=$(detect_ip_of_iface "$IFACE") || {
    echo "error: no se encontró dirección IPv4 en la interfaz '$IFACE'." >&2
    return 1
  }

  # rutas peass
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

  URL="http://${HOST}:${PORT}/${SRC_BASENAME}"

  echo "serviendo desde: $SRC_DIR"
  echo "archivo: $SRC_BASENAME"
  echo "interfaz: $IFACE"
  echo "host: $HOST"
  echo "url: $URL (puerto: $PORT)"

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

  if ! pushd "$SRC_DIR" >/dev/null 2>&1; then
    echo "error: no se pudo acceder a $SRC_DIR"
    return 1
  fi

  _sol_cleanup() {
    if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" >/dev/null 2>&1; then
      kill "$SERVER_PID" >/dev/null 2>&1 || true
      wait "$SERVER_PID" 2>/dev/null || true
    fi
    popd >/dev/null 2>&1 || true
  }
  trap '_sol_cleanup; trap - INT TERM EXIT; return 0' INT TERM EXIT

  # arrancar servidor en background bind a la IP de la interfaz elegida
  if command -v python3 >/dev/null 2>&1; then
    python3 -m http.server "$PORT" --bind "$HOST" >/dev/null 2>&1 &
  else
    python -m http.server "$PORT" --bind "$HOST" >/dev/null 2>&1 &
  fi

  SERVER_PID=$!

  # breve espera para verificar arranque
  sleep 0.2
  if ! kill -0 "$SERVER_PID" >/dev/null 2>&1; then
    echo "error: no se pudo iniciar el servidor en ${HOST}:${PORT} (puerto ocupado o permisos)." >&2
    _sol_cleanup
    return 1
  fi

  echo "Servidor iniciado con PID: $SERVER_PID (bind a $HOST:$PORT)"
  echo "El servidor se cerrará automáticamente en 30 segundos o presione CTRL-C para cerrarlo..."

  sleep 30

  echo "Tiempo completado. Cerrando servidor..."
  _sol_cleanup
}
