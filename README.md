# yaw-infra-runners

**PRIVADO.** Scripts que viven en los servidores de Puyu y corren como root.

## Flujo

    Jenkins --ssh--> servicio-init.sh   (root; jenkins NO puede modificarlo)
                          |
                          +-- 0. se actualiza a si mismo desde este repo
                          +-- rutas   < servicios.yaml  ->  puyu-alta
                          +-- imagen  < imagen.tar      ->  puyu-deploy

Jenkins elige una opcion de un menu cerrado. No manda comandos ni parametros de
ejecucion: puertos, limites y rutas salen de `servicios.yaml`, que pasa por PR
en `Labotec-Peru/yaw-routes`.

## Menu

| Accion | Entrada | Efecto |
|---|---|---|
| `menu` | — | lista las opciones |
| `rutas` | `servicios.yaml` por stdin | crea `.env` y reconcilia Kong |
| `nginx` | tar (nginx.conf + conf.d) por stdin | valida y aplica la config de nginx con reload atomico |
| `imagen <svc> <ent>` | `.tar` por stdin | carga y levanta el contenedor |
| `estado <svc> <ent>` | — | solo lectura |
| `registro <svc> <ent>` | — | ultimas 50 lineas |
| `revertir <svc> <ent>` | — | vuelve a la imagen `:previo` |

`estado` y `registro` son solo lectura y no reciben parametros. `revertir`
tampoco: re-arranca el contenedor con la config exacta del ultimo deploy
exitoso, guardada por `puyu-deploy` en `/var/lib/yaw/cfg/<contenedor>.json`
(root 600). Si el health check falla en el PRIMER despliegue (sin version
anterior), el contenedor se deja corriendo para inspeccion en vez de
eliminarlo.

La membresia de `servicios.yaml` aplica SOLO a los `back` (tienen ruta Kong
y `.env`). Los `front` no pasan por el registro: se declaran en el nginx del
host, que los alcanza por nombre en `home-net`.

`nginx` recibe un tar con `nginx.conf` + `conf.d/*.conf` y valida antes de
tocar nada: rutas/extensiones permitidas, tamaños, `server_name` bajo
`.yaw-iot.com` sin duplicados, backends con nombre válido de contenedor, y
sintaxis real (`nginx -t` en un contenedor desechable con los certs). Aplica
con respaldo y reload atómico; si el `-t` real falla, restaura el respaldo.

> El sudoers de jenkins debe preservar `SSH_ORIGINAL_COMMAND` (`env_keep`),
> ademas de `SSH_CLIENT` y `SSH_CONNECTION`: sin ella, `sudo` la borra y el
> menu ve el comando vacio. `instalar.sh` ya la incluye.

## Por que los runners corren como root

Un usuario que puede ejecutar Docker **es** root en el host: el socket no tiene
permisos intermedios, y quien lo alcanza monta `/` en un contenedor privilegiado.
Fue el vector de marzo, cuando `jenkins` estaba en el grupo `docker`.

No existe "un usuario que solo toque /home y Docker". La frontera no es el
usuario sino el script inmutable: `jenkins` no tiene privilegios y lo unico que
puede invocar es este menu.

## Autoactualizacion

Antes de cada accion se trae este repo y se reinstalan los binarios, con el
token de solo lectura de la GitHub App (ver abajo). El acceso de ESCRITURA al
repo sigue siendo la frontera: cuida quien puede pushear a main, porque quien
controle el repositorio controla root en el servidor.

## Acceso al repo (GitHub App)

Labotec-Peru deshabilito las deploy keys. El acceso de solo lectura es una
**GitHub App** instalada unicamente en este repo (permission `Contents:
Read`). El token de instalacion lo genera `puyu-token` (JWT RS256 con la
clave privada de la app + API de GitHub) y lo cachea en `/var/lib/yaw/token`
(root 600) hasta 5 minutos antes de expirar. `puyu-git-askpass` se lo entrega
a git: el token **nunca** aparece en la linea de comandos ni en `ps`.

Config en `/etc/yaw/github-app.conf` (root 600):

    APP_ID=123456
    INSTALL_ID=12345678
    PEM=/root/.ssh/yaw-runners-app.pem

## Ajustes sin tocar el codigo (/etc/yaw)

Los falsos positivos del revisor de imagenes se ajustan desde archivos de
config en el servidor — un solo lugar, sin editar binarios:

| Archivo | Controla |
|---|---|
| `/etc/yaw/ips-permitidas.txt` | IPs/redes permitidas en el codigo. Si existe → modo ESTRICTO |
| `/etc/yaw/ioc-exentos.txt` | Exenciones IOC: `ruta \| patron [\| fragmento]`. Sin fragmento exime el patron completo en esa ruta; con fragmento (regex) solo la coincidencia exacta. `ruta/*` aplica a todo el prefijo. Si no existe → defaults internos |

Ambos archivos de ejemplo viven en `etc/` de este repo.

## Validaciones

| Campo | Regla |
|---|---|
| `nombre` | `[a-z0-9][a-z0-9-]{1,48}` |
| `env` | `/home/<x>/<y>/.env`, sin `..`, sin enlaces simbolicos, root, 600, no vacio |
| `http` / `tcp` | entero 1024-65535 |
| `mem` | `\d+[mg]` |
| `cpus` | numerico, maximo 8 |
| `kong_host` | obligatoriamente bajo `.yaw-iot.com` |
| `plugins` | lista blanca de seis |
| imagen | **exactamente una** etiqueta en el tar, igual a la declarada |

El tar se inspecciona leyendo `manifest.json` **sin cargarlo en el demonio**. Eso
impide colar una imagen extra o con otra etiqueta. No cubre que Jenkins produzca
un binario malicioso bajo la etiqueta correcta: para eso hace falta firma.

## El contenedor

`--cap-drop ALL`, `--read-only`, `--user` del YAML, `--pids-limit 512`,
`no-new-privileges`, limites de memoria y CPU, HTTP publicado solo en `127.0.0.1`.
El `/tmp` de los back es un tmpfs `nosuid` pero con `exec` explicito: los
tmpfs de Docker traen `noexec` por defecto y los JVM necesitan extraer ahi
sus librerias nativas (Netty epoll, etc.).

El `0.0.0.0` del puerto TCP es explicito a proposito: `daemon.json` tiene
`"ip": "127.0.0.1"`, asi que un `-p 5010:5010` sin IP publicaria solo en loopback
y los dispositivos no llegarian.

## Registro

    journalctl -t servicio-init -t puyu-alta -t puyu-deploy --since today

## Instalacion

    ./instalar.sh root@173.249.36.100