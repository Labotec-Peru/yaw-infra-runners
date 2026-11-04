#!/bin/bash
# API de despliegue de Puyu. Menu cerrado de acciones.
#
# authorized_keys de jenkins:
#   command="sudo -n /usr/local/bin/servicio-init.sh",restrict ssh-ed25519 AAAA...

set -uo pipefail

REPO_URL="git@github.com:Labotec-Peru/puyu-infra-runners.git"
REPO_DIR="/var/lib/puyu/runners"
CACHE="/var/lib/puyu/servicios.yaml"
BIN="/usr/local/bin"
LLAVE_REPO="/root/.ssh/puyu-runners"
FIRMANTES="/etc/puyu/allowed_signers"
IP="${SSH_CLIENT%% *}"

log(){ logger -t servicio-init "ip=$IP $*"; }
morir(){ log "RECHAZADO $*"; echo "ERROR: $*" >&2; exit 1; }

actualizar_bins() {
  install -d -m 700 /var/lib/puyu
  local GITSSH="ssh -i $LLAVE_REPO -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes"

  if [ ! -d "$REPO_DIR/.git" ]; then
    GIT_SSH_COMMAND="$GITSSH" git clone --quiet "$REPO_URL" "$REPO_DIR" \
      || morir "no se pudo clonar el repo"
  else
    GIT_SSH_COMMAND="$GITSSH" git -C "$REPO_DIR" fetch --quiet --tags origin \
      || morir "no se pudo actualizar el repo"
    git -C "$REPO_DIR" reset --hard --quiet origin/main \
      || morir "no se pudo posicionar en main"
  fi

  if [ -f "$FIRMANTES" ]; then
    git -C "$REPO_DIR" -c gpg.ssh.allowedSignersFile="$FIRMANTES" \
        verify-commit HEAD >/dev/null 2>&1 \
      || morir "el commit HEAD no tiene firma valida"
  fi

  local commit; commit=$(git -C "$REPO_DIR" rev-parse --short HEAD)

  for f in puyu-alta puyu-deploy; do
    [ -f "$REPO_DIR/bin/$f" ] || morir "falta bin/$f en el repo"
    python3 -m py_compile "$REPO_DIR/bin/$f" || morir "bin/$f no compila"
    install -m 755 -o root -g root "$REPO_DIR/bin/$f" "$BIN/$f"
  done
  install -m 755 -o root -g root "$REPO_DIR/bin/servicio-init.sh" "$BIN/servicio-init.sh.nuevo"
  mv "$BIN/servicio-init.sh.nuevo" "$BIN/servicio-init.sh"

  log "bins actualizados commit=$commit"
  echo "runners en commit $commit"
}

CMD="${SSH_ORIGINAL_COMMAND:-}"
[[ "$CMD" =~ ^[a-z]+( [a-z0-9][a-z0-9-]{1,48} (dev|prod))?$ ]] \
  || morir "sintaxis: menu | rutas | imagen <servicio> <dev|prod> | estado <servicio> <dev|prod>"

read -r ACCION SERVICIO ENTORNO <<< "$CMD"
log "accion=$ACCION servicio=${SERVICIO:-} entorno=${ENTORNO:-}"

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

  imagen)
    [ -n "${SERVICIO:-}" ] && [ -n "${ENTORNO:-}" ] || morir "uso: imagen <servicio> <dev|prod>"
    [ -s "$CACHE" ] || morir "no hay servicios.yaml aplicado; corre rutas primero"
    actualizar_bins
    PUYU_SERVICIOS="$CACHE" "$BIN/puyu-deploy" desplegar "$SERVICIO" "$ENTORNO"
    ;;

  estado|registro|revertir)
    [ -n "${SERVICIO:-}" ] && [ -n "${ENTORNO:-}" ] || morir "uso: $ACCION <servicio> <dev|prod>"
    [ -s "$CACHE" ] || morir "no hay servicios.yaml aplicado"
    PUYU_SERVICIOS="$CACHE" "$BIN/puyu-deploy" "$ACCION" "$SERVICIO" "$ENTORNO"
    ;;

  menu)
    echo "rutas                          aplica servicios.yaml (por stdin)"
    echo "imagen   <servicio> <entorno>  despliega una imagen (tar por stdin)"
    echo "estado   <servicio> <entorno>  estado del contenedor"
    echo "registro <servicio> <entorno>  ultimas 50 lineas de log"
    echo "revertir <servicio> <entorno>  vuelve a la imagen anterior"
    ;;

  *) morir "accion no permitida: $ACCION" ;;
esac