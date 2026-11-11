"""
Prueba la API completa SIN Atlas ni MongoDB instalado, con un cliente en
memoria (mongomock).

    pip install mongomock
    python pruebas_locales.py

No reemplaza probar contra Atlas: verifica logica, validacion y codigos.
"""

import sys

import mongomock

import app.db as db_modulo
from app import crear_app

_falso = mongomock.MongoClient()
db_modulo.obtener_cliente = lambda: _falso
aplicacion = crear_app({"MONGO_DB": "veterinaria_prueba"})
ok = fallo = 0


def probar(titulo, esperado, metodo, ruta, cuerpo=None):
    global ok, fallo
    with aplicacion.test_client() as c:
        f = getattr(c, metodo.lower())
        r = f(ruta, json=cuerpo) if cuerpo is not None else f(ruta)
    if r.status_code == esperado:
        print(f"  OK    {r.status_code:<3} {titulo}"); ok += 1
    else:
        print(f"  FALLA {r.status_code:<3} {titulo}  (se esperaba {esperado})")
        print(f"        -> {r.get_json(silent=True)}"); fallo += 1
    return r


with aplicacion.app_context():
    db_modulo.crear_indices()

OTITIS = {"cita_id": 1, "diagnostico": "Otitis externa leve", "tratamiento": "Limpieza diaria",
          "medicamentos": [{"medicamento": "Otomax", "dosis": "2 gotas", "duracion_dias": 7}]}

print("\n== Crear ==")
r = probar("crear atencion", 201, "POST", "/api/atenciones", OTITIS)
aid = r.get_json()["id"]
assert "_id" not in r.get_json() and r.headers["Location"] == f"/api/atenciones/{aid}"
probar("cita repetida (indice unico)", 409, "POST", "/api/atenciones", OTITIS)
probar("segunda atencion", 201, "POST", "/api/atenciones",
       {"cita_id": 2, "diagnostico": "Gastroenteritis aguda", "medicamentos": [
           {"medicamento": "Amoxicilina", "dosis": "1 comp", "duracion_dias": 5},
           {"medicamento": "Probiotico", "dosis": "1 sobre", "duracion_dias": 10}]})
probar("tercera, sin receta", 201, "POST", "/api/atenciones",
       {"cita_id": 3, "diagnostico": "Control anual sin hallazgos"})

print("\n== Validacion ==")
probar("sin cita_id", 400, "POST", "/api/atenciones", {"diagnostico": "Algo largo"})
probar("sin diagnostico", 400, "POST", "/api/atenciones", {"cita_id": 9})
probar("diagnostico corto", 400, "POST", "/api/atenciones", {"cita_id": 9, "diagnostico": "no"})
probar("cita_id booleano", 400, "POST", "/api/atenciones", {"cita_id": True, "diagnostico": "Algo largo"})
probar("campo no permitido", 400, "POST", "/api/atenciones", {"cita_id": 9, "diagnostico": "Algo largo", "rol": "x"})
probar("medicamento invalido", 400, "POST", "/api/atenciones",
       {"cita_id": 9, "diagnostico": "Algo largo", "medicamentos": [{"medicamento": "A", "duracion_dias": 500}]})
probar("medicamentos no es lista", 400, "POST", "/api/atenciones",
       {"cita_id": 9, "diagnostico": "Algo largo", "medicamentos": "Otomax"})
with aplicacion.test_client() as c:
    r = c.post("/api/atenciones", data="no es json", content_type="application/json")
    print(f"  {'OK   ' if r.status_code == 400 else 'FALLA'} {r.status_code:<3} JSON malformado"); ok += r.status_code == 400; fallo += r.status_code != 400
    r = c.post("/api/atenciones", data="x", content_type="text/plain")
    print(f"  {'OK   ' if r.status_code == 415 else 'FALLA'} {r.status_code:<3} sin Content-Type JSON"); ok += r.status_code == 415; fallo += r.status_code != 415

print("\n== Obtener y listar ==")
r = probar("obtener por id", 200, "GET", f"/api/atenciones/{aid}")
assert r.get_json()["medicamentos"][0]["dosis"] == "2 gotas"
probar("id con formato invalido", 400, "GET", "/api/atenciones/abc")
probar("id valido inexistente", 404, "GET", "/api/atenciones/64b7f0000000000000000000")
r = probar("listar", 200, "GET", "/api/atenciones")
assert r.get_json()["paginacion"]["total"] == 3
assert "tratamiento" not in r.get_json()["datos"][0], "la proyeccion debe excluir tratamiento"
r = probar("filtro por medicamento (en el arreglo)", 200, "GET", "/api/atenciones?medicamento=amoxi")
assert r.get_json()["paginacion"]["total"] == 1
r = probar("buscar en diagnostico", 200, "GET", "/api/atenciones?buscar=otitis")
assert r.get_json()["paginacion"]["total"] == 1
r = probar("buscar con caracteres de regex", 200, "GET", "/api/atenciones?buscar=.*")
assert r.get_json()["paginacion"]["total"] == 0, "el texto se busca literal"
r = probar("filtro por cita_id", 200, "GET", "/api/atenciones?cita_id=2")
assert r.get_json()["paginacion"]["total"] == 1
probar("paginacion", 200, "GET", "/api/atenciones?pagina=2&tam=2")
probar("orden invalido", 400, "GET", "/api/atenciones?orden=diagnostico")
probar("tam fuera de rango", 400, "GET", "/api/atenciones?tam=999")
probar("fecha mal formada", 400, "GET", "/api/atenciones?desde=ayer")
r = probar("rango de fechas de hoy", 200, "GET", "/api/atenciones?desde=2000-01-01&hasta=2100-01-01")
assert r.get_json()["paginacion"]["total"] == 3

print("\n== Actualizar y agregar ==")
r = probar("PUT reemplaza la receta", 200, "PUT", f"/api/atenciones/{aid}",
           {"medicamentos": [{"medicamento": "Amoxicilina", "dosis": "1 comp", "duracion_dias": 3}]})
assert r.get_json()["medicamentos"][0]["medicamento"] == "Amoxicilina" and r.get_json()["diagnostico"] == "Otitis externa leve"
probar("PUT no cambia cita_id", 400, "PUT", f"/api/atenciones/{aid}", {"cita_id": 7})
probar("PUT vacio", 400, "PUT", f"/api/atenciones/{aid}", {})
probar("PUT inexistente", 404, "PUT", "/api/atenciones/64b7f0000000000000000000", {"tratamiento": "x"})
r = probar("resumen de medicamentos ($unwind)", 200, "GET", "/api/atenciones/resumen/medicamentos")
top = r.get_json()["datos"][0]
assert top["medicamento"] == "Amoxicilina" and top["veces"] == 2, top

print("\n== Eliminar ==")
probar("eliminar", 204, "DELETE", f"/api/atenciones/{aid}")
probar("eliminar otra vez", 404, "DELETE", f"/api/atenciones/{aid}")
probar("metodo no permitido", 405, "PATCH", "/api/atenciones")
probar("ruta inexistente", 404, "GET", "/api/nada")
probar("salud", 200, "GET", "/api/salud")

print(f"\n  {ok} OK, {fallo} con fallas")
sys.exit(1 if fallo else 0)
