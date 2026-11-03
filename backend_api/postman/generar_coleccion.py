"""Genera Veterinaria_API.postman_collection.json (Postman v2.1).

Uso: python3 postman/generar_coleccion.py
Las peticiones van en orden: corriendo la coleccion completa (Run collection)
cada una deja guardados en variables los tokens e ids que usan las siguientes.
"""
import json
import os
import uuid

AQUI = os.path.dirname(os.path.abspath(__file__))
SALIDA = os.path.join(AQUI, "Veterinaria_API.postman_collection.json")

CLAVE = "clave-segura-123"

# Antes de la primera peticion: sufijo unico para los emails (la coleccion se
# puede correr varias veces) y una fecha de manana para las citas.
PREPARAR = """
const sufijo = Date.now().toString();
pm.collectionVariables.set('sufijo', sufijo);
const d = new Date(Date.now() + 24 * 3600 * 1000);
const dos = n => String(n).padStart(2, '0');
const dia = `${d.getFullYear()}-${dos(d.getMonth() + 1)}-${dos(d.getDate())}`;
pm.collectionVariables.set('dia_cita', dia);
pm.collectionVariables.set('cita_1030', `${dia}T10:30:00`);
pm.collectionVariables.set('cita_1100', `${dia}T11:00:00`);
pm.collectionVariables.set('cita_1200', `${dia}T12:00:00`);
"""


def guardar(variable, expr):
    return f"pm.collectionVariables.set('{variable}', pm.response.json().{expr});"


def esperar(campo, valor):
    return (f"pm.test('{campo} = {valor}', () => "
            f"pm.expect(pm.response.json().{campo}).to.eql({json.dumps(valor)}));")


# (carpeta, nombre, metodo, ruta, cuerpo, token, estado esperado, js extra, pre-request)
P = []


def r(carpeta, nombre, metodo, ruta, cuerpo=None, token=None, estado=200,
      extra="", pre=""):
    P.append((carpeta, nombre, metodo, ruta, cuerpo, token, estado, extra, pre))


A = "Auth y usuarios (E01-E04)"
r(A, "E01 Login administrador", "POST", "/api/auth/login",
  {"email": "admin@clinica.cl", "clave": "{{admin_clave}}"}, None, 200,
  guardar("token_admin", "access_token") + "\n" + esperar("token_type", "Bearer"),
  PREPARAR)
r(A, "E01 Error 401 clave incorrecta", "POST", "/api/auth/login",
  {"email": "admin@clinica.cl", "clave": "mala-clave"}, None, 401,
  esperar("error", "Credenciales invalidas"))
r(A, "E01 Error 401 email inexistente (mismo mensaje)", "POST", "/api/auth/login",
  {"email": "nadie@correo.cl", "clave": "mala-clave"}, None, 401,
  esperar("error", "Credenciales invalidas"))
r(A, "E01 Error 400 falta la clave", "POST", "/api/auth/login",
  {"email": "admin@clinica.cl"}, None, 400)
r(A, "E02 Registro de dueno (rol enviado se ignora)", "POST", "/api/auth/registro",
  {"nombre": "Ana Rojas", "email": "ana{{sufijo}}@correo.cl", "clave": CLAVE,
   "telefono": "987654321", "rol": "administrador"}, None, 201,
  guardar("id_ana", "id") + "\n" + esperar("rol", "dueno"))
r(A, "E02 Error 409 email repetido", "POST", "/api/auth/registro",
  {"nombre": "Ana Rojas", "email": "ana{{sufijo}}@correo.cl", "clave": CLAVE},
  None, 409)
r(A, "E02 Error 400 clave corta", "POST", "/api/auth/registro",
  {"nombre": "Ana", "email": "otra{{sufijo}}@correo.cl", "clave": "123"}, None, 400)
r(A, "E02 Registro de otro dueno", "POST", "/api/auth/registro",
  {"nombre": "Luis Perez", "email": "luis{{sufijo}}@correo.cl", "clave": CLAVE},
  None, 201, guardar("id_luis", "id"))
r(A, "E01 Login dueno Ana", "POST", "/api/auth/login",
  {"email": "ana{{sufijo}}@correo.cl", "clave": CLAVE}, None, 200,
  guardar("token_ana", "access_token"))
r(A, "E01 Login dueno Luis", "POST", "/api/auth/login",
  {"email": "luis{{sufijo}}@correo.cl", "clave": CLAVE}, None, 200,
  guardar("token_luis", "access_token"))
r(A, "GET /api/auth/yo (usuario conectado)", "GET", "/api/auth/yo", None,
  "token_ana", 200)
