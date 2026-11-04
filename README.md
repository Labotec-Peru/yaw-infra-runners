# puyu-infra-runners

**Privado.** Scripts que viven en los servidores de Puyu y se ejecutan como root.

## puyu-alta

Recibe `servicios.yaml` por stdin (lo envia el job de `puyu-routes`) y reconcilia:

- crea `/home/<servicio>/<entorno>/.env` vacio si no existe, en modo 600
- corrige los permisos si estaban mal
- crea o actualiza el servicio y la ruta en Kong con `PUT` (idempotente)
- agrega los plugins declarados que falten

No borra, no despliega contenedores, no ejecuta comandos arbitrarios.

### Por que esta separado de puyu-routes

`puyu-routes` lo descarga Jenkins en cada build. Este repositorio no: el script
se instala a mano y el usuario `jenkins` no puede modificarlo.

### Modelo de confianza

El YAML llega desde Jenkins, asi que la unica defensa son las validaciones:

| Campo | Regla |
|---|---|
| `nombre` | `[a-z0-9][a-z0-9-]{1,48}` |
| `env` | exactamente `/home/<x>/<y>/.env`, sin `..`, sin enlaces simbolicos |
| `http` | entero entre 1024 y 65535 |
| `kong_host` | obligatoriamente bajo `.puyu-iot.com` |
| `plugins` | lista blanca de seis |
| tamano | maximo 256 KB y 100 servicios |

Se valida el YAML **completo** antes de aplicar nada: si una entrada esta mal,
aborta sin haber tocado un solo archivo.

Si alguien toma Jenkins, lo peor que logra es crear archivos `.env` vacios y
registrar rutas en Kong bajo el dominio propio. Todo queda en syslog con el
`sha256` del YAML aplicado:

    journalctl -t puyu-alta

## Instalacion

    ./instalar.sh root@5.189.180.249