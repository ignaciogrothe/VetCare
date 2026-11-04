#!/bin/bash
# Datos de usuario de ec2-api (subred publica). Corre una sola vez, como root.
exec > /var/log/userdata.log 2>&1
set -x

# Misma zona horaria que ec2-mysql: la API compara fechas de citas con la hora local
timedatectl set-timezone America/Santiago

export DEBIAN_FRONTEND=noninteractive
APT="apt-get -o DPkg::Lock::Timeout=300 -y"
$APT update
$APT install nginx mysql-client git wget gpg apt-transport-https python3

# --- Dart SDK desde el repositorio oficial de Google ---
wget -qO- https://dl-ssl.google.com/linux/linux_signing_key.pub \
  | gpg --dearmor -o /usr/share/keyrings/dart.gpg
REPO=https://storage.googleapis.com/download.dartlang.org/linux/debian
echo "deb [signed-by=/usr/share/keyrings/dart.gpg arch=amd64] $REPO stable main" \
  > /etc/apt/sources.list.d/dart_stable.list
$APT update
$APT install dart

# --- 1 GB de swap: t3.micro tiene 1 GB de RAM y compilar Dart la necesita ---
fallocate -l 1G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

# --- Carpeta de la API y plantilla del .env ---
mkdir -p /opt/api
cat > /opt/api/.env.ejemplo <<'EOF'
DB_HOST=10.0.21.10
DB_PORT=3306
DB_USER=vet_app
DB_PASSWORD=CambieEstaClave2026
DB_NAME=veterinaria
DB_SSL=true
HOST=127.0.0.1
PORT=8080
JWT_SECRET=reemplace-por-la-salida-de-openssl-rand-hex-32
ADMIN_EMAIL=admin@clinica.cl
ADMIN_CLAVE=admin12345
EOF
chown -R ubuntu:ubuntu /opt/api

# --- Servicio systemd (se activa en la Fase 6, cuando exista el binario) ---
cat > /etc/systemd/system/veterinaria-api.service <<'EOF'
[Unit]
Description=API Veterinaria VetCare (Dart)
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
User=ubuntu
WorkingDirectory=/opt/api
EnvironmentFile=/opt/api/.env
ExecStart=/opt/api/veterinaria_api
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload

# --- nginx: puerto 80 publico -> API en 127.0.0.1:8080 ---
cat > /etc/nginx/sites-available/veterinaria <<'EOF'
server {
    listen 80 default_server;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
EOF
ln -sf /etc/nginx/sites-available/veterinaria /etc/nginx/sites-enabled/veterinaria
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx

echo "USER DATA API TERMINADO"
