#!/bin/bash
# API de despliegue de Puyu. Menu cerrado de acciones.
#
# Es el UNICO ejecutable que el usuario jenkins puede invocar, y no puede
# modificarlo (root:root 755). authorized_keys de jenkins:
#
#   command="sudo -n /usr/local/bin/servicio-init.sh",restrict ssh-ed25519 AAAA...
#
# /etc/sudoers.d/jenkins-alta DEBE preservar SSH_ORIGINAL_COMMAND:
#   Defaults:jenkins env_keep += "SSH_CLIENT SSH_CONNECTION SSH_ORIGINAL_COMMAND"
#   jenkins ALL=(root) NOPASSWD: /usr/local/bin/servicio-init.sh
#
# Acciones validas: menu | rutas | nginx | imagen <servicio> <dev|prod>
# [clave=valor ...] | estado | registro | revertir. Aqui solo se valida la
# FORMA del comando; los pares clave=valor los valida puyu-deploy contra su
# lista blanca.

set -uo pipefail

REPO_URL="https://github.com/Labotec-Peru/puyu-infra-runners.git"
REPO_DIR="/var/lib/puyu/runners"
CACHE="/var/lib/puyu/servicios.yaml"
BIN="/usr/local/bin"
IP="${SSH_CLIENT%% *}"

log(){ logger -t servicio-init "ip=$IP $*"; }
morir(){ log "RECHAZADO $*"; echo "ERROR: $*" >&2; exit 1; }

# Auto-actualiza este repo desde origin/main (token de la GitHub App via
# puyu-git-askpass: nunca viaja en la linea de comandos) y reinstala los
# binarios con verificacion de sintaxis.
actualizar_bins() {
  install -d -m 700 /var/lib/puyu

  export GIT_ASKPASS="$BIN/puyu-git-askpass"
  export GIT_TERMINAL_PROMPT=0

  if [ ! -d "$REPO_DIR/.git" ]; then
    git clone --quiet "$REPO_URL" "$REPO_DIR" \
      || morir "no se pudo clonar el repo (revisa /etc/puyu/github-app.conf)"
  else
    git -C "$REPO_DIR" fetch --quiet --tags origin \
      || morir "no se pudo actualizar el repo"
  fi

  git -C "$REPO_DIR" reset --hard --quiet origin/main \
    || morir "no se pudo posicionar en main"

  local commit; commit=$(git -C "$REPO_DIR" rev-parse --short HEAD)

  for f in puyu-alta puyu-deploy puyu-revisar puyu-token puyu-nginx; do
    [ -f "$REPO_DIR/bin/$f" ] || morir "falta bin/$f en el repo"
    python3 -m py_compile "$REPO_DIR/bin/$f" || morir "bin/$f no compila"
    install -m 755 -o root -g root "$REPO_DIR/bin/$f" "$BIN/$f"
  done
  for f in puyu-git-askpass; do
    [ -f "$REPO_DIR/bin/$f" ] || morir "falta bin/$f en el repo"
    sh -n "$REPO_DIR/bin/$f" || morir "bin/$f no compila"
    install -m 755 -o root -g root "$REPO_DIR/bin/$f" "$BIN/$f"
  done
  install -m 755 -o root -g root "$REPO_DIR/bin/servicio-init.sh" "$BIN/servicio-init.sh.nuevo"
  mv "$BIN/servicio-init.sh.nuevo" "$BIN/servicio-init.sh"

  log "bins actualizados commit=$commit"
  echo "runners en commit $commit"
}

CMD="${SSH_ORIGINAL_COMMAND:-}"
[ -n "$CMD" ] || morir "comando vacio. Si viene por sudo, revisa que \
/etc/sudoers.d/jenkins-alta tenga SSH_ORIGINAL_COMMAND en env_keep"

[[ "$CMD" =~ ^[a-z]+( [a-z0-9][a-z0-9-]{1,48} (dev|prod)( [a-z_]{2,16}=[-A-Za-z0-9=:._/,%+]{1,256})*)?$ ]] \
  || morir "sintaxis: menu | rutas | imagen <servicio> <dev|prod> [clave=valor ...]"

read -r -a PARTES <<< "$CMD"
ACCION="${PARTES[0]}"
SERVICIO="${PARTES[1]:-}"
ENTORNO="${PARTES[2]:-}"
EXTRA=("${PARTES[@]:3}")

[ "${#EXTRA[@]}" -le 16 ] || morir "demasiados parametros: ${#EXTRA[@]}"

log "accion=$ACCION servicio=${SERVICIO:-} entorno=${ENTORNO:-} extra=${EXTRA[*]+${EXTRA[*]}}"

case "$ACCION" in

  rutas)
    actualizar_bins
    umask 077
    cat > "$CACHE.nuevo" || morir "no se recibio servicios.yaml"
    [ -s "$CACHE.nuevo" ] || { rm -f "$CACHE.nuevo"; morir "servicios.yaml vacio"; }
    "$BIN/puyu-alta" < "$CACHE.nuevo" || { rm -f "$CACHE.nuevo"; exit 1; }
    mv "$CACHE.nuevo" "$CACHE"
    chmod 600 "$CACHE"
    ;;

  nginx)
    actualizar_bins
    "$BIN/puyu-nginx"
    ;;

  imagen)
    [ -n "${SERVICIO:-}" ] && [ -n "${ENTORNO:-}" ] \
      || morir "uso: imagen <servicio> <dev|prod> [clave=valor ...]"
    [ -s "$CACHE" ] || morir "no hay servicios.yaml aplicado; corre rutas primero"
    actualizar_bins
    PUYU_SERVICIOS="$CACHE" "$BIN/puyu-deploy" desplegar "$SERVICIO" "$ENTORNO" \
      "${EXTRA[@]+${EXTRA[@]}}"
    ;;

  estado|registro|revertir)
    [ -n "${SERVICIO:-}" ] && [ -n "${ENTORNO:-}" ] \
      || morir "uso: $ACCION <servicio> <dev|prod>"
    [ -s "$CACHE" ] || morir "no hay servicios.yaml aplicado"
    actualizar_bins
    PUYU_SERVICIOS="$CACHE" "$BIN/puyu-deploy" "$ACCION" "$SERVICIO" "$ENTORNO" \
      "${EXTRA[@]+${EXTRA[@]}}"
    ;;

  menu)
    echo "rutas                                     aplica servicios.yaml (por stdin)"
    echo "nginx                                     valida y aplica la config de nginx (tar por stdin)"
    echo "imagen   <servicio> <entorno> [k=v ...]   despliega una imagen (tar por stdin)"
    echo "estado   <servicio> <entorno>             estado del contenedor"
    echo "registro <servicio> <entorno>             ultimas 50 lineas de log"
    echo "revertir <servicio> <entorno>             vuelve a la imagen anterior"
    echo
    echo "parametros que acepta 'imagen':"
    echo "  tipo=back|front   puertos=N[:N][,N[:N]...]   env=/home/<svc>/<entorno>/.env"
    echo "  mem=2g   reserva=512m   cpus=2   pids=512   java_opts=-Xmx1g,-Xms512m"
    echo "  salud=/actuator/health   reintentos=45   conservar=3"
    echo
    echo "todos los puertos se publican en 127.0.0.1. Un puerto publico se"
    echo "abre a mano en el servidor, nunca desde el pipeline."
    echo
    echo "toda imagen pasa por puyu-revisar antes del docker load."
    ;;

  # Accion desconocida: puede ser una accion NUEVA del repo. Auto-actualiza y
  # reintenta UNA vez con el binario recien instalado; si sigue sin existir,
  # rechaza.
  *)
    if [ "${PUYU_REINTENTO:-0}" = "0" ]; then
      actualizar_bins
      PUYU_REINTENTO=1 exec "$BIN/servicio-init.sh"
    fi
    morir "accion no permitida: $ACCION"
    ;;
esac
