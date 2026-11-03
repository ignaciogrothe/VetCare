"""Prueba de humo de los endpoints E01-E16 contra la API corriendo.

Uso: python3 tool/probar_api.py [http://localhost:8080]
(ADMIN_CLAVE en el entorno si el admin no usa la clave por defecto)
Crea datos de prueba con emails unicos, asi que se puede repetir.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timedelta

BASE = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8080"
SUFIJO = str(int(time.time()))
ADMIN_CLAVE = os.environ.get("ADMIN_CLAVE", "admin12345")
fallas = 0
total = 0


def pedir(metodo, ruta, cuerpo=None, token=None, crudo=None):
    datos = crudo if crudo is not None else (
        json.dumps(cuerpo).encode() if cuerpo is not None else None)
    req = urllib.request.Request(BASE + ruta, data=datos, method=metodo)
    req.add_header("content-type", "application/json")
    if token:
        req.add_header("authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(req) as r:
            texto = r.read().decode()
            return r.status, (json.loads(texto) if texto else None), dict(r.headers)
    except urllib.error.HTTPError as e:
        texto = e.read().decode()
        return e.code, (json.loads(texto) if texto else None), dict(e.headers)


def caso(nombre, esperado, metodo, ruta, cuerpo=None, token=None, crudo=None):
    global fallas, total
    total += 1
    estado, datos, cabeceras = pedir(metodo, ruta, cuerpo, token, crudo)
    ok = estado == esperado
    if not ok:
        fallas += 1
    print(f"{'OK ' if ok else 'MAL'} {estado} (esperado {esperado})  {nombre}")
    if not ok:
        print("     ", datos)
    return datos, cabeceras


def login(email, clave):
    estado, datos, _ = pedir("POST", "/api/auth/login", {"email": email, "clave": clave})
    assert estado == 200, datos
    return datos["access_token"]


clave = "clave-segura-123"
print("--- E01 login / E02 registro / E03 personal")
caso("E01 login admin", 200, "POST", "/api/auth/login",
     {"email": "admin@clinica.cl", "clave": ADMIN_CLAVE})
caso("E01 clave incorrecta", 401, "POST", "/api/auth/login",
     {"email": "admin@clinica.cl", "clave": "mala-clave"})
caso("E01 email inexistente (mismo 401)", 401, "POST", "/api/auth/login",
     {"email": "nadie@x.cl", "clave": "mala-clave"})
caso("E01 sin clave", 400, "POST", "/api/auth/login", {"email": "a@b.cl"})
caso("E01 JSON invalido", 400, "POST", "/api/auth/login", crudo=b"{no-json")
admin = login("admin@clinica.cl", ADMIN_CLAVE)

ana, cab = caso("E02 registro dueno (rol enviado se ignora)", 201, "POST",
                "/api/auth/registro",
                {"nombre": "Ana Rojas", "email": f"ana{SUFIJO}@correo.cl",
                 "clave": clave, "telefono": "987654321", "rol": "administrador"})
assert ana["rol"] == "dueno" and "clave" not in ana and cab.get("location") == "/api/auth/yo", ana
caso("E02 email repetido", 409, "POST", "/api/auth/registro",
     {"nombre": "Ana", "email": f"ANA{SUFIJO}@correo.cl", "clave": clave})
caso("E02 clave corta y telefono malo", 400, "POST", "/api/auth/registro",
     {"nombre": "Ana", "email": f"x{SUFIJO}@correo.cl", "clave": "123", "telefono": "12ab"})
luis, _ = caso("E02 segundo dueno", 201, "POST", "/api/auth/registro",
               {"nombre": "Luis Perez", "email": f"luis{SUFIJO}@correo.cl", "clave": clave})
t_ana = login(f"ana{SUFIJO}@correo.cl", clave)
t_luis = login(f"luis{SUFIJO}@correo.cl", clave)
caso("GET /api/auth/yo", 200, "GET", "/api/auth/yo", token=t_ana)

vet, cab = caso("E03 crear veterinario", 201, "POST", "/api/usuarios",
                {"nombre": "Dr. Pablo Soto", "email": f"psoto{SUFIJO}@clinica.cl",
                 "clave": clave, "rol": "veterinario"}, admin)
assert cab.get("location") == f"/api/usuarios/{vet['id']}"
vet2, _ = caso("E03 crear otro veterinario", 201, "POST", "/api/usuarios",
               {"nombre": "Dra. Marta Diaz", "email": f"mdiaz{SUFIJO}@clinica.cl",
                "clave": clave, "rol": "veterinario"}, admin)
caso("E03 crear recepcionista", 201, "POST", "/api/usuarios",
     {"nombre": "Rosa Recepcion", "email": f"rosa{SUFIJO}@clinica.cl",
      "clave": clave, "rol": "recepcionista"}, admin)
caso("E03 rol dueno no permitido", 400, "POST", "/api/usuarios",
     {"nombre": "X", "email": f"y{SUFIJO}@c.cl", "clave": clave, "rol": "dueno"}, admin)
caso("E03 sin token", 401, "POST", "/api/usuarios", {})
caso("E03 token invalido", 401, "POST", "/api/usuarios", {}, "abc.def.ghi")
caso("E03 dueno no es admin", 403, "POST", "/api/usuarios", {}, t_ana)
caso("E03 email repetido", 409, "POST", "/api/usuarios",
     {"nombre": "Otro", "email": f"psoto{SUFIJO}@clinica.cl", "clave": clave,
      "rol": "veterinario"}, admin)
t_vet = login(f"psoto{SUFIJO}@clinica.cl", clave)
t_vet2 = login(f"mdiaz{SUFIJO}@clinica.cl", clave)
t_rec = login(f"rosa{SUFIJO}@clinica.cl", clave)

print("--- E04 veterinarios")
vets, _ = caso("E04 recepcionista lista vets", 200, "GET", "/api/veterinarios", token=t_rec)
assert all(set(v) == {"id", "nombre"} for v in vets)
caso("E04 dueno", 403, "GET", "/api/veterinarios", token=t_ana)
caso("E04 sin token", 401, "GET", "/api/veterinarios")

print("--- E05-E09 mascotas")
rocky, cab = caso("E06 crear mascota", 201, "POST", "/api/mascotas",
                  {"nombre": "Rocky", "especie": "perro", "sexo": "macho",
                   "fecha_nacimiento": "2021-03-15", "peso_kg": 12.5,
                   "dueno_id": ana["id"]}, t_rec)
assert rocky["dueno"] == {"id": ana["id"], "nombre": "Ana Rojas"} and rocky["peso_kg"] == 12.5
assert cab.get("location") == f"/api/mascotas/{rocky['id']}"
michi, _ = caso("E06 mascota de otro dueno", 201, "POST", "/api/mascotas",
                {"nombre": "Michi", "especie": "gato", "sexo": "hembra",
                 "dueno_id": luis["id"]}, t_rec)
caso("E06 validaciones (fecha futura, peso, especie)", 400, "POST", "/api/mascotas",
     {"nombre": "R", "especie": "dragon", "sexo": "x", "fecha_nacimiento": "2099-01-01",
      "peso_kg": 500, "dueno_id": ana["id"]}, t_rec)
caso("E06 fecha imposible", 400, "POST", "/api/mascotas",
     {"nombre": "Rocky", "especie": "perro", "sexo": "macho",
      "fecha_nacimiento": "2021-02-30", "dueno_id": ana["id"]}, t_rec)
caso("E06 envia id", 400, "POST", "/api/mascotas",
     {"id": 99, "nombre": "Rocky", "especie": "perro", "sexo": "macho",
      "dueno_id": ana["id"]}, t_rec)
caso("E06 dueno_id es veterinario", 422, "POST", "/api/mascotas",
     {"nombre": "Rocky", "especie": "perro", "sexo": "macho", "dueno_id": vet["id"]}, t_rec)
caso("E06 veterinario no puede", 403, "POST", "/api/mascotas", {}, t_vet)
caso("E06 sin token", 401, "POST", "/api/mascotas", {})

lista, _ = caso("E05 dueno ve solo las suyas", 200, "GET", "/api/mascotas", token=t_ana)
assert [m["id"] for m in lista["items"]] == [rocky["id"]] and lista["total"] == 1, lista
lista, _ = caso("E05 personal filtra por especie", 200, "GET",
                "/api/mascotas?especie=gato&tamano=50", token=t_rec)
assert all(m["especie"] == "gato" for m in lista["items"])
caso("E05 tamano > 50", 400, "GET", "/api/mascotas?tamano=51", token=t_rec)
caso("E05 pagina 0", 400, "GET", "/api/mascotas?pagina=0", token=t_rec)
caso("E05 sin token", 401, "GET", "/api/mascotas")

caso("E07 dueno ve la suya", 200, "GET", f"/api/mascotas/{rocky['id']}", token=t_ana)
caso("E07 dueno ve ajena", 403, "GET", f"/api/mascotas/{michi['id']}", token=t_ana)
caso("E07 veterinario ve cualquiera", 200, "GET", f"/api/mascotas/{michi['id']}", token=t_vet)
caso("E07 no existe", 404, "GET", "/api/mascotas/999999", token=t_rec)
caso("E07 sin token", 401, "GET", f"/api/mascotas/{rocky['id']}")

m, _ = caso("E08 cambiar nombre y peso", 200, "PATCH", f"/api/mascotas/{rocky['id']}",
            {"nombre": "Rocky II", "peso_kg": 13.2}, t_rec)
assert m["nombre"] == "Rocky II" and m["peso_kg"] == 13.2
caso("E08 cambiar especie", 400, "PATCH", f"/api/mascotas/{rocky['id']}",
     {"especie": "gato"}, t_rec)
caso("E08 cambiar dueno_id", 400, "PATCH", f"/api/mascotas/{rocky['id']}",
     {"dueno_id": luis["id"]}, t_rec)
caso("E08 dueno no puede", 403, "PATCH", f"/api/mascotas/{rocky['id']}",
     {"nombre": "X"}, t_ana)
caso("E08 no existe", 404, "PATCH", "/api/mascotas/999999", {"nombre": "Xx"}, t_rec)
caso("E08 sin token", 401, "PATCH", f"/api/mascotas/{rocky['id']}", {"nombre": "Xx"})

print("--- E10-E13 citas")
manana = (datetime.now() + timedelta(days=1)).replace(hour=10, minute=30, second=0, microsecond=0)
iso = manana.strftime("%Y-%m-%dT%H:%M:%S")
cita, cab = caso("E11 agendar cita", 201, "POST", "/api/citas",
                 {"mascota_id": rocky["id"], "veterinario_id": vet["id"],
                  "fecha_hora": iso, "motivo": "Vacuna anual"}, t_rec)
assert cita["estado"] == "agendada" and cita["fecha_hora"] == iso
assert cab.get("location") == f"/api/citas/{cita['id']}"
caso("E11 veterinario ocupado", 409, "POST", "/api/citas",
     {"mascota_id": michi["id"], "veterinario_id": vet["id"], "fecha_hora": iso,
      "motivo": "Control"}, t_rec)
caso("E11 fuera de bloque 30 min", 400, "POST", "/api/citas",
     {"mascota_id": rocky["id"], "veterinario_id": vet["id"],
      "fecha_hora": manana.strftime("%Y-%m-%dT10:15:00"), "motivo": "Control"}, t_rec)
caso("E11 fecha pasada", 400, "POST", "/api/citas",
     {"mascota_id": rocky["id"], "veterinario_id": vet["id"],
      "fecha_hora": "2020-01-01T10:00:00", "motivo": "Control"}, t_rec)
caso("E11 envia estado", 400, "POST", "/api/citas",
     {"mascota_id": rocky["id"], "veterinario_id": vet["id"], "fecha_hora": iso,
      "motivo": "Control", "estado": "atendida"}, t_rec)
caso("E11 veterinario_id no es veterinario", 422, "POST", "/api/citas",
     {"mascota_id": rocky["id"], "veterinario_id": ana["id"],
      "fecha_hora": iso, "motivo": "Control"}, t_rec)
caso("E11 mascota inexistente", 422, "POST", "/api/citas",
     {"mascota_id": 999999, "veterinario_id": vet["id"],
      "fecha_hora": iso, "motivo": "Control"}, t_rec)
caso("E11 dueno no puede", 403, "POST", "/api/citas", {}, t_ana)
caso("E11 sin token", 401, "POST", "/api/citas", {})
cita_michi, _ = caso("E11 otra hora para Michi", 201, "POST", "/api/citas",
                     {"mascota_id": michi["id"], "veterinario_id": vet["id"],
                      "fecha_hora": manana.strftime("%Y-%m-%dT11:00:00"),
                      "motivo": "Control"}, t_rec)
cita_cancelar, _ = caso("E11 cita para cancelar", 201, "POST", "/api/citas",
                        {"mascota_id": rocky["id"], "veterinario_id": vet2["id"],
                         "fecha_hora": manana.strftime("%Y-%m-%dT12:00:00"),
                         "motivo": "Control de peso"}, t_rec)

lista, _ = caso("E10 dueno ve solo citas de sus mascotas", 200, "GET", "/api/citas", token=t_ana)
assert {c["mascota_id"] for c in lista["items"]} == {rocky["id"]}, lista
assert all("diagnostico" not in c for c in lista["items"])
lista, _ = caso("E10 filtro fecha y estado", 200, "GET",
                f"/api/citas?fecha={manana:%Y-%m-%d}&estado=agendada&tamano=50", token=t_rec)
assert {cita["id"], cita_michi["id"]} <= {c["id"] for c in lista["items"]}
caso("E10 estado invalido", 400, "GET", "/api/citas?estado=perdida", token=t_rec)
caso("E10 fecha invalida", 400, "GET", "/api/citas?fecha=03-11-2026", token=t_rec)
caso("E10 sin token", 401, "GET", "/api/citas")

caso("E12 dueno ve su cita", 200, "GET", f"/api/citas/{cita['id']}", token=t_ana)
caso("E12 dueno ve cita ajena", 403, "GET", f"/api/citas/{cita_michi['id']}", token=t_ana)
caso("E12 no existe", 404, "GET", "/api/citas/999999", token=t_rec)
caso("E12 sin token", 401, "GET", f"/api/citas/{cita['id']}")

c, _ = caso("E13 cancelar", 200, "POST", f"/api/citas/{cita_cancelar['id']}/cancelacion",
            token=t_rec)
assert c["estado"] == "cancelada"
caso("E13 cancelar de nuevo", 409, "POST",
     f"/api/citas/{cita_cancelar['id']}/cancelacion", token=t_rec)
caso("E13 veterinario no puede", 403, "POST", f"/api/citas/{cita['id']}/cancelacion",
     token=t_vet)
caso("E13 no existe", 404, "POST", "/api/citas/999999/cancelacion", token=t_rec)
caso("E13 sin token", 401, "POST", f"/api/citas/{cita['id']}/cancelacion")
caso("E11 bloque de cita cancelada queda libre", 201, "POST", "/api/citas",
     {"mascota_id": michi["id"], "veterinario_id": vet2["id"],
      "fecha_hora": manana.strftime("%Y-%m-%dT12:00:00"), "motivo": "Control"}, t_rec)

print("--- E14-E16 atencion")
receta = [{"medicamento": "Otomax", "dosis": "4 gotas por oido", "duracion_dias": 7}]
caso("E14 otro veterinario", 403, "POST", f"/api/citas/{cita['id']}/atencion",
     {"diagnostico": "Otitis externa leve"}, t_vet2)
caso("E14 recepcionista", 403, "POST", f"/api/citas/{cita['id']}/atencion",
     {"diagnostico": "Otitis externa leve"}, t_rec)
caso("E14 receta invalida", 400, "POST", f"/api/citas/{cita['id']}/atencion",
     {"diagnostico": "Otitis externa leve",
      "medicamentos": [{"medicamento": "O", "dosis": "", "duracion_dias": 120}]}, t_vet)
caso("E14 cita cancelada", 409, "POST", f"/api/citas/{cita_cancelar['id']}/atencion",
     {"diagnostico": "Otitis externa leve"}, t_vet2)
caso("E15 sin atencion aun", 404, "GET", f"/api/citas/{cita['id']}/atencion", token=t_ana)
a, cab = caso("E14 registrar atencion", 201, "POST", f"/api/citas/{cita['id']}/atencion",
              {"diagnostico": "Otitis externa leve", "tratamiento": "Limpieza otica cada 12 h",
               "medicamentos": receta}, t_vet)
assert a["medicamentos"] == receta and a["cita_id"] == cita["id"]
assert cab.get("location") == f"/api/citas/{cita['id']}/atencion"
caso("E14 atencion duplicada", 409, "POST", f"/api/citas/{cita['id']}/atencion",
     {"diagnostico": "Otra vez"}, t_vet)
caso("E14 no existe", 404, "POST", "/api/citas/999999/atencion",
     {"diagnostico": "Otitis"}, t_vet)
caso("E14 sin token", 401, "POST", f"/api/citas/{cita['id']}/atencion", {})
c, _ = caso("E12 cita quedo atendida", 200, "GET", f"/api/citas/{cita['id']}", token=t_rec)
assert c["estado"] == "atendida" and "diagnostico" not in c
caso("E13 no se cancela una atendida", 409, "POST",
     f"/api/citas/{cita['id']}/cancelacion", token=t_rec)

caso("E15 dueno lee diagnostico", 200, "GET", f"/api/citas/{cita['id']}/atencion", token=t_ana)
caso("E15 admin lee diagnostico", 200, "GET", f"/api/citas/{cita['id']}/atencion", token=admin)
caso("E15 recepcionista siempre 403", 403, "GET", f"/api/citas/{cita['id']}/atencion",
     token=t_rec)
caso("E15 dueno ajeno", 403, "GET", f"/api/citas/{cita['id']}/atencion", token=t_luis)
caso("E15 no existe", 404, "GET", "/api/citas/999999/atencion", token=t_vet)
caso("E15 sin token", 401, "GET", f"/api/citas/{cita['id']}/atencion")

a, _ = caso("E16 corregir (receta vacia)", 200, "PATCH", f"/api/citas/{cita['id']}/atencion",
            {"diagnostico": "Otitis externa resuelta", "medicamentos": []}, t_vet)
assert a["diagnostico"] == "Otitis externa resuelta" and a["medicamentos"] == []
assert a["tratamiento"] == "Limpieza otica cada 12 h"
caso("E16 otro veterinario", 403, "PATCH", f"/api/citas/{cita['id']}/atencion",
     {"diagnostico": "Cambio no autorizado"}, t_vet2)
caso("E16 diagnostico corto", 400, "PATCH", f"/api/citas/{cita['id']}/atencion",
     {"diagnostico": "ok"}, t_vet)
caso("E16 cita sin atencion", 404, "PATCH", f"/api/citas/{cita_michi['id']}/atencion",
     {"diagnostico": "Diagnostico"}, t_vet)
caso("E16 sin token", 401, "PATCH", f"/api/citas/{cita['id']}/atencion", {})

print("--- E09 eliminar mascota")
caso("E09 recepcionista no puede", 403, "DELETE", f"/api/mascotas/{rocky['id']}", token=t_rec)
caso("E09 con citas", 409, "DELETE", f"/api/mascotas/{rocky['id']}", token=admin)
caso("E09 no existe", 404, "DELETE", "/api/mascotas/999999", token=admin)
caso("E09 sin token", 401, "DELETE", f"/api/mascotas/{rocky['id']}")
sin_citas, _ = caso("E06 mascota sin citas", 201, "POST", "/api/mascotas",
                    {"nombre": "Pio", "especie": "ave", "sexo": "macho",
                     "dueno_id": ana["id"]}, t_rec)
caso("E09 eliminar", 204, "DELETE", f"/api/mascotas/{sin_citas['id']}", token=admin)
caso("E07 ya no existe", 404, "GET", f"/api/mascotas/{sin_citas['id']}", token=admin)

caso("Ruta inexistente", 404, "GET", "/api/nada", token=admin)

print(f"\n{total - fallas}/{total} casos correctos")
sys.exit(1 if fallas else 0)
