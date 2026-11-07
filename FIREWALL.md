# Firewall — runbook (iptables, sin ufw)

> Estado: **vigente**. Los servidores de Puyu usan **iptables + iptables-persistent**.
> **ufw está prohibido**: ambos paquetes administran iptables y entran en conflicto —
> al instalar `iptables-persistent`, apt desinstala ufw automáticamente y resetea la
> política de INPUT a ACCEPT (incidente real: ver la sección "Incidente: ufw e iptables-persistent").

## Regla de oro

1. Reglas de iptables **se agregan a mano** y se persisten SIEMPRE con `netfilter-persistent save`.
2. Las de Docker no se tocan: el daemon las recrea solo al arrancar.
3. Nada de ufw, firewalld ni paneles — iptables puro.

## Estándar del host (INPUT)

```bash
iptables -F INPUT
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -P INPUT DROP
netfilter-persistent save
```

- 80/443 **no** llevan regla en INPUT: ese tráfico se DNATea a contenedores y viaja
  por FORWARD, donde gobierna `DOCKER-USER`.
- `ss -tulpn | grep -v 127.0.0.1` debe mostrar solo lo esperado (22, 80, 443).

## Puertos hacia contenedores (FORWARD / DOCKER-USER)

Docker instala el candado: `DOCKER-USER` acepta `RELATED,ESTABLISHED` + los puertos
listados (80/443 y los TCP crudos abiertos a mano) y **DROP para el resto** desde `eth0`.
No requiere mantenimiento.

## Abrir un puerto TCP crudo a internet

```bash
# 1. IP del contenedor en home-net (CAMBIA al redeployar: re-verificar siempre)
docker inspect <contenedor> --format '{{(index .NetworkSettings.Networks "home-net").IPAddress}}'

# 2. El par DNAT + RETURN
iptables -t nat -A PREROUTING -i eth0 -p tcp --dport <PUERTO> -j DNAT --to-destination <IP>:<PUERTO>
iptables -I DOCKER-USER 3 -i eth0 -p tcp --dport <PUERTO> -j RETURN

# 3. Persistir SIEMPRE
netfilter-persistent save
```

Cerrar un puerto = borrar el par (`iptables -t nat -D PREROUTING ...` +
`iptables -D DOCKER-USER ...`) + `netfilter-persistent save`.

Puertos públicos actuales: **5010** (tcp-service), **5020** (tcp-service-dev),
**6071** (grifos-core-iot-dev, Wialon).

## Auditoría rápida (cuando dudes)

```bash
iptables -L INPUT -n -v | head           # política DROP + lo/established/22
iptables -L DOCKER-USER -n -v            # 80/443 + puertos públicos → DROP
iptables -t nat -L PREROUTING -n -v      # DNATs públicos
ss -tulpn | grep -vE '127\.0\.0\.1|::1'  # qué escucha de cara a internet
systemctl is-enabled netfilter-persistent # debe decir 'enabled'
grep -n '^\*\|^:INPUT' /etc/iptables/rules.v4
```

### Aclaración: dos `:INPUT` en rules.v4

El archivo tiene **una cadena INPUT por tabla** — ambas normales:

```
*filter  →  :INPUT DROP   [0:0]    ← el firewall del host (la que importa)
*nat     →  :INPUT ACCEPT [0:0]    ← normal: nat usa INPUT para DNAT local
```

No es un error ver las dos líneas. La del `*filter` debe decir **DROP**.

## Incidente: ufw e iptables-persistent

- Instalamos `iptables-persistent` → apt desinstaló ufw y **reseteó INPUT a ACCEPT**
  (el host quedó con default-allow silencioso).
- Detección: `iptables -L INPUT -n` mostró `policy ACCEPT`.
- Fix: el bloque del estándar de arriba + `netfilter-persistent save`.

Regla derivada: **después de cualquier cambio de paquetes de firewall, re-auditar
la política de INPUT**.