r(A, "E03 Crear veterinario", "POST", "/api/usuarios",
  {"nombre": "Dr. Pablo Soto", "email": "psoto{{sufijo}}@clinica.cl",
   "clave": CLAVE, "rol": "veterinario"}, "token_admin", 201,
  guardar("id_vet", "id"))
r(A, "E03 Crear segundo veterinario", "POST", "/api/usuarios",
  {"nombre": "Dra. Marta Diaz", "email": "mdiaz{{sufijo}}@clinica.cl",
   "clave": CLAVE, "rol": "veterinario"}, "token_admin", 201,
  guardar("id_vet2", "id"))
r(A, "E03 Crear recepcionista", "POST", "/api/usuarios",
  {"nombre": "Rosa Recepcion", "email": "rosa{{sufijo}}@clinica.cl",
   "clave": CLAVE, "rol": "recepcionista"}, "token_admin", 201)
r(A, "E03 Error 400 rol no permitido", "POST", "/api/usuarios",
  {"nombre": "X Y", "email": "xy{{sufijo}}@clinica.cl", "clave": CLAVE,
   "rol": "dueno"}, "token_admin", 400)
r(A, "E03 Error 401 sin token", "POST", "/api/usuarios", {}, None, 401)
r(A, "E03 Error 403 dueno no es administrador", "POST", "/api/usuarios", {},
  "token_ana", 403)
r(A, "E03 Error 409 email repetido", "POST", "/api/usuarios",
  {"nombre": "Otro", "email": "psoto{{sufijo}}@clinica.cl", "clave": CLAVE,
   "rol": "veterinario"}, "token_admin", 409)
r(A, "E01 Login veterinario", "POST", "/api/auth/login",
  {"email": "psoto{{sufijo}}@clinica.cl", "clave": CLAVE}, None, 200,
  guardar("token_vet", "access_token"))
r(A, "E01 Login segundo veterinario", "POST", "/api/auth/login",
  {"email": "mdiaz{{sufijo}}@clinica.cl", "clave": CLAVE}, None, 200,
  guardar("token_vet2", "access_token"))
r(A, "E01 Login recepcionista", "POST", "/api/auth/login",
  {"email": "rosa{{sufijo}}@clinica.cl", "clave": CLAVE}, None, 200,
  guardar("token_rec", "access_token"))
r(A, "E04 Listar veterinarios", "GET", "/api/veterinarios", None, "token_rec", 200)
r(A, "E04 Error 403 dueno", "GET", "/api/veterinarios", None, "token_ana", 403)
r(A, "E04 Error 401 sin token", "GET", "/api/veterinarios", None, None, 401)

M = "Mascotas (E05-E09)"
r(M, "E06 Registrar mascota", "POST", "/api/mascotas",
  {"nombre": "Rocky", "especie": "perro", "sexo": "macho",
   "fecha_nacimiento": "2021-03-15", "peso_kg": 12.5, "dueno_id": "{{id_ana}}"},
  "token_rec", 201, guardar("id_rocky", "id"))
r(M, "E06 Registrar mascota de otro dueno", "POST", "/api/mascotas",
  {"nombre": "Michi", "especie": "gato", "sexo": "hembra",
   "dueno_id": "{{id_luis}}"}, "token_rec", 201, guardar("id_michi", "id"))
r(M, "E06 Error 400 validaciones", "POST", "/api/mascotas",
  {"nombre": "R", "especie": "dragon", "sexo": "x",
   "fecha_nacimiento": "2099-01-01", "peso_kg": 500, "dueno_id": "{{id_ana}}"},
  "token_rec", 400)
r(M, "E06 Error 422 dueno_id no es dueno", "POST", "/api/mascotas",
  {"nombre": "Rocky", "especie": "perro", "sexo": "macho",
   "dueno_id": "{{id_vet}}"}, "token_rec", 422)
r(M, "E06 Error 403 veterinario", "POST", "/api/mascotas", {}, "token_vet", 403)
r(M, "E06 Error 401 sin token", "POST", "/api/mascotas", {}, None, 401)
r(M, "E05 Listar mascotas (dueno ve solo las suyas)", "GET", "/api/mascotas",
  None, "token_ana", 200, esperar("total", 1))
r(M, "E05 Listar con filtro y paginacion", "GET",
  "/api/mascotas?especie=gato&pagina=1&tamano=20", None, "token_rec", 200)
r(M, "E05 Error 400 tamano mayor a 50", "GET", "/api/mascotas?tamano=51", None,
  "token_rec", 400)
r(M, "E05 Error 401 sin token", "GET", "/api/mascotas", None, None, 401)
r(M, "E07 Ficha de la mascota (dueno)", "GET", "/api/mascotas/{{id_rocky}}",
  None, "token_ana", 200)
r(M, "E07 Error 403 mascota de otro dueno", "GET", "/api/mascotas/{{id_michi}}",
  None, "token_ana", 403)
r(M, "E07 Error 404 no existe", "GET", "/api/mascotas/999999", None,
  "token_rec", 404)
r(M, "E07 Error 401 sin token", "GET", "/api/mascotas/{{id_rocky}}", None, None, 401)
r(M, "E08 Modificar nombre y peso", "PATCH", "/api/mascotas/{{id_rocky}}",
  {"nombre": "Rocky II", "peso_kg": 13.2}, "token_rec", 200,
  esperar("nombre", "Rocky II"))
r(M, "E08 Error 400 cambiar especie", "PATCH", "/api/mascotas/{{id_rocky}}",
  {"especie": "gato"}, "token_rec", 400)
r(M, "E08 Error 403 dueno", "PATCH", "/api/mascotas/{{id_rocky}}",
  {"nombre": "Otro"}, "token_ana", 403)
r(M, "E08 Error 404 no existe", "PATCH", "/api/mascotas/999999",
  {"nombre": "Otro"}, "token_rec", 404)
r(M, "E08 Error 401 sin token", "PATCH", "/api/mascotas/{{id_rocky}}",
  {"nombre": "Otro"}, None, 401)

C = "Citas (E10-E13)"
r(C, "E11 Agendar cita", "POST", "/api/citas",
  {"mascota_id": "{{id_rocky}}", "veterinario_id": "{{id_vet}}",
   "fecha_hora": "{{cita_1030}}", "motivo": "Vacuna anual"}, "token_rec", 201,
  guardar("id_cita", "id") + "\n" + esperar("estado", "agendada"))
r(C, "E11 Error 409 veterinario ocupado", "POST", "/api/citas",
  {"mascota_id": "{{id_michi}}", "veterinario_id": "{{id_vet}}",
   "fecha_hora": "{{cita_1030}}", "motivo": "Control"}, "token_rec", 409)
r(C, "E11 Error 400 fuera de bloque de 30 min", "POST", "/api/citas",
  {"mascota_id": "{{id_rocky}}", "veterinario_id": "{{id_vet}}",
   "fecha_hora": "{{dia_cita}}T10:15:00", "motivo": "Control"}, "token_rec", 400)
r(C, "E11 Error 400 fecha pasada", "POST", "/api/citas",
  {"mascota_id": "{{id_rocky}}", "veterinario_id": "{{id_vet}}",
   "fecha_hora": "2020-01-01T10:00:00", "motivo": "Control"}, "token_rec", 400)
r(C, "E11 Error 422 veterinario_id no es veterinario", "POST", "/api/citas",
  {"mascota_id": "{{id_rocky}}", "veterinario_id": "{{id_ana}}",
   "fecha_hora": "{{cita_1100}}", "motivo": "Control"}, "token_rec", 422)
r(C, "E11 Error 403 dueno", "POST", "/api/citas", {}, "token_ana", 403)
r(C, "E11 Error 401 sin token", "POST", "/api/citas", {}, None, 401)
r(C, "E11 Agendar cita de Michi", "POST", "/api/citas",
  {"mascota_id": "{{id_michi}}", "veterinario_id": "{{id_vet}}",
   "fecha_hora": "{{cita_1100}}", "motivo": "Control"}, "token_rec", 201,
  guardar("id_cita_michi", "id"))
r(C, "E11 Agendar cita para cancelar", "POST", "/api/citas",
  {"mascota_id": "{{id_rocky}}", "veterinario_id": "{{id_vet2}}",
   "fecha_hora": "{{cita_1200}}", "motivo": "Control de peso"}, "token_rec", 201,
  guardar("id_cita_cancelar", "id"))
r(C, "E10 Listar citas (dueno ve solo las suyas)", "GET", "/api/citas", None,
  "token_ana", 200)
r(C, "E10 Listar con filtro de fecha y estado", "GET",
  "/api/citas?fecha={{dia_cita}}&estado=agendada", None, "token_rec", 200)
r(C, "E10 Error 400 estado invalido", "GET", "/api/citas?estado=perdida", None,
  "token_rec", 400)
r(C, "E10 Error 401 sin token", "GET", "/api/citas", None, None, 401)
r(C, "E12 Detalle de cita (dueno)", "GET", "/api/citas/{{id_cita}}", None,
  "token_ana", 200)
r(C, "E12 Error 403 cita de mascota ajena", "GET", "/api/citas/{{id_cita_michi}}",
  None, "token_ana", 403)
r(C, "E12 Error 404 no existe", "GET", "/api/citas/999999", None, "token_rec", 404)
r(C, "E12 Error 401 sin token", "GET", "/api/citas/{{id_cita}}", None, None, 401)
r(C, "E13 Cancelar cita", "POST", "/api/citas/{{id_cita_cancelar}}/cancelacion",
  None, "token_rec", 200, esperar("estado", "cancelada"))
r(C, "E13 Error 409 ya cancelada", "POST",
  "/api/citas/{{id_cita_cancelar}}/cancelacion", None, "token_rec", 409)
r(C, "E13 Error 403 veterinario", "POST", "/api/citas/{{id_cita}}/cancelacion",
  None, "token_vet", 403)
r(C, "E13 Error 404 no existe", "POST", "/api/citas/999999/cancelacion", None,
  "token_rec", 404)
r(C, "E13 Error 401 sin token", "POST", "/api/citas/{{id_cita}}/cancelacion",
  None, None, 401)

T = "Atencion (E14-E16)"
receta = [{"medicamento": "Otomax", "dosis": "4 gotas por oido", "duracion_dias": 7}]
r(T, "E14 Error 403 otro veterinario", "POST", "/api/citas/{{id_cita}}/atencion",
  {"diagnostico": "Otitis externa leve"}, "token_vet2", 403)
r(T, "E14 Error 400 receta invalida", "POST", "/api/citas/{{id_cita}}/atencion",
  {"diagnostico": "Otitis externa leve",
   "medicamentos": [{"medicamento": "O", "dosis": "", "duracion_dias": 120}]},
  "token_vet", 400)
r(T, "E14 Error 409 cita cancelada", "POST",
  "/api/citas/{{id_cita_cancelar}}/atencion",
  {"diagnostico": "Otitis externa leve"}, "token_vet2", 409)
r(T, "E14 Registrar atencion", "POST", "/api/citas/{{id_cita}}/atencion",
  {"diagnostico": "Otitis externa leve", "tratamiento": "Limpieza otica cada 12 h",
   "medicamentos": receta}, "token_vet", 201)
r(T, "E14 Error 409 atencion duplicada", "POST", "/api/citas/{{id_cita}}/atencion",
  {"diagnostico": "Otra atencion"}, "token_vet", 409)
r(T, "E14 Error 404 no existe", "POST", "/api/citas/999999/atencion",
  {"diagnostico": "Otitis externa"}, "token_vet", 404)
r(T, "E14 Error 401 sin token", "POST", "/api/citas/{{id_cita}}/atencion", {},
  None, 401)
r(T, "E15 Leer diagnostico (dueno)", "GET", "/api/citas/{{id_cita}}/atencion",
  None, "token_ana", 200)
r(T, "E15 Error 403 recepcionista", "GET", "/api/citas/{{id_cita}}/atencion",
  None, "token_rec", 403)
r(T, "E15 Error 403 dueno ajeno", "GET", "/api/citas/{{id_cita}}/atencion",
  None, "token_luis", 403)
r(T, "E15 Error 404 cita sin atencion", "GET",
  "/api/citas/{{id_cita_michi}}/atencion", None, "token_vet", 404)
r(T, "E15 Error 401 sin token", "GET", "/api/citas/{{id_cita}}/atencion", None,
  None, 401)
r(T, "E16 Corregir atencion", "PATCH", "/api/citas/{{id_cita}}/atencion",
  {"diagnostico": "Otitis externa resuelta", "medicamentos": []}, "token_vet", 200,
  esperar("diagnostico", "Otitis externa resuelta"))
r(T, "E16 Error 400 diagnostico corto", "PATCH", "/api/citas/{{id_cita}}/atencion",
  {"diagnostico": "ok"}, "token_vet", 400)
r(T, "E16 Error 403 otro veterinario", "PATCH", "/api/citas/{{id_cita}}/atencion",
  {"diagnostico": "Cambio no autorizado"}, "token_vet2", 403)
r(T, "E16 Error 404 cita sin atencion", "PATCH",
  "/api/citas/{{id_cita_michi}}/atencion", {"diagnostico": "Diagnostico"},
  "token_vet", 404)
r(T, "E16 Error 401 sin token", "PATCH", "/api/citas/{{id_cita}}/atencion", {},
  None, 401)

