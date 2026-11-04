#!/bin/bash
# Instala puyu-alta en un servidor. Uso: ./instalar.sh root@5.189.180.249
set -euo pipefail
DESTINO="${1:?uso: ./instalar.sh <usuario@host>}"

python3 -m py_compile bin/puyu-alta
echo "--- sintaxis OK"

scp -O bin/puyu-alta "$DESTINO":/tmp/puyu-alta.nuevo

ssh "$DESTINO" '
  set -e
  apt-get install -y python3-yaml >/dev/null

  id jenkins >/dev/null 2>&1 || {
    useradd -m -s /bin/bash -c "alta de servicios desde Jenkins" jenkins
    passwd -l jenkins
  }
  install -d -m 700 -o jenkins -g jenkins /home/jenkins/.ssh

  install -m 755 -o root -g root /tmp/puyu-alta.nuevo /usr/local/bin/puyu-alta
  rm -f /tmp/puyu-alta.nuevo
  python3 -m py_compile /usr/local/bin/puyu-alta

  cat > /etc/sudoers.d/jenkins-alta <<SUDO
Defaults:jenkins env_keep += "SSH_CLIENT SSH_CONNECTION"
jenkins ALL=(root) NOPASSWD: /usr/local/bin/puyu-alta
SUDO
  chmod 440 /etc/sudoers.d/jenkins-alta
  visudo -c >/dev/null

  echo "--- comprobaciones:"
  sudo -u jenkins test -w /usr/local/bin/puyu-alta \
    && echo "  MAL: jenkins puede modificar el script" \
    || echo "  ok: jenkins no puede modificar el script"
  echo -n "  reglas de sudo para jenkins (debe ser 1): "
  sudo -u jenkins sudo -n -l 2>/dev/null | grep -c puyu-alta || true
'
echo "--- instalado"
echo
echo "Falta una sola vez, en el servidor:"
echo "  ssh-keygen -t ed25519 -f /root/jenkins-alta -N \"\" -C jenkins-alta"
echo "  echo \"command=\\\"sudo -n /usr/local/bin/puyu-alta\\\",restrict \$(cat /root/jenkins-alta.pub)\" > /home/jenkins/.ssh/authorized_keys"
echo "  chown jenkins:jenkins /home/jenkins/.ssh/authorized_keys && chmod 600 /home/jenkins/.ssh/authorized_keys"
echo "  cat /root/jenkins-alta    # -> credencial puyu-alta en Jenkins"
echo "  shred -u /root/jenkins-alta"