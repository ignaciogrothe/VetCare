"""Endpoints E01-E16 del Caso 2 (veterinaria), partidos en dos motores:
usuarios, mascotas y citas en MySQL; atenciones (con su receta anidada)
en MongoDB, referenciando citas.id mediante el campo cita_id."""

import re
from datetime import datetime, timezone

import pymysql.err
from flask import Blueprint, request
from pymongo.errors import DuplicateKeyError

from . import auth
from .db import consulta, ejecutar, mongo, uno
from .errores import ApiError, leer_json, respuesta
from .validacion import Validador, ValidadorQuery, a_iso, fecha_hora_mysql

bp = Blueprint("api", __name__)

ESPECIES = ["perro", "gato", "ave", "conejo", "otro"]
SEXOS = ["macho", "hembra"]
ESTADOS_CITA = ["agendada", "atendida", "cancelada"]
ROLES_PERSONAL = ["veterinario", "recepcionista", "administrador"]

PERSONAL = {"veterinario", "recepcionista", "administrador"}
RECEPCION = {"recepcionista", "administrador"}
SOLO_ADMIN = {"administrador"}
SOLO_VET = {"veterinario"}
CLINICO = {"dueno", "veterinario", "administrador"}  # ven diagnosticos

ERR_DUPLICADO = 1062
ERR_FK_CON_HIJOS = 1451
NO_ADMITE = "La cita no admite una atencion"


def _id_ruta(texto):
    """Un id no numerico o gigante se trata como inexistente (404)."""
    return int(texto) if re.fullmatch(r"[0-9]{1,10}", texto) else None


def _es_dueno(u):
    return u["rol"] == "dueno"


def _paginar(q):
    return (
        q.entero_texto("pagina", 1),
        q.entero_texto("tamano", 20, 1, 50),
    )


# ---------------------------------------------------------------- Salud

@bp.get("/api/salud")
def salud():
    """Comprueba que responden los dos motores."""
    consulta("SELECT 1 AS ok")
    mongo().command("ping")
    return respuesta(200, {"estado": "ok", "mysql": "ok", "mongo": "ok"})


# ----------------------------------------------------------------- Auth

@bp.post("/api/auth/login")  # E01
def login():
    v = Validador(leer_json())
    email = v.email("email")
    clave = v.texto("clave", True, 1, 200)
    v.verificar()
    u = auth.buscar_por_email(email)
    valido = u is not None and u["activo"] and auth.clave_correcta(clave, u["clave_hash"])
    if not valido:
        raise ApiError(401, "Credenciales invalidas")
    return respuesta(200, {
        "access_token": auth.emitir_token(u),
        "token_type": "Bearer",
        "expira_en": auth.SEGUNDOS_TOKEN,
        "usuario": {"id": u["id"], "nombre": u["nombre"], "rol": u["rol"]},
    })


@bp.post("/api/auth/registro")  # E02: el rol siempre es "dueno"
def registro():
    u = _crear_usuario(Validador(leer_json()), "dueno")
    return respuesta(201, auth.usuario_json(u), {"Location": "/api/auth/yo"})


@bp.get("/api/auth/yo")
def yo():
    return respuesta(200, auth.usuario_json(auth.autenticar()))


@bp.post("/api/usuarios")  # E03
def crear_personal():
    auth.autenticar(SOLO_ADMIN)
    v = Validador(leer_json())
    v.solo_campos({"nombre", "email", "clave", "rol", "telefono"})
    rol = v.opcion("rol", ROLES_PERSONAL, obligatorio=True)
    u = _crear_usuario(v, rol)
    return respuesta(201, auth.usuario_json(u), {"Location": "/api/usuarios/%d" % u["id"]})


def _crear_usuario(v, rol):
    nombre = v.texto("nombre", True, 2, 80)
    email = v.email("email")
    clave = v.texto("clave", True, 8, 200)
    telefono = v.texto("telefono", maximo=15)
    if telefono is not None and not re.fullmatch(r"[0-9]{8,15}", telefono):
        v.error("telefono", "Solo digitos, entre 8 y 15.")
    v.verificar()
    if auth.buscar_por_email(email):
        raise ApiError(409, "El email ya esta registrado")
    try:
        ejecutar(
            "INSERT INTO usuarios (nombre, email, clave_hash, rol, telefono) "
            "VALUES (%s, %s, %s, %s, %s)",
            (nombre, email, auth.hash_clave(clave), rol, telefono),
        )
    except pymysql.err.IntegrityError as e:
        if e.args[0] == ERR_DUPLICADO:
            raise ApiError(409, "El email ya esta registrado")
        raise
    return auth.buscar_por_email(email)


@bp.get("/api/veterinarios")  # E04: solo id y nombre
def veterinarios():
    auth.autenticar(PERSONAL)
    filas = consulta(
        "SELECT id, nombre FROM usuarios WHERE rol = 'veterinario' "
        "AND activo = TRUE ORDER BY nombre"
    )
    return respuesta(200, [{"id": f["id"], "nombre": f["nombre"]} for f in filas])


# ------------------------------------------------------------- Mascotas

SQL_MASCOTA = (
    "SELECT m.id, m.nombre, m.especie, m.sexo, m.fecha_nacimiento, m.peso_kg, "
    "m.dueno_id, u.nombre AS dueno_nombre "
    "FROM mascotas m JOIN usuarios u ON u.id = m.dueno_id"
)


def _mascota_json(f):
    return {
        "id": f["id"],
        "nombre": f["nombre"],
        "especie": f["especie"],
        "sexo": f["sexo"],
        "fecha_nacimiento": f["fecha_nacimiento"].isoformat() if f["fecha_nacimiento"] else None,
        "peso_kg": float(f["peso_kg"]) if f["peso_kg"] is not None else None,
        "dueno": {"id": f["dueno_id"], "nombre": f["dueno_nombre"]},
    }


def _buscar_mascota(id_):
    return uno(SQL_MASCOTA + " WHERE m.id = %s", (id_,))


def _mascota_existente(id_ruta):
    id_ = _id_ruta(id_ruta)
    fila = _buscar_mascota(id_) if id_ is not None else None
    if not fila:
        raise ApiError(404, "La mascota no existe")
    return fila


@bp.get("/api/mascotas")  # E05
def listar_mascotas():
    u = auth.autenticar()
    q = ValidadorQuery(request.args.to_dict())
    especie = q.opcion("especie", ESPECIES)
    pagina, tamano = _paginar(q)
    q.verificar()
    filtros, params = [], []
    if _es_dueno(u):
        filtros.append("m.dueno_id = %s")
        params.append(u["id"])
    if especie:
        filtros.append("m.especie = %s")
        params.append(especie)
    where = (" WHERE " + " AND ".join(filtros)) if filtros else ""
    total = uno("SELECT COUNT(*) AS n FROM mascotas m" + where, params)["n"]
    filas = consulta(
        SQL_MASCOTA + where + " ORDER BY m.nombre, m.id LIMIT %s OFFSET %s",
        params + [tamano, (pagina - 1) * tamano],
    )
    return respuesta(200, {
        "items": [_mascota_json(f) for f in filas],
        "pagina": pagina, "tamano": tamano, "total": total,
    })


@bp.post("/api/mascotas")  # E06
def crear_mascota():
    auth.autenticar(RECEPCION)
    v = Validador(leer_json())
    v.solo_campos({"nombre", "especie", "sexo", "fecha_nacimiento", "peso_kg", "dueno_id"})
    nombre = v.texto("nombre", True, 2, 60)
    especie = v.opcion("especie", ESPECIES, True)
    sexo = v.opcion("sexo", SEXOS, True)
    nacimiento = v.fecha_pasada("fecha_nacimiento")
    peso = v.positivo("peso_kg", 200)
    dueno_id = v.entero("dueno_id", True)
    v.verificar()
    if not uno("SELECT id FROM usuarios WHERE id = %s AND rol = 'dueno'", (dueno_id,)):
        raise ApiError(422, "dueno_id invalido")
    id_, _ = ejecutar(
        "INSERT INTO mascotas (nombre, especie, sexo, fecha_nacimiento, peso_kg, dueno_id) "
        "VALUES (%s, %s, %s, %s, %s, %s)",
        (nombre, especie, sexo, nacimiento, peso, dueno_id),
    )
    return respuesta(201, _mascota_json(_buscar_mascota(id_)),
                     {"Location": "/api/mascotas/%d" % id_})


@bp.get("/api/mascotas/<id_ruta>")  # E07
def ver_mascota(id_ruta):
    u = auth.autenticar()
    fila = _mascota_existente(id_ruta)
    if _es_dueno(u) and fila["dueno_id"] != u["id"]:
        raise ApiError(403, "La mascota no le pertenece")
    return respuesta(200, _mascota_json(fila))


@bp.patch("/api/mascotas/<id_ruta>")  # E08: solo nombre y peso
def modificar_mascota(id_ruta):
    auth.autenticar(RECEPCION)
    fila = _mascota_existente(id_ruta)
    v = Validador(leer_json())
    v.solo_campos({"nombre", "peso_kg"})
    if not v.datos:
        v.error("cuerpo", "Envie al menos nombre o peso_kg.")
    nombre = v.texto("nombre", minimo=2, maximo=60)
    if v.tiene("nombre") and v.datos["nombre"] is None:
        v.error("nombre", "No puede ser nulo.")
    peso = v.positivo("peso_kg", 200)
    v.verificar()
    cambios, params = [], []
    if v.tiene("nombre"):
        cambios.append("nombre = %s")
        params.append(nombre)
    if v.tiene("peso_kg"):
        cambios.append("peso_kg = %s")
        params.append(peso)
    ejecutar("UPDATE mascotas SET " + ", ".join(cambios) + " WHERE id = %s",
             params + [fila["id"]])
    return respuesta(200, _mascota_json(_buscar_mascota(fila["id"])))


@bp.delete("/api/mascotas/<id_ruta>")  # E09: 409 si tiene citas
def eliminar_mascota(id_ruta):
    auth.autenticar(SOLO_ADMIN)
    fila = _mascota_existente(id_ruta)
    con_citas = "No se puede eliminar: la mascota tiene citas"
    if uno("SELECT 1 FROM citas WHERE mascota_id = %s LIMIT 1", (fila["id"],)):
        raise ApiError(409, con_citas)
    try:
        ejecutar("DELETE FROM mascotas WHERE id = %s", (fila["id"],))
    except pymysql.err.IntegrityError as e:
        if e.args[0] == ERR_FK_CON_HIJOS:
            raise ApiError(409, con_citas)
        raise
    return respuesta(204)


# ---------------------------------------------------------------- Citas

SQL_CITA = (
    "SELECT c.id, c.mascota_id, c.veterinario_id, c.fecha_hora, c.motivo, c.estado, "
    "m.nombre AS mascota_nombre, m.dueno_id, v.nombre AS veterinario_nombre "
    "FROM citas c JOIN mascotas m ON m.id = c.mascota_id "
    "JOIN usuarios v ON v.id = c.veterinario_id"
)


def _cita_json(f):
    """Detalle de una cita: nunca incluye diagnostico."""
    return {
        "id": f["id"],
        "mascota": {"id": f["mascota_id"], "nombre": f["mascota_nombre"]},
        "veterinario": {"id": f["veterinario_id"], "nombre": f["veterinario_nombre"]},
        "fecha_hora": a_iso(f["fecha_hora"]),
        "motivo": f["motivo"],
        "estado": f["estado"],
    }


def _buscar_cita(id_):
    return uno(SQL_CITA + " WHERE c.id = %s", (id_,))


def _cita_existente(id_ruta):
    id_ = _id_ruta(id_ruta)
    fila = _buscar_cita(id_) if id_ is not None else None
    if not fila:
        raise ApiError(404, "La cita no existe")
    return fila


def _verificar_dueno_de_cita(u, cita):
    if _es_dueno(u) and cita["dueno_id"] != u["id"]:
        raise ApiError(403, "La cita no corresponde a una mascota suya")


def _verificar_vet_de_cita(u, cita):
    if cita["veterinario_id"] != u["id"]:
        raise ApiError(403, "Solo el veterinario asignado puede hacer esto")


@bp.get("/api/citas")  # E10
def listar_citas():
    u = auth.autenticar()
    q = ValidadorQuery(request.args.to_dict())
    fecha = q.fecha("fecha")
    estado = q.opcion("estado", ESTADOS_CITA)
    pagina, tamano = _paginar(q)
    q.verificar()
    filtros, params = [], []
    if _es_dueno(u):
        filtros.append("m.dueno_id = %s")
        params.append(u["id"])
    if fecha:
        filtros.append("c.fecha_hora >= %s AND c.fecha_hora < %s + INTERVAL 1 DAY")
        params += [fecha, fecha]
    if estado:
        filtros.append("c.estado = %s")
        params.append(estado)
    where = (" WHERE " + " AND ".join(filtros)) if filtros else ""
    desde = " FROM citas c JOIN mascotas m ON m.id = c.mascota_id"
    total = uno("SELECT COUNT(*) AS n" + desde + where, params)["n"]
    filas = consulta(
        "SELECT c.id, c.mascota_id, c.veterinario_id, c.fecha_hora, c.motivo, c.estado"
        + desde + where + " ORDER BY c.fecha_hora, c.id LIMIT %s OFFSET %s",
        params + [tamano, (pagina - 1) * tamano],
    )
    return respuesta(200, {
        "items": [{
            "id": f["id"], "mascota_id": f["mascota_id"],
            "veterinario_id": f["veterinario_id"],
            "fecha_hora": a_iso(f["fecha_hora"]),
            "motivo": f["motivo"], "estado": f["estado"],
        } for f in filas],
        "pagina": pagina, "tamano": tamano, "total": total,
    })


@bp.post("/api/citas")  # E11
def crear_cita():
    auth.autenticar(RECEPCION)
    v = Validador(leer_json())
    v.solo_campos({"mascota_id", "veterinario_id", "fecha_hora", "motivo"})
    mascota_id = v.entero("mascota_id", True)
    vet_id = v.entero("veterinario_id", True)
    fecha = v.fecha_hora_agenda("fecha_hora")
    motivo = v.texto("motivo", True, 3, 200)
    v.verificar()
    mascota = uno("SELECT 1 AS x FROM mascotas WHERE id = %s", (mascota_id,))
    vet = uno("SELECT 1 AS x FROM usuarios WHERE id = %s AND rol = 'veterinario' "
              "AND activo = TRUE", (vet_id,))
    if not mascota or not vet:
        raise ApiError(422, "Referencia invalida")
    ocupado = "El veterinario no esta disponible en ese horario"
    fecha_sql = fecha_hora_mysql(fecha)
    if uno("SELECT 1 AS x FROM citas WHERE veterinario_id = %s AND fecha_hora = %s "
           "AND estado = 'agendada'", (vet_id, fecha_sql)):
        raise ApiError(409, ocupado)
    try:
        id_, _ = ejecutar(
            "INSERT INTO citas (mascota_id, veterinario_id, fecha_hora, motivo) "
            "VALUES (%s, %s, %s, %s)", (mascota_id, vet_id, fecha_sql, motivo))
    except pymysql.err.IntegrityError as e:
        # dos recepcionistas agendando el mismo bloque a la vez: lo ataja el indice unico
        if e.args[0] == ERR_DUPLICADO:
            raise ApiError(409, ocupado)
        raise
    return respuesta(201, _cita_json(_buscar_cita(id_)), {"Location": "/api/citas/%d" % id_})


@bp.get("/api/citas/<id_ruta>")  # E12
def ver_cita(id_ruta):
    u = auth.autenticar()
    cita = _cita_existente(id_ruta)
    _verificar_dueno_de_cita(u, cita)
    return respuesta(200, _cita_json(cita))


@bp.post("/api/citas/<id_ruta>/cancelacion")  # E13
def cancelar_cita(id_ruta):
    auth.autenticar(RECEPCION)
    cita = _cita_existente(id_ruta)
    _, n = ejecutar("UPDATE citas SET estado = 'cancelada' "
                    "WHERE id = %s AND estado = 'agendada'", (cita["id"],))
    if n == 0:
        raise ApiError(409, "La cita no se puede cancelar en su estado actual")
    return respuesta(200, _cita_json(_buscar_cita(cita["id"])))


# ------------------------------------------- Atencion (documento en Mongo)

def _atencion_json(d):
    return {
        "cita_id": d["cita_id"],
        "diagnostico": d["diagnostico"],
        "tratamiento": d.get("tratamiento"),
        "medicamentos": d.get("medicamentos", []),
        "fecha_registro": a_iso(d["fecha_registro"]),
    }


def _atencion_de(cita_id):
    return mongo().atenciones.find_one({"cita_id": cita_id}, {"_id": 0})


@bp.post("/api/citas/<id_ruta>/atencion")  # E14
def registrar_atencion(id_ruta):
    u = auth.autenticar(SOLO_VET)
    cita = _cita_existente(id_ruta)
    _verificar_vet_de_cita(u, cita)
    v = Validador(leer_json())
    v.solo_campos({"diagnostico", "tratamiento", "medicamentos"})
    diagnostico = v.texto("diagnostico", True, 5, 2000)
    tratamiento = v.texto("tratamiento", maximo=2000)
    medicamentos = v.medicamentos("medicamentos") or []
    v.verificar()

    cita_id = cita["id"]
    # 1) La transicion agendada -> atendida en MySQL es la guarda: solo una
    #    peticion la gana, asi que no hay dos atenciones para la misma cita.
    _, n = ejecutar("UPDATE citas SET estado = 'atendida' "
                    "WHERE id = %s AND estado = 'agendada'", (cita_id,))
    if n == 0:
        raise ApiError(409, NO_ADMITE)
    # 2) El documento va a Mongo. No existe transaccion que abarque los dos
    #    motores: si falla, se compensa devolviendo la cita a "agendada".
    doc = {
        "cita_id": cita_id,
        "diagnostico": diagnostico,
        "tratamiento": tratamiento,
        "medicamentos": medicamentos,
        "fecha_registro": datetime.now(timezone.utc).replace(microsecond=0),
    }
    try:
        mongo().atenciones.insert_one(doc)
    except DuplicateKeyError:
        raise ApiError(409, NO_ADMITE)
    except Exception:
        ejecutar("UPDATE citas SET estado = 'agendada' "
                 "WHERE id = %s AND estado = 'atendida'", (cita_id,))
        raise
    return respuesta(201, _atencion_json(doc),
                     {"Location": "/api/citas/%d/atencion" % cita_id})


@bp.get("/api/citas/<id_ruta>/atencion")  # E15: la recepcionista recibe 403
def ver_atencion(id_ruta):
    u = auth.autenticar(CLINICO)
    cita = _cita_existente(id_ruta)
    _verificar_dueno_de_cita(u, cita)
    d = _atencion_de(cita["id"])
    if not d:
        raise ApiError(404, "La cita no tiene atencion registrada")
    return respuesta(200, _atencion_json(d))


@bp.patch("/api/citas/<id_ruta>/atencion")  # E16: medicamentos reemplaza la receta
def corregir_atencion(id_ruta):
    u = auth.autenticar(SOLO_VET)
    cita = _cita_existente(id_ruta)
    _verificar_vet_de_cita(u, cita)
    if not _atencion_de(cita["id"]):
        raise ApiError(404, "La cita no tiene atencion registrada")
    v = Validador(leer_json())
    v.solo_campos({"diagnostico", "tratamiento", "medicamentos"})
    if not v.datos:
        v.error("cuerpo", "Envie al menos un campo a corregir.")
    diagnostico = v.texto("diagnostico", minimo=5, maximo=2000)
    if v.tiene("diagnostico") and v.datos["diagnostico"] is None:
        v.error("diagnostico", "No puede ser nulo.")
    tratamiento = v.texto("tratamiento", maximo=2000)
    medicamentos = v.medicamentos("medicamentos")
    v.verificar()
    cambios = {}
    if v.tiene("diagnostico"):
        cambios["diagnostico"] = diagnostico
    if v.tiene("tratamiento"):
        cambios["tratamiento"] = tratamiento
    if medicamentos is not None:
        cambios["medicamentos"] = medicamentos
    if cambios:
        mongo().atenciones.update_one({"cita_id": cita["id"]}, {"$set": cambios})
    return respuesta(200, _atencion_json(_atencion_de(cita["id"])))


# -------------------------------- Endpoint que combina los dos motores

@bp.get("/api/mascotas/<id_ruta>/historial")
def historial(id_ruta):
    """Mascota y citas (MySQL) + atenciones (MongoDB) en una sola respuesta.
    Orden: primero MySQL, porque es quien dice si la mascota existe (404);
    solo entonces se consulta Mongo, con filtro y proyeccion. Una cita sin
    documento (o un documento huerfano) no rompe la respuesta."""
    u = auth.autenticar(CLINICO)
    m = _mascota_existente(id_ruta)
    if _es_dueno(u) and m["dueno_id"] != u["id"]:
        raise ApiError(403, "La mascota no le pertenece")
    citas = consulta(SQL_CITA + " WHERE c.mascota_id = %s ORDER BY c.fecha_hora, c.id",
                     (m["id"],))
    ids = [c["id"] for c in citas]
    atenciones = {}
    if ids:
        for d in mongo().atenciones.find({"cita_id": {"$in": ids}}, {"_id": 0}):
            atenciones[d["cita_id"]] = _atencion_json(d)
    return respuesta(200, {
        "mascota": _mascota_json(m),
        "citas": [dict(_cita_json(c), atencion=atenciones.get(c["id"])) for c in citas],
        "total_atenciones": len(atenciones),
    })