E = "Eliminar mascota (E09)"
r(E, "E09 Error 403 recepcionista", "DELETE", "/api/mascotas/{{id_rocky}}", None,
  "token_rec", 403)
r(E, "E09 Error 409 tiene citas", "DELETE", "/api/mascotas/{{id_rocky}}", None,
  "token_admin", 409)
r(E, "E09 Error 404 no existe", "DELETE", "/api/mascotas/999999", None,
  "token_admin", 404)
r(E, "E09 Error 401 sin token", "DELETE", "/api/mascotas/{{id_rocky}}", None,
  None, 401)
r(E, "E06 Registrar mascota sin citas", "POST", "/api/mascotas",
  {"nombre": "Pio", "especie": "ave", "sexo": "macho", "dueno_id": "{{id_ana}}"},
  "token_rec", 201, guardar("id_pio", "id"))
r(E, "E09 Eliminar mascota", "DELETE", "/api/mascotas/{{id_pio}}", None,
  "token_admin", 204)


def cuerpo_json(cuerpo):
    # Los ids van como {{variable}} sin comillas para que lleguen como numero.
    texto = json.dumps(cuerpo, indent=2, ensure_ascii=False)
    for var in ["id_ana", "id_luis", "id_vet", "id_vet2", "id_rocky", "id_michi"]:
        texto = texto.replace(f'"{{{{{var}}}}}"', f"{{{{{var}}}}}")
    return texto


def peticion(nombre, metodo, ruta, cuerpo, token, estado, extra, pre):
    ruta_sin_query, _, query = ruta.partition("?")
    url = {
        "raw": "{{baseUrl}}" + ruta,
        "host": ["{{baseUrl}}"],
        "path": [p for p in ruta_sin_query.split("/") if p],
    }
    if query:
        url["query"] = [{"key": k, "value": v} for k, v in
                        (par.split("=", 1) for par in query.split("&"))]
    req = {"method": metodo, "header": [], "url": url}
    if token:
        req["auth"] = {"type": "bearer",
                       "bearer": [{"key": "token", "value": "{{" + token + "}}",
                                   "type": "string"}]}
    else:
        req["auth"] = {"type": "noauth"}
    if cuerpo is not None:
        req["header"].append({"key": "Content-Type", "value": "application/json"})
        req["body"] = {"mode": "raw", "raw": cuerpo_json(cuerpo),
                       "options": {"raw": {"language": "json"}}}
    prueba = f"pm.test('Responde {estado}', () => pm.response.to.have.status({estado}));"
    eventos = [{"listen": "test", "script": {
        "type": "text/javascript", "exec": (prueba + "\n" + extra).strip().split("\n")}}]
    if pre:
        eventos.insert(0, {"listen": "prerequest", "script": {
            "type": "text/javascript", "exec": pre.strip().split("\n")}})
    return {"name": nombre, "event": eventos, "request": req}


carpetas = {}
for carpeta, *resto in P:
    carpetas.setdefault(carpeta, []).append(peticion(*resto))

variables = ["sufijo", "dia_cita", "cita_1030", "cita_1100", "cita_1200",
             "token_admin", "token_ana", "token_luis", "token_vet", "token_vet2",
             "token_rec", "id_ana", "id_luis", "id_vet", "id_vet2", "id_rocky",
             "id_michi", "id_cita", "id_cita_michi", "id_cita_cancelar", "id_pio"]

coleccion = {
    "info": {
        "_postman_id": str(uuid.uuid5(uuid.NAMESPACE_URL, "veterinaria-api")),
        "name": "Veterinaria API (Caso 2)",
        "description": (
            "Endpoints E01-E16 de la especificacion Grothe_Gonzalez_EspecAPI.xlsx.\n\n"
            "Correr en orden (Run collection): el login guarda los tokens y cada "
            "creacion guarda su id en variables de la coleccion. Cada peticion "
            "verifica el codigo de estado esperado en la pestana Tests.\n\n"
            "baseUrl por defecto: http://localhost:8080. Para AWS cambiar baseUrl y "
            "admin_clave en la pestana Variables de la coleccion."),
        "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json",
    },
    "item": [{"name": n, "item": items} for n, items in carpetas.items()],
    "variable": [{"key": "baseUrl", "value": "http://localhost:8080"},
                 {"key": "admin_clave", "value": "admin12345"}]
    + [{"key": v, "value": ""} for v in variables],
}

with open(SALIDA, "w", encoding="utf-8") as f:
    json.dump(coleccion, f, indent=2, ensure_ascii=False)
print(f"{len(P)} peticiones -> {SALIDA}")
