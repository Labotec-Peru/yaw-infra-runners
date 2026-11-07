#!/bin/bash
# Corre en el servidor como root: crea la llave de Jenkins y la ata al menu.
# Uso local (PowerShell):  Get-Content setup-jenkins.sh -Raw | ssh root@173.249.36.100 'bash -s'
set -euo pipefail

# usuario jenkins sin shell util y con la carpeta .ssh
id jenkins >/dev/null 2>&1 || {
  useradd -m -s /bin/bash -c "despliegue desde Jenkins" jenkins
  passwd -l jenkins
}
install -d -m 700 -o jenkins -g jenkins /home/jenkins/.ssh

# llave de Jenkins (si ya existe se reusa)
if [ ! -f /root/jenkins-alta.pub ]; then
  ssh-keygen -t ed25519 -f /root/jenkins-alta -N "" -C "jenkins-alta" >/dev/null
fi

# forced command: lo unico que puede hacer esta llave es el menu cerrado
echo "command=\"sudo -n /usr/local/bin/servicio-init.sh\",restrict $(cat /root/jenkins-alta.pub)" \
  > /home/jenkins/.ssh/authorized_keys
# root es el dueno: si comprometen al usuario jenkins no puede reescribir su
# propia authorized_keys para quitar el restrict. OJO: sshd la lee como el
# USUARIO jenkins (privsep), no como root: por eso debe quedar LEGIBLE (644).
chown root:root /home/jenkins/.ssh/authorized_keys
chmod 644 /home/jenkins/.ssh/authorized_keys

echo "== authorized_keys de jenkins (debe verse el command= al inicio):"
cat /home/jenkins/.ssh/authorized_keys
echo
echo "== LLAVE PRIVADA de Jenkins (pegarla en Jenkins como credencial 'yaw-alta',"
echo "== tipo SSH Username with private key, usuario: jenkins). Despues: shred -u."
echo "== INICIO LLAVE"
cat /root/jenkins-alta
echo "== FIN LLAVE"
