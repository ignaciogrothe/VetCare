# API Veterinaria con dos motores de datos

API REST en Flask. **MySQL 8** guarda usuarios, mascotas y citas; **MongoDB 7**
guarda las atenciones clínicas (con su receta anidada). Los tres servicios
(`api`, `mysql`, `mongo`) se levantan con Docker Compose. Es el mismo contrato
de la API en Dart de `../backend_api` (endpoints E01–E16), por lo que la app
Flutter de `../flutter_application_1` funciona sin cambios.

El reparto de datos y su justificación están en
[`DECISION-DE-MODELADO.md`](DECISION-DE-MODELADO.md).

## Requisitos

* Docker Desktop (o Docker Engine + Compose v2)
* Para las pruebas: `bash`, `curl` y `python3`

## Arranque

```bash
cp .env.ejemplo .env        # y cambie las claves
docker compose up -d --build
```

Listo: <http://127.0.0.1:8080/api/salud> responde `{"estado":"ok","mysql":"ok","mongo":"ok"}`.

* El esquema de MySQL (`sql/schema.sql`) se aplica solo la primera vez que se crea el volumen.
* El administrador inicial se crea solo al arrancar la API, con `ADMIN_EMAIL` / `ADMIN_CLAVE` del `.env`.
* Los índices de MongoDB se crean al arrancar la API.

## Datos iniciales y pruebas

Un solo comando carga datos de ejemplo (veterinaria, recepcionista, dueña,
mascota, cita, atención) y ejercita todos los endpoints:

```bash
bash pruebas/probar_api.sh
```

Imprime cada petición con su código HTTP y termina con "Todas las pruebas
pasaron." Se puede repetir las veces que se quiera.

## Comandos útiles

```bash
docker compose logs -f api        # ver la API
docker compose down               # detener; los datos se conservan (volúmenes)
docker compose down -v            # detener y BORRAR los datos (vuelve a aplicar el esquema)
```

Si cambia `sql/schema.sql`, haga `docker compose down -v` para que MySQL lo
vuelva a ejecutar (solo corre cuando el volumen está vacío).

## Endpoints

| ID  | Método y ruta                    | Quién                              | Motor |
|-----|----------------------------------|------------------------------------|-------|
| —   | GET /api/salud                   | Público                            | ambos |
| E01 | POST /api/auth/login             | Público                            | MySQL |
| E02 | POST /api/auth/registro          | Público (rol siempre `dueno`)      | MySQL |
| —   | GET /api/auth/yo                 | Autenticado                        | MySQL |
| E03 | POST /api/usuarios               | Administrador                      | MySQL |
| E04 | GET /api/veterinarios            | Personal                           | MySQL |
| E05 | GET /api/mascotas                | Autenticado (dueño: solo las suyas)| MySQL |
| E06 | POST /api/mascotas               | Recepción, administrador           | MySQL |
| E07 | GET /api/mascotas/{id}           | Dueño de la mascota, personal      | MySQL |
| E08 | PATCH /api/mascotas/{id}         | Recepción, administrador           | MySQL |
| E09 | DELETE /api/mascotas/{id}        | Administrador (409 si tiene citas) | MySQL |
| E10 | GET /api/citas                   | Autenticado (dueño: solo las suyas)| MySQL |
| E11 | POST /api/citas                  | Recepción, administrador           | MySQL |
| E12 | GET /api/citas/{id}              | Dueño de la mascota, personal      | MySQL |
| E13 | POST /api/citas/{id}/cancelacion | Recepción, administrador           | MySQL |
| E14 | POST /api/citas/{id}/atencion    | Veterinario asignado               | MySQL + Mongo |
| E15 | GET /api/citas/{id}/atencion     | Dueño, veterinario, administrador  | Mongo |
| E16 | PATCH /api/citas/{id}/atencion   | Veterinario asignado               | Mongo |
| —   | **GET /api/mascotas/{id}/historial** | Dueño, veterinario, administrador | **MySQL + Mongo** |

Errores siempre en JSON: `{"error": "...", "codigo": 400, "detalles": {...}}`.
Autenticación: `Authorization: Bearer <token>` (se obtiene en E01).

## App Flutter

```bash
cd ../flutter_application_1
flutter run                                                  # emulador: http://10.0.2.2:8080
flutter run --dart-define=API_URL=http://IP_DEL_COMPUTADOR:8080   # teléfono físico
```

## Estructura

```
api_poliglota/
  app/                  código de la API (Flask)
    __init__.py         fábrica, administrador inicial, índice de Mongo
    rutas.py            los endpoints
    db.py               conexiones a MySQL y MongoDB
    auth.py             JWT y bcrypt
    validacion.py       validación de la entrada
    errores.py          errores en JSON
  sql/schema.sql        esquema de MySQL
  Dockerfile  .dockerignore  compose.yml  .env.ejemplo  requirements.txt
  pruebas/probar_api.sh
  DECISION-DE-MODELADO.md
```
