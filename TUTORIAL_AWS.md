# Tutorial: desplegar una API con MySQL en AWS (VPC + EC2)

Este tutorial explica cómo publicar en internet la API de este repositorio
(Dart + MySQL, carpeta `backend_api/`) usando una cuenta de **AWS Academy
Learner Lab**. Al terminar tendrán:

- Una **VPC** propia con una subred pública y una privada.
- Una instancia **EC2** (Amazon Linux 2023) en la subred pública.
- **MariaDB** (compatible con MySQL) corriendo dentro de la misma instancia.
- La **API** corriendo como servicio, accesible en `http://<IP-pública>:8080`.
- La app Flutter y Postman apuntando a esa dirección.

Tiempo estimado: 45–60 minutos.

```
              Internet
                 │
         ┌───────┴────────┐  puerto 8080 (API), 22/443 (SSH)
         │ Internet Gateway│
 VPC ────┼────────────────┼──────────────────────────────
         │ Subred pública │
         │  ┌───────────────────────────┐
         │  │ EC2 t3.micro              │
         │  │  ├─ API (systemd) :8080   │
         │  │  └─ MariaDB       :3306 ◄─┼── solo localhost
         │  └───────────────────────────┘
         │ Subred privada (sin uso; ahí iría RDS si se quisiera)
         └───────────────────────────────────────────────
```

> **¿Por qué la base de datos en la misma EC2?** Para un proyecto de curso es
> lo más simple y gratis. MariaDB escucha solo en `localhost`, así que no queda
> expuesta a internet. Si más adelante quieren separarla, se usa **RDS** en la
> subred privada (ver [Variante con RDS](#variante-con-rds)).

---

## 0. Requisitos

En su computador:

| Herramienta | Para qué | Cómo verificar |
|---|---|---|
| Flutter (incluye Dart **3.8 o superior**) | Compilar la API para Linux y correr la app | `flutter --version` |
| Terminal con `ssh` y `scp` | Conectarse a la EC2 y subir archivos | `ssh -V` (macOS/Linux ya lo traen; en Windows usar PowerShell) |
| Postman (opcional) | Probar los endpoints | — |
| Este repositorio clonado | El código de la API | `ls backend_api` |

En AWS: acceso al **Learner Lab** (botón *Start Lab* y luego *AWS* cuando el
círculo esté en verde). Todo el tutorial usa la región **us-east-1 (N. Virginia)**.

En los comandos, reemplacen:

- `<IP>` → la IP pública de su EC2 (paso 3).
- `<PEM>` → la ruta de su llave, por ejemplo `~/Downloads/labsuser.pem`.
- `<PUERTO_SSH>` → `22`, o `443` si su red bloquea el 22 (paso 4).

---

## 1. Crear la VPC

1. En la consola, buscar **VPC** → **Your VPCs** → **Create VPC**.
2. Elegir **VPC and more** (crea todo de una vez).
3. Configurar:
   - **Name tag auto-generation:** un nombre, por ejemplo `vetcare`.
   - **IPv4 CIDR block:** `10.0.0.0/16` (el que viene por defecto).
   - **Number of Availability Zones:** `1`.
   - **Number of public subnets:** `1`.
   - **Number of private subnets:** `1`.
   - **NAT gateways:** **None**. Un NAT gateway cobra por hora y gasta el
     crédito del lab; no lo necesitamos.
   - **VPC endpoints:** **None**.
4. **Create VPC** y esperar a que todo aparezca en verde.

Esto crea la VPC, las dos subredes, el **Internet Gateway** y las tablas de
rutas. La subred pública tiene una ruta `0.0.0.0/0 → igw-…`; la privada no.

---

## 2. Lanzar la instancia EC2

En la consola: **EC2** → **Instances** → **Launch instances**.

| Campo | Valor |
|---|---|
| **Name** | `vetcare-api` (cualquiera) |
| **AMI** | **Amazon Linux 2023** (la que viene por defecto) |
| **Instance type** | **t3.micro** |
| **Key pair** | **vockey** (ya viene en el Learner Lab) |

### Network settings → botón **Edit**

Este paso es el más importante: si no se presiona *Edit*, la instancia queda en
la VPC por defecto y no en la suya.

- **VPC:** la que crearon en el paso 1 (`vetcare-vpc`).
- **Subnet:** la **pública** (su nombre contiene `public`).
- **Auto-assign public IP:** **Enable**.
- **Firewall (security groups):** *Create security group*, con estas reglas:

| Tipo | Puerto | Origen | Para qué |
|---|---|---|---|
| SSH | 22 | My IP (o Anywhere) | Entrar al servidor |
| Custom TCP | 8080 | Anywhere (`0.0.0.0/0`) | La API |
| Custom TCP | 443 | My IP (o Anywhere) | SSH alternativo si su red bloquea el 22 (paso 4) |

> **No abran el 3306 (MySQL).** La base de datos solo la usa la API desde
> dentro de la misma máquina.

El resto (8 GiB de disco, etc.) queda igual. **Launch instance**.

---

## 3. Obtener la IP y la llave

1. **IP pública:** EC2 → Instances → seleccionar la instancia → copiar
   **Public IPv4 address**. Esperar a que *Status check* diga
   **3/3 checks passed** (o 2/2).
2. **Llave:** en la página del Learner Lab → **AWS Details** →
   **Download PEM** → se descarga `labsuser.pem`.
3. En su computador, protegerla (SSH la rechaza si otros usuarios pueden leerla):

   ```bash
   chmod 400 <PEM>
   ```

   En Windows: clic derecho → Propiedades → Seguridad → dejar solo a su usuario.

---

## 4. Conectarse por SSH

```bash
ssh -i <PEM> ec2-user@<IP>
```

Si responde `Operation timed out`:

1. Revisen que la regla SSH del security group permita su IP
   (EC2 → instancia → pestaña **Security** → security group → **Inbound rules**).
   Su IP actual se ve en <https://checkip.amazonaws.com>.
2. Si la regla está bien, **su red bloquea el puerto 22** (pasa en muchas
   universidades). Comprobación: `nc -vz -G 5 github.com 22` también falla.
   En ese caso, habiliten SSH por el puerto 443:
   1. EC2 → instancia → **Connect** → pestaña **EC2 Instance Connect** →
      **Connect**. Se abre una terminal en el navegador.
   2. Pegar:

      ```bash
      printf 'Port 22\nPort 443\n' | sudo tee /etc/ssh/sshd_config.d/10-puerto-443.conf && sudo systemctl restart sshd && sudo ss -tlnp | grep sshd
      ```

      Debe mostrar `sshd` escuchando en `:22` y `:443`.
   3. Desde su computador, conectarse agregando `-p 443`:

      ```bash
      ssh -p 443 -i <PEM> ec2-user@<IP>
      ```

   Otra alternativa rápida: conectar el computador al hotspot del celular.

Desde aquí, cuando el tutorial diga `ssh` o `scp`, usen el puerto que les
funcionó (`-p` para `ssh`, `-P` mayúscula para `scp`).

---

## 5. Compilar la API para Linux (en su computador)

La EC2 no necesita tener Dart instalado: se compila un ejecutable para Linux
desde su computador (Dart 3.8+ permite compilar para otro sistema operativo).

```bash
cd backend_api
dart pub get
dart compile exe bin/server.dart --target-os=linux --target-arch=x64 -o build/veterinaria_api
```

> `t3.micro` es `x86_64`, por eso `--target-arch=x64`. Si eligen una instancia
> Graviton (`t4g`), usen `--target-arch=arm64`. En la EC2, `uname -m` lo confirma.

Si `dart` no se encuentra, usen el que viene con Flutter:
`<carpeta-de-flutter>/bin/dart`.

---

## 6. Subir los archivos

Desde `backend_api/`:

```bash
scp -P <PUERTO_SSH> -i <PEM> build/veterinaria_api sql/schema.sql deploy/veterinaria-api.service ec2-user@<IP>:~
```

Se suben tres archivos a `/home/ec2-user`:

- `veterinaria_api` → la API compilada.
- `schema.sql` → crea la base `veterinaria` y sus tablas.
- `veterinaria-api.service` → la configuración para que Linux la mantenga corriendo.

---

## 7. Instalar la base de datos (en la EC2)

Entrar por SSH y ejecutar lo siguiente **dentro de la instancia**.

### 7.1 Instalar MariaDB

Amazon Linux 2023 trae MariaDB en sus repositorios. Es compatible con MySQL:
mismo SQL, mismo cliente `mysql` y mismo protocolo, así que la API lo usa sin
cambios.

```bash
sudo dnf install -y mariadb105-server
sudo systemctl enable --now mariadb
mariadb --version
```

### 7.2 Crear la base y las tablas

```bash
sudo mysql < ~/schema.sql
sudo mysql -e "SHOW TABLES FROM veterinaria"
```

Deben aparecer `atenciones`, `citas`, `mascotas`, `recetas` y `usuarios`.

### 7.3 Crear un usuario para la API

No usen `root` para la API: creen un usuario que solo tenga acceso a esta base.
Elijan una clave y reemplacen `CLAVE_DB`:

```bash
sudo mysql -e "CREATE USER 'vet'@'localhost' IDENTIFIED BY 'CLAVE_DB'; GRANT ALL ON veterinaria.* TO 'vet'@'localhost'; FLUSH PRIVILEGES;"
mysql -u vet -p veterinaria -e "SHOW TABLES"
```

El último comando pide la clave; si muestra las tablas, el usuario funciona.

---

## 8. Configurar y arrancar la API (en la EC2)

### 8.1 Archivo de configuración

La API lee su configuración desde variables de entorno. Se guardan en un
archivo que solo puede leer `ec2-user`.

Para generar valores aleatorios, en su computador:

```bash
openssl rand -hex 32
```

Luego, en la EC2 (reemplacen los tres valores):

```bash
cat > ~/veterinaria.env <<'EOF'
DB_USER=vet
DB_PASSWORD=CLAVE_DB
DB_SSL=false
JWT_SECRET=pegar-aqui-un-texto-largo-aleatorio
ADMIN_EMAIL=admin@clinica.cl
ADMIN_CLAVE=una-clave-segura-para-el-admin
EOF
chmod 600 ~/veterinaria.env
```

| Variable | Qué es |
|---|---|
| `DB_USER`, `DB_PASSWORD` | El usuario del paso 7.3 |
| `DB_SSL` | `false` con MariaDB. Con MySQL 8 o superior debe ser `true` (ver [Problemas frecuentes](#problemas-frecuentes)) |
| `JWT_SECRET` | Con este secreto se firman los tokens de sesión. Si alguien lo conoce, puede fabricar tokens válidos |
| `ADMIN_EMAIL`, `ADMIN_CLAVE` | Si la base no tiene ningún administrador, la API crea este al arrancar. Con él se crean veterinarios y recepcionistas |

> **No usen `admin12345` en AWS**: la API queda pública en internet.

Otras variables opcionales: `DB_HOST` (por defecto `127.0.0.1`), `DB_PORT`
(`3306`), `DB_NAME` (`veterinaria`) y `PORT` (`8080`).

### 8.2 Instalar como servicio

Así la API arranca sola al encender la instancia y se reinicia si se cae:

```bash
chmod +x ~/veterinaria_api
sudo cp ~/veterinaria-api.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now veterinaria-api
```

### 8.3 Verificar

```bash
systemctl is-active veterinaria-api
sudo journalctl -u veterinaria-api -n 10 --no-pager
curl -s localhost:8080/api/mascotas
```

Deben ver:

- `active`.
- En el log: `Administrador inicial creado: admin@clinica.cl` y
  `API veterinaria escuchando en http://0.0.0.0:8080`.
- `{"error":"Falta el token de acceso","codigo":401}`. Es correcto: ese
  endpoint pide iniciar sesión.

---

## 9. Probar desde internet

### Navegador

Abrir `http://<IP>:8080/api/mascotas` → debe mostrar el mismo JSON con `401`.

> Abrir `http://<IP>:8080/` (sin ruta) devuelve `404 Ruta no encontrada`. Es
> normal: la API solo responde en rutas que empiezan con `/api/`.

### curl (login)

```bash
curl -s http://<IP>:8080/api/auth/login -H 'content-type: application/json' -d '{"email":"admin@clinica.cl","clave":"<ADMIN_CLAVE>"}'
```

Debe devolver un `access_token`.

### Script de pruebas (los 16 endpoints)

Desde `backend_api/` en su computador:

```bash
ADMIN_CLAVE='<ADMIN_CLAVE>' python3 tool/probar_api.py http://<IP>:8080
```

Debe terminar con `101/101 casos correctos`. El script crea datos de prueba
con emails únicos, así que se puede repetir.

### Postman

1. **Import** → elegir `backend_api/postman/Veterinaria_API.postman_collection.json`.
2. En la colección → pestaña **Variables**:
   - `baseUrl` = `http://<IP>:8080`
   - `admin_clave` = su `ADMIN_CLAVE`
3. Guardar (Ctrl/Cmd+S) → **⋯ → Run collection** → **Run**.

Las peticiones van en orden: el login guarda el token y cada creación guarda su
id para las siguientes. Las 88 deben salir en verde.

---

## 10. Conectar la app Flutter

La URL de la API se pasa al compilar la app. En Android Studio:

1. **Run → Edit Configurations…** → configuración `main.dart`.
2. **Additional run args:**

   ```
   --dart-define=API_URL=http://<IP>:8080
   ```

3. Elegir el teléfono o el emulador → **▶ Run**.

O desde la terminal, en `flutter_application_1/`:

```bash
flutter run --dart-define=API_URL=http://<IP>:8080
```

> La app ya tiene en su `AndroidManifest.xml` el permiso `INTERNET` y
> `usesCleartextTraffic="true"`, necesarios para usar `http://` (sin HTTPS).
> Si usan otra app, agréguenlos.

Una vez instalada, la app funciona desde cualquier red, con Wi‑Fi o datos
móviles, sin el computador encendido.

---

## 11. IP fija con Elastic IP (recomendado)

En el Learner Lab, la instancia se detiene cuando termina la sesión del lab.
Al encenderla de nuevo, **la IP pública cambia** y habría que actualizarla en
la app y en Postman. Para que no cambie:

1. EC2 → **Elastic IPs** → **Allocate Elastic IP address** → **Allocate**.
2. Seleccionarla → **Actions → Associate Elastic IP address** → elegir la
   instancia → **Associate**.

Desde ahora `<IP>` es la Elastic IP. Mientras esté asociada a una instancia
encendida no tiene costo extra.

La base de datos y la API **sobreviven** a detener y encender la instancia:
los datos quedan en el disco y el servicio arranca solo.

---

## 12. Actualizar la API después de cambiar el código

En su computador, desde `backend_api/`:

```bash
dart compile exe bin/server.dart --target-os=linux --target-arch=x64 -o build/veterinaria_api
scp -P <PUERTO_SSH> -i <PEM> build/veterinaria_api ec2-user@<IP>:~
ssh -p <PUERTO_SSH> -i <PEM> ec2-user@<IP> 'sudo systemctl restart veterinaria-api && systemctl is-active veterinaria-api'
```

Si cambiaron `sql/schema.sql`, súbanlo y apliquen los cambios con
`sudo mysql veterinaria`. `schema.sql` usa `CREATE TABLE IF NOT EXISTS`, así
que **no modifica tablas que ya existen**: para agregar columnas usen
`ALTER TABLE`.

---

## Problemas frecuentes

| Síntoma | Causa | Solución |
|---|---|---|
| `ssh: … Operation timed out` | La regla SSH no permite su IP, o su red bloquea el 22 | [Paso 4](#4-conectarse-por-ssh) |
| `Permission denied (publickey)` | Llave equivocada, usuario equivocado o permisos del `.pem` | Usuario `ec2-user`, `chmod 400 <PEM>` y la llave del lab actual |
| `WARNING: UNPROTECTED PRIVATE KEY FILE!` | Permisos del `.pem` muy abiertos | `chmod 400 <PEM>` |
| El navegador no carga `http://<IP>:8080` (timeout) | Falta la regla 8080 en el security group, o la EC2 está en la subred privada | Revisar inbound rules y que la subred sea la pública |
| `Connection refused` en el 8080 | La red funciona, pero la API no está corriendo | `sudo journalctl -u veterinaria-api -n 30` |
| Log: `Access denied for user 'vet'@'localhost'` | La clave de `veterinaria.env` no coincide con la del paso 7.3 | Corregir el archivo y `sudo systemctl restart veterinaria-api` |
| Log: `Auth plugin caching_sha2_password is supported only with secure connections` | Usan MySQL 8+ en vez de MariaDB | Poner `DB_SSL=true` en `veterinaria.env` |
| Log: `Unknown database 'veterinaria'` | No se ejecutó `schema.sql` | Paso 7.2 |
| La app dice "No pudimos conectar con el servidor" | `API_URL` mal escrito, IP vieja o falta `usesCleartextTraffic` | Revisar el paso 10 y probar la URL en el navegador del celular |
| La IP cambió | Se reinició el lab | [Paso 11](#11-ip-fija-con-elastic-ip-recomendado) |
| `cannot execute binary file` en la EC2 | Arquitectura equivocada al compilar | `uname -m` en la EC2: `x86_64` → `x64`, `aarch64` → `arm64` |

Comandos útiles dentro de la EC2:

```bash
sudo systemctl status veterinaria-api      # estado del servicio
sudo journalctl -u veterinaria-api -f      # log en vivo (Ctrl+C para salir)
sudo systemctl restart veterinaria-api     # reiniciar la API
sudo mysql veterinaria                     # consola de la base de datos
```

---

## Variante con RDS

Si el curso pide la base de datos en un servicio administrado:

1. **RDS → Create database** → **MySQL**, plantilla *Free tier*,
   `db.t3.micro`.
2. **Connectivity:** su VPC, **Public access: No** y un security group que
   permita el **3306 solo desde el security group de la EC2**. RDS exige
   subredes en dos zonas de disponibilidad: si crearon la VPC con una sola AZ,
   agreguen una segunda subred privada en otra AZ.
3. Desde la EC2, crear la base con el endpoint de RDS:

   ```bash
   sudo dnf install -y mariadb105
   mysql -h <endpoint-rds> -u admin -p < ~/schema.sql
   ```

4. En `veterinaria.env`: `DB_HOST=<endpoint-rds>`, `DB_USER=admin`,
   `DB_PASSWORD=<clave-rds>` y `DB_SSL=true`. Quitar `Requires=mariadb.service`
   de `veterinaria-api.service`.

RDS consume más crédito del lab que tener la base en la EC2.

---

## Al terminar el curso

Para no gastar crédito: **EC2 → Instances → Instance state → Terminate**,
liberar la **Elastic IP** (*Actions → Release*) y borrar la VPC
(*Your VPCs → Actions → Delete VPC*). Terminar la instancia borra también la
base de datos.

## Checklist

- [ ] VPC con subred pública y privada, sin NAT gateway
- [ ] EC2 en la **subred pública**, con IP pública
- [ ] Security group: 22 (o 443) y 8080 abiertos; 3306 **cerrado**
- [ ] MariaDB instalada, con la base `veterinaria` y el usuario `vet`
- [ ] `veterinaria.env` con secretos propios (no `admin12345`) y permiso `600`
- [ ] `systemctl is-active veterinaria-api` → `active`
- [ ] `http://<IP>:8080/api/mascotas` responde `401` desde el navegador
- [ ] `probar_api.py` o la colección de Postman pasan completos
- [ ] La app corre con `--dart-define=API_URL=http://<IP>:8080`
- [ ] (Opcional) Elastic IP asociada
