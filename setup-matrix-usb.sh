#!/usr/bin/env bash
set -euo pipefail

# 1) Variables
DEVICE=/dev/sda
MOUNT=/media/usb
DB_PASS="matrixpass"

# 2) Formatear el USB
sudo umount ${DEVICE}1 2>/dev/null || true
sudo wipefs -a ${DEVICE}
sudo parted ${DEVICE} --script mklabel gpt
sudo parted ${DEVICE} --script mkpart primary ext4 1MiB 100%
sudo mkfs.ext4 -L matrix-usb ${DEVICE}1

# 3) Montar y dar permisos
sudo mkdir -p ${MOUNT}
sudo mount ${DEVICE}1 ${MOUNT}
sudo chown -R $USER:$USER ${MOUNT}

# 4) Instalar Docker & Compose V2
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker <<EOF
sudo apt update
sudo apt install -y docker-compose-plugin
EOF

# 5) Crear estructura de carpetas
cd ${MOUNT}
mkdir -p avahi data/postgres data/synapse

# 6) Definir servicio mDNS (Avahi)
cat > avahi/miserver.service <<'EOF'
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">Matrix Server on %h</name>
  <service>
    <type>_http._tcp</type>
    <port>8080</port>
    <txt-record>path=/</txt-record>
  </service>
</service-group>
EOF

# 7) Crear docker-compose.yml con todas las contraseñas iguales
cat > docker-compose.yml <<EOF
version: '3.8'

services:
  avahi:
    image: alpine:edge
    container_name: avahi
    network_mode: host
    cap_add:
      - NET_ADMIN
    volumes:
      - ./avahi/miserver.service:/etc/avahi/services/miserver.service
    command: >-
      sh -c "apk add --no-cache avahi avahi-dbus dbus && \
             sed -i 's/^#enable-dbus=yes/enable-dbus=yes/' /etc/avahi/avahi-daemon.conf && \
             dbus-daemon --system && \
             avahi-daemon --no-chroot --daemonize"
    restart: unless-stopped

  postgres:
    image: postgres:15-alpine
    container_name: synapse-postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: synapse
      POSTGRES_PASSWORD: "$DB_PASS"
    volumes:
      - ./data/postgres:/var/lib/postgresql/data

  synapse:
    image: matrixdotorg/synapse:latest
    container_name: synapse
    restart: unless-stopped
    depends_on:
      - postgres
    environment:
      SYNAPSE_SERVER_NAME: "miserver.local"
      SYNAPSE_REPORT_STATS: "yes"
      SYNAPSE_DATABASE_NAME: synapse
      SYNAPSE_DATABASE_USER: synapse
      SYNAPSE_DATABASE_PASSWORD: "$DB_PASS"
      SYNAPSE_DATABASE_HOST: postgres
      SYNAPSE_DATABASE_PORT: 5432
    volumes:
      - ./data/synapse:/data
    ports:
      - "8008:8008"

  element-web:
    image: vectorim/element-web:latest
    container_name: element-web
    restart: unless-stopped
    depends_on:
      - synapse
    environment:
      DEFAULT_HS_URL: "http://localhost:8008"
      DEFAULT_IS_URL: "http://localhost:8008"
    ports:
      - "8080:80"
EOF

# 8) Generar homeserver.yaml y claves de Synapse
docker run --rm -it \
  -v "${MOUNT}/data/synapse:/data" \
  -e SYNAPSE_SERVER_NAME=miserver.local \
  -e SYNAPSE_REPORT_STATS=yes \
  matrixdotorg/synapse:latest generate

# 9) Arrancar todo el stack
docker compose up -d

# 10) Inicializar la base de datos Postgres
docker exec -i synapse-postgres psql -U synapse -d postgres <<'EOSQL'
DROP DATABASE IF EXISTS synapse;
CREATE DATABASE synapse
  ENCODING 'UTF8'
  LC_COLLATE='C'
  LC_CTYPE='C'
  TEMPLATE=template0;
EOSQL

# 11) Registrar usuario admin (misma contraseña)
docker exec -it synapse \
  register_new_matrix_user \
  --user admin \
  --password "$DB_PASS" \
  --admin \
  --config /data/homeserver.yaml

echo "✔️  ¡Todo listo! Element Web en http://miserver.local:8080  (admin/$DB_PASS)"
