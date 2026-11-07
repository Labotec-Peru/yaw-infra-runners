#!/bin/bash
# Instala los runners en un servidor. Uso: ./instalar.sh root@173.249.36.100
set -euo pipefail
DESTINO="${1:?uso: ./instalar.sh <usuario@host>}"

python3 -m py_compile bin/puyu-alta bin/puyu-deploy bin/puyu-revisar bin/puyu-token bin/puyu-nginx
bash -n bin/servicio-init.sh
sh -n bin/puyu-git-askpass
echo "--- sintaxis OK"

scp -O bin/puyu-alta bin/puyu-deploy bin/puyu-revisar bin/puyu-token \
  bin/puyu-nginx bin/puyu-git-askpass bin/servicio-init.sh "$DESTINO":/tmp/

ssh "$DESTINO" '
  set -e
  apt-get install -y python3-yaml git >/dev/null

  install -d -m 700 /var/lib/yaw
  install -d -m 755 /etc/yaw

  id jenkins >/dev/null 2>&1 || {
    useradd -m -s /bin/bash -c "despliegue desde Jenkins" jenkins
    passwd -l jenkins
  }
  install -d -m 700 -o jenkins -g jenkins /home/jenkins/.ssh

  for f in puyu-alta puyu-deploy puyu-revisar puyu-token puyu-nginx puyu-git-askpass servicio-init.sh; do
    install -m 755 -o root -g root "/tmp/$f" "/usr/local/bin/$f"
    rm -f "/tmp/$f"
  done
  python3 -m py_compile /usr/local/bin/puyu-alta /usr/local/bin/puyu-deploy \
    /usr/local/bin/puyu-revisar /usr/local/bin/puyu-token /usr/local/bin/puyu-nginx

  cat > /etc/sudoers.d/jenkins-alta <<SUDO
Defaults:jenkins env_keep += "SSH_CLIENT SSH_CONNECTION SSH_ORIGINAL_COMMAND"
jenkins ALL=(root) NOPASSWD: /usr/local/bin/servicio-init.sh
SUDO
  chmod 440 /etc/sudoers.d/jenkins-alta
  visudo -c >/dev/null

  echo "--- comprobaciones:"
  sudo -u jenkins test -w /usr/local/bin/servicio-init.sh \
    && echo "  MAL: jenkins puede modificar el script" \
    || echo "  ok: jenkins no puede modificar el script"
  echo -n "  reglas de sudo para jenkins (debe ser 1): "
  sudo -u jenkins sudo -n -l 2>/dev/null | grep -c servicio-init || true
'

cat <<'FIN'
--- instalado

Falta, una sola vez en el servidor:

  # 1. GitHub App de solo lectura (la org bloqueo las deploy keys).
  #    Ya subiste el .pem a /root/.ssh/yaw-runners-app.pem; completa los
  #    IDs (pagina de la app en Developer settings, y la URL de Install):
  cat > /etc/yaw/github-app.conf <<CONF
APP_ID=TU_APP_ID
INSTALL_ID=TU_INSTALL_ID
PEM=/root/.ssh/yaw-runners-app.pem
CONF
  chmod 600 /etc/yaw/github-app.conf

  # 1b. (opcional) exenciones del revisor de imagenes (ver README "Ajustes"):
  #     cp etc/ioc-exentos.txt /etc/yaw/ioc-exentos.txt

  # 2. llave de Jenkins, atada al menu
  ssh-keygen -t ed25519 -f /root/jenkins-alta -N "" -C "jenkins-alta"
  echo "command=\"sudo -n /usr/local/bin/servicio-init.sh\",restrict $(cat /root/jenkins-alta.pub)" \
    > /home/jenkins/.ssh/authorized_keys
  # root es el dueno: si comprometen al usuario jenkins no puede reescribir su
  # propia authorized_keys para quitar el restrict. OJO: sshd la lee como el
  # USUARIO jenkins (privsep), no como root: por eso debe quedar LEGIBLE (644).
  chown root:root /home/jenkins/.ssh/authorized_keys
  chmod 644 /home/jenkins/.ssh/authorized_keys
  cat /root/jenkins-alta               # -> credencial puyu-alta en Jenkins
  shred -u /root/jenkins-alta
FIN