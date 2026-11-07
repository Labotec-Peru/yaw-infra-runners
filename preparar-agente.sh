#!/bin/bash
# Corre en la MAQUINA DE JENKINS (root): prepara el contenedor de Jenkins para
# el job de yaw-routes: python3+yaml (validacion del YAML), openssh-client
# (ssh al servidor) y el host key de 173.249.36.100 en known_hosts del usuario
# jenkins (el job usa StrictHostKeyChecking=yes).
#
# Uso local (PowerShell):
#   Get-Content preparar-agente.sh -Raw | ssh jenkins 'bash -s [nombre-contenedor]'
#
# Soporta contenedores Debian (apt-get) y Alpine (apk). Ojo: los paquetes viven
# en el contenedor; si lo recreas (docker run nuevo), vuelve a correr el script.
set -euo pipefail

CONT="${1:-$(docker ps -q -f name=jenkins | head -1)}"
[ -n "$CONT" ] || { echo "ERROR: no encontre el contenedor de Jenkins"; exit 1; }
echo "--- contenedor: $CONT"

if docker exec -u root "$CONT" sh -c 'command -v apt-get >/dev/null' 2>/dev/null; then
  echo "--- distro: debian (apt-get)"
  docker exec -u root "$CONT" apt-get update -qq
  docker exec -u root "$CONT" apt-get install -y -qq python3 python3-yaml openssh-client
elif docker exec -u root "$CONT" sh -c 'command -v apk >/dev/null' 2>/dev/null; then
  echo "--- distro: alpine (apk)"
  docker exec -u root "$CONT" apk add --no-cache python3 py3-yaml openssh-client
else
  echo "ERROR: no encontre apt-get ni apk en el contenedor"
  exit 1
fi

ssh-keyscan 173.249.36.100 > /tmp/yaw-keyscan
docker exec -u root "$CONT" mkdir -p /var/jenkins_home/.ssh
docker cp /tmp/yaw-keyscan "$CONT":/var/jenkins_home/.ssh/known_hosts
docker exec -u root "$CONT" chown -R jenkins:jenkins /var/jenkins_home/.ssh
rm -f /tmp/yaw-keyscan

echo "--- python3 en el agente:"
docker exec "$CONT" python3 --version || true
echo "--- host key del servidor yaw (debe aparecer 173.249.36.100):"
docker exec "$CONT" ssh-keygen -F 173.249.36.100 || true
echo "--- listo"
