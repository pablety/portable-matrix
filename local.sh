#!/usr/bin/env bash
set -euo pipefail

# 1) Variables
# Directorio de instalación en tu disco local
INSTALL_DIR=/opt/matrix
DB_PASS="matrixpass"

# 2) Crear y preparar el directorio de instalación
sudo mkdir -p "${INSTALL_DIR}"
sudo chown -R "$USER:$USER" "${INSTALL_DIR}"
cd "${INSTALL_DIR}"

# 3) Instalar Docker & Compose V2
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker "$USER"
# Necesitas reiniciar la sesión o activar el nuevo grupo docker:
newgrp docker <<EOF
sudo apt update
sudo apt install -y docker-compose-plugin
EOF

# 4) Crear estructura de carpetas
mkdir -p avahi data/postgres data/synapse

# 5) Definir servicio mDNS (Avahi)
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

# 6) Crear docker-compose.yml
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
      POSTGRES_PASSWORD: "${DB_PASS}"
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
      SYNAPSE_DATABASE_PASSWORD: "${DB_PASS}"
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

# 7) Generar homeserver.yaml y claves de Synapse
docker run --rm -it \
  -v "${INSTALL_DIR}/data/synapse:/data" \
  -e SYNAPSE_SERVER_NAME=miserver.local \
  -e SYNAPSE_REPORT_STATS=yes \
  matrixdotorg/synapse:latest generate

# 8) Arrancar todo el stack
docker compose up -d

# 9) Inicializar la base de datos Postgres
docker exec -i synapse-postgres psql -U synapse -d postgres <<'EOSQL'
DROP DATABASE IF EXISTS synapse;
CREATE DATABASE synapse
  ENCODING 'UTF8'
  LC_COLLATE='C'
  LC_CTYPE='C'
  TEMPLATE=template0;
EOSQL

# 10) Registrar usuario admin (misma contraseña)
docker exec -it synapse \
  register_new_matrix_user \
  --user admin \
  --password "${DB_PASS}" \
  --admin \
  --config /data/homeserver.yaml

echo "✔️  ¡Todo listo! Element Web en http://miserver.local:8080  (admin/${DB_PASS})"
