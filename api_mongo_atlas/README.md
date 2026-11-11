# API de atenciones clínicas — Flask + MongoDB Atlas

La misma API del taller de catálogo, ahora con los datos de la veterinaria
(proyecto VetCare). Una colección, `atenciones`, con el **mismo documento** que
usa el lado MongoDB de [`../api_poliglota`](../api_poliglota): el modelo NoSQL
se entrega una vez y sirve para las dos asignaturas.

```json
{
  "cita_id": 12,
  "diagnostico": "Otitis externa leve",
  "tratamiento": "Limpieza diaria",
  "medicamentos": [{"medicamento": "Otomax", "dosis": "2 gotas cada 12 h", "duracion_dias": 7}],
  "fecha_registro": "2026-11-11T12:00:00+00:00"
}
```

`cita_id` es el identificador de la cita. En la API poliglota vive en MySQL;
aquí, sin base relacional, es solo un entero único (un índice `unique` impide
dos atenciones para la misma cita).

## Configurar y levantar

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.ejemplo .env          # pegue su MONGO_URI de Atlas (variable MONGO_URI, no MONGODB_URI)
python semilla.py             # 6 atenciones de ejemplo
python run.py                 # http://127.0.0.1:5001
```

Con Docker: `docker compose up -d --build` y luego `docker compose exec api python semilla.py`.
El puerto es **5001** porque en macOS el 5000 lo ocupa AirPlay Receiver.
Si su red bloquea el puerto 27017 (wifi de la universidad), Atlas no conecta: use otra red.

## Endpoints

| Método | Ruta | Qué hace | Éxito |
|---|---|---|---|
| GET | `/api/salud` | Comprueba que la base responde | 200 |
| GET | `/api/atenciones` | Lista con filtros, proyección y paginación | 200 |
| GET | `/api/atenciones/<id>` | Una atención completa | 200 |
| POST | `/api/atenciones` | Crea (409 si la cita ya tiene atención) | 201 |
| PUT | `/api/atenciones/<id>` | Actualiza parcial (`medicamentos` reemplaza la receta) | 200 |
| DELETE | `/api/atenciones/<id>` | Elimina | 204 |
| GET | `/api/atenciones/resumen/medicamentos` | Agregación: medicamentos más recetados | 200 |

Filtros de `GET /api/atenciones`:

```
?cita_id=12
?buscar=otitis                   en diagnóstico o tratamiento (texto literal, sin regex)
?medicamento=amoxi               dentro del arreglo anidado ($elemMatch)
?desde=2026-11-01&hasta=2026-11-30
?orden=fecha_registro&dir=desc   orden: fecha_registro | cita_id
?pagina=2&tam=5                  tam máximo 100
```

Errores en JSON: `{"error": "...", "detalle": {...}}` con 400, 404, 405, 409, 415 y 503.

## Probar

```bash
python pruebas_locales.py     # 36 pruebas sin Atlas (pip install mongomock)
bash probar_api.sh            # contra el servidor corriendo
```

## Qué mirar en el código

1. **`rutas/atenciones.py`, `listar()`**: filtros y proyección en MongoDB, no en Python; `$elemMatch` consulta dentro del arreglo.
2. **`resumen_medicamentos()`**: `$unwind` abre el arreglo anidado y `$group` cuenta; en SQL sería un JOIN con una tabla de recetas.
3. **`crear()`**: no hay `find` previo; el índice único decide y `DuplicateKeyError` se traduce a 409.
4. **`validacion.py`**: Mongo acepta cualquier documento, la coherencia es responsabilidad de la API.
