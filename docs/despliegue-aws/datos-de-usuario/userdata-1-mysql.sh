#!/bin/bash
# Datos de usuario de ec2-mysql (subred privada). Corre una sola vez, como root.
exec > /var/log/userdata.log 2>&1
set -x

# Misma zona horaria que ec2-api: la API compara fechas de citas con la hora local
timedatectl set-timezone America/Santiago

export DEBIAN_FRONTEND=noninteractive
APT="apt-get -o DPkg::Lock::Timeout=300 -y"
$APT update
$APT install mysql-server
systemctl enable --now mysql

# Script de preparacion: se ejecuta a mano en la Fase 4, despues de leerlo
cat > /root/preparar-base.sh <<'EOF'
#!/bin/bash
set -e
CLAVE='CambieEstaClave2026'     # la misma que pondra en DB_PASSWORD del .env
RED_API='10.0.1.%'              # subred publica-api
CNF=/etc/mysql/mysql.conf.d/mysqld.cnf

# 1) Escuchar en todas las interfaces (por omision solo 127.0.0.1)
sed -i 's/^bind-address.*/bind-address = 0.0.0.0/' "$CNF"
systemctl restart mysql

# 2) Base veterinaria en utf8mb4 y 3) usuario vet_app solo desde la subred de la API
mysql <<SQL
CREATE DATABASE IF NOT EXISTS veterinaria
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'vet_app'@'${RED_API}' IDENTIFIED BY '${CLAVE}';
GRANT ALL PRIVILEGES ON veterinaria.* TO 'vet_app'@'${RED_API}';
FLUSH PRIVILEGES;
SQL

echo "---- Datos de conexion para el .env de ec2-api ----"
echo "DB_HOST=$(hostname -I | awk '{print $1}')"
echo "DB_PORT=3306"
echo "DB_USER=vet_app"
echo "DB_PASSWORD=${CLAVE}"
echo "DB_NAME=veterinaria"
echo "---- MySQL escuchando en: ----"
ss -lntp | grep 3306
EOF
chmod 700 /root/preparar-base.sh

echo "USER DATA MYSQL TERMINADO"
