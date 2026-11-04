#!/bin/bash
# Instala los runners en un servidor. Uso: ./instalar.sh root@5.189.180.249
set -euo pipefail
DESTINO="${1:?uso: ./instalar.sh <usuario@host>}"

python3 -m py_compile bin/puyu-alta bin/puyu-deploy
bash -n bin/servicio-init.sh
echo "--- sintaxis OK"

scp -O bin/puyu-alta bin/puyu-deploy bin/servicio-init.sh "$DESTINO":/tmp/

ssh "$DESTINO" '
  set -e
  apt-get install -y python3-yaml git >/dev/null

  install -d -m 700 /var/lib/puyu
  install -d -m 755 /etc/puyu

  id jenkins >/dev/null 2>&1 || {
    useradd -m -s /bin/bash -c "despliegue desde Jenkins" jenkins
    passwd -l jenkins
  }
  install -d -m 700 -o jenkins -g jenkins /home/jenkins/.ssh

  for f in puyu-alta puyu-deploy servicio-init.sh; do
    install -m 755 -o root -g root "/tmp/$f" "/usr/local/bin/$f"
    rm -f "/tmp/$f"
  done
  python3 -m py_compile /usr/local/bin/puyu-alta /usr/local/bin/puyu-deploy

  cat > /etc/sudoers.d/jenkins-alta <<SUDO
Defaults:jenkins env_keep += "SSH_CLIENT SSH_CONNECTION"
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

  # 1. llave de solo lectura del repo privado (deploy key en GitHub, SIN escritura)
  ssh-keygen -t ed25519 -f /root/.ssh/puyu-runners -N "" -C "puyu-runners-readonly"
  cat /root/.ssh/puyu-runners.pub      # -> Settings > Deploy keys del repo
  ssh-keyscan github.com >> /root/.ssh/known_hosts

  # 2. firmantes autorizados de los commits
  echo "gabriel@labotec ssh-ed25519 AAAA..." > /etc/puyu/allowed_signers

  # 3. llave de Jenkins, atada al menu
  ssh-keygen -t ed25519 -f /root/jenkins-alta -N "" -C "jenkins-alta"
  echo "command=\"sudo -n /usr/local/bin/servicio-init.sh\",restrict $(cat /root/jenkins-alta.pub)" \
    > /home/jenkins/.ssh/authorized_keys
  chown jenkins:jenkins /home/jenkins/.ssh/authorized_keys
  chmod 600 /home/jenkins/.ssh/authorized_keys
  cat /root/jenkins-alta               # -> credencial puyu-alta en Jenkins
  shred -u /root/jenkins-alta
FIN