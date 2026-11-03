# API Veterinaria (Caso 2) — Dart + MySQL

Implementa los endpoints E01–E16 de `Grothe_Gonzalez_EspecAPI.xlsx`. La app
Android que la consume está en `../flutter_application_1`.

## 1. Base de datos

```bash
brew install mysql          # si no está instalado
brew services start mysql
mysql -u root < sql/schema.sql
```

## 2. Levantar la API

```bash
cd backend_api
dart pub get
DB_PASSWORD='' JWT_SECRET='un-secreto-largo' dart run bin/server.dart
```

Variables de entorno (todas opcionales):

| Variable      | Por defecto                          |
|---------------|--------------------------------------|
| `DB_HOST`     | `127.0.0.1`                          |
| `DB_PORT`     | `3306`                               |
| `DB_USER`     | `root`                               |
| `DB_PASSWORD` | vacío                                |
| `DB_NAME`     | `veterinaria`                        |
| `DB_SSL`      | `true` (MySQL 8+ lo exige para `caching_sha2_password`) |
| `PORT`        | `8080`                               |
| `JWT_SECRET`  | `cambiar-este-secreto-en-produccion` |
| `ADMIN_EMAIL` | `admin@clinica.cl`                   |
| `ADMIN_CLAVE` | `admin12345`                         |

Si no hay ningún administrador, el servidor crea uno al arrancar con
`ADMIN_EMAIL` / `ADMIN_CLAVE`. Con él se crean veterinarios y recepcionistas
(E03); los dueños se registran solos desde la app (E02).

## 3. App Android

```bash
cd ../flutter_application_1
flutter run                                              # emulador: usa http://10.0.2.2:8080
flutter run --dart-define=API_URL=http://192.168.1.20:8080   # teléfono físico: IP del computador
```

## Endpoints

| ID  | Método y ruta                     | Quién                                   |
|-----|-----------------------------------|-----------------------------------------|
| E01 | POST /api/auth/login              | Público                                 |
| E02 | POST /api/auth/registro           | Público (rol siempre `dueno`)           |
| —   | GET /api/auth/yo                  | Autenticado (destino del `Location` de E02) |
| E03 | POST /api/usuarios                | Administrador                           |
| E04 | GET /api/veterinarios             | Personal                                |
| E05 | GET /api/mascotas                 | Autenticado (dueño: solo las suyas)     |
| E06 | POST /api/mascotas                | Recepcionista, administrador            |
| E07 | GET /api/mascotas/{id}            | Dueño de la mascota, personal           |
| E08 | PATCH /api/mascotas/{id}          | Recepcionista, administrador            |
| E09 | DELETE /api/mascotas/{id}         | Administrador (409 si tiene citas)      |
| E10 | GET /api/citas                    | Autenticado (dueño: solo las suyas)     |
| E11 | POST /api/citas                   | Recepcionista, administrador            |
| E12 | GET /api/citas/{id}               | Dueño de la mascota, personal           |
| E13 | POST /api/citas/{id}/cancelacion  | Recepcionista, administrador            |
| E14 | POST /api/citas/{id}/atencion     | Veterinario asignado                    |
| E15 | GET /api/citas/{id}/atencion      | Dueño, veterinario, administrador       |
| E16 | PATCH /api/citas/{id}/atencion    | Veterinario asignado                    |

Errores con el formato `{"error": "...", "codigo": 400, "detalles": {...}}`.

Decisiones de implementación que la planilla no fija:

- Orden de verificación: 401 → 403 por rol → 404 → 403 por pertenencia → 400 → 422/409.
- Los campos no previstos en el cuerpo (`id`, `rol`, `estado`, …) dan 400,
  salvo en el registro (E02), donde `rol` se ignora como dice la planilla.
- La regla "un veterinario no tiene dos citas agendadas a la misma hora" está
  además en un índice único de MySQL, así dos agendamientos simultáneos no
  pueden pasar los dos.

## Prueba rápida con curl

```bash
TOKEN=$(curl -s localhost:8080/api/auth/login -H 'content-type: application/json' \
  -d '{"email":"admin@clinica.cl","clave":"admin12345"}' | sed 's/.*"access_token":"\([^"]*\)".*/\1/')
curl -s localhost:8080/api/mascotas -H "authorization: Bearer $TOKEN"
```
