"""
CRUD de atenciones clinicas (documentos en MongoDB).

    GET    /api/atenciones                        listar (filtros, proyeccion, paginacion)
    GET    /api/atenciones/<id>                   obtener una
    POST   /api/atenciones                        crear (409 si la cita ya tiene atencion)
    PUT    /api/atenciones/<id>                   actualizar (parcial)
    DELETE /api/atenciones/<id>                   eliminar
    GET    /api/atenciones/resumen/medicamentos   agregacion sobre el arreglo anidado

Documento:
    { cita_id, diagnostico, tratamiento, medicamentos: [{medicamento, dosis,
      duracion_dias}], fecha_registro, actualizado_en }
"""

import re
from datetime import datetime, timedelta, timezone

from flask import Blueprint, jsonify, request
from pymongo import ASCENDING, DESCENDING, ReturnDocument
from pymongo.errors import DuplicateKeyError

from ..db import obtener_db
from ..respuestas import cuerpo_json, fallar
from ..serializacion import a_json, a_object_id, ahora, lista_a_json
from ..validacion import validar_atencion

bp = Blueprint("atenciones", __name__, url_prefix="/api/atenciones")

ORDENES_VALIDOS = {"fecha_registro", "cita_id"}

# Proyeccion del listado: solo lo necesario para una tabla. El detalle
# completo (tratamiento, dosis) se pide con GET /api/atenciones/<id>.
PROYECCION_LISTA = {
    "cita_id": 1, "diagnostico": 1, "fecha_registro": 1,
    "medicamentos.medicamento": 1,
}


def _buscar_o_404(coleccion, id_texto):
    oid = a_object_id(id_texto)
    if oid is None:
        fallar(400, f"El identificador '{id_texto}' no tiene un formato valido.")
    documento = coleccion.find_one({"_id": oid})
    if documento is None:
        fallar(404, "No existe una atencion con ese identificador.")
    return oid, documento


def _fecha(parametro):
    """Lee ?desde=AAAA-MM-DD / ?hasta=AAAA-MM-DD; None si no viene."""
    valor = request.args.get(parametro)
    if not valor:
        return None
    try:
        return datetime.strptime(valor, "%Y-%m-%d").replace(tzinfo=timezone.utc)
    except ValueError:
        fallar(400, f"El parametro {parametro} debe tener formato AAAA-MM-DD.")


def _entero_param(nombre, defecto, minimo=1, maximo=None):
    valor = request.args.get(nombre)
    if valor is None or valor == "":
        return defecto
    if not re.fullmatch(r"[0-9]+", valor) or int(valor) < minimo or (
        maximo is not None and int(valor) > maximo
    ):
        fallar(400, f"El parametro {nombre} debe ser un entero"
                    + (f" entre {minimo} y {maximo}." if maximo else f" mayor o igual a {minimo}."))
    return int(valor)


# ---------------------------------------------------------------- LISTAR
@bp.get("")
def listar():
    """
    Filtros por query string (todos se resuelven en MongoDB, no en Python):
        ?cita_id=12
        ?buscar=otitis            en diagnostico o tratamiento
        ?medicamento=amoxi        dentro del arreglo medicamentos
        ?desde=2026-11-01&hasta=2026-11-30
        ?orden=fecha_registro&dir=desc
        ?pagina=1&tam=10
    """
    db = obtener_db()
    filtro = {}

    if request.args.get("cita_id"):
        filtro["cita_id"] = _entero_param("cita_id", None)

    if buscar := request.args.get("buscar"):
        # re.escape: el texto del usuario se busca literal, no como regex.
        patron = {"$regex": re.escape(buscar), "$options": "i"}
        filtro["$or"] = [{"diagnostico": patron}, {"tratamiento": patron}]

    if medicamento := request.args.get("medicamento"):
        # $elemMatch consulta DENTRO del arreglo anidado.
        filtro["medicamentos"] = {"$elemMatch": {
            "medicamento": {"$regex": re.escape(medicamento), "$options": "i"}}}

    desde, hasta = _fecha("desde"), _fecha("hasta")
    if desde or hasta:
        rango = {}
        if desde:
            rango["$gte"] = desde
        if hasta:
            rango["$lt"] = hasta + timedelta(days=1)   # "hasta" incluye ese dia
        filtro["fecha_registro"] = rango

    campo = request.args.get("orden", "fecha_registro")
    if campo not in ORDENES_VALIDOS:
        fallar(400, f"No se puede ordenar por '{campo}'.",
               {"validos": sorted(ORDENES_VALIDOS)})
    direccion = ASCENDING if request.args.get("dir", "desc") == "asc" else DESCENDING

    pagina = _entero_param("pagina", 1)
    tam = _entero_param("tam", 10, 1, 100)

    total = db.atenciones.count_documents(filtro)
    cursor = (db.atenciones.find(filtro, PROYECCION_LISTA)
              .sort(campo, direccion)
              .skip((pagina - 1) * tam)
              .limit(tam))

    return jsonify({
        "datos": lista_a_json(cursor),
        "paginacion": {"pagina": pagina, "tam": tam, "total": total,
                       "paginas": (total + tam - 1) // tam},
    }), 200


# ------------------------------------------------------------- AGREGACION
@bp.get("/resumen/medicamentos")
def resumen_medicamentos():
    """
    Medicamentos mas recetados. Es la agregacion que en SQL seria un JOIN con
    una tabla de recetas: aqui $unwind abre el arreglo anidado y $group cuenta.
    """
    db = obtener_db()
    pipeline = [
        {"$unwind": "$medicamentos"},
        {"$group": {
            "_id": "$medicamentos.medicamento",
            "veces": {"$sum": 1},
            "dias_promedio": {"$avg": "$medicamentos.duracion_dias"},
        }},
        {"$sort": {"veces": -1, "_id": 1}},
        {"$limit": 20},
    ]
    filas = [
        {"medicamento": f["_id"], "veces": f["veces"],
         "dias_promedio": round(f["dias_promedio"], 1)}
        for f in db.atenciones.aggregate(pipeline)
    ]
    return jsonify({"datos": filas}), 200


# ---------------------------------------------------------------- OBTENER
@bp.get("/<id_atencion>")
def obtener(id_atencion):
    db = obtener_db()
    _, documento = _buscar_o_404(db.atenciones, id_atencion)
    return jsonify(a_json(documento)), 200


# ---------------------------------------------------------------- CREAR
@bp.post("")
def crear():
    db = obtener_db()
    limpio, errores = validar_atencion(cuerpo_json())
    if errores:
        fallar(400, "Hay errores en los datos enviados.", errores)

    limpio["fecha_registro"] = ahora()
    limpio["actualizado_en"] = limpio["fecha_registro"]

    # No se comprueba con un find previo: entre el find y el insert otra
    # peticion podria insertar la misma cita. El indice unico decide.
    try:
        resultado = db.atenciones.insert_one(limpio)
    except DuplicateKeyError:
        fallar(409, "La cita ya tiene una atencion registrada.")
    creada = db.atenciones.find_one({"_id": resultado.inserted_id})

    respuesta = jsonify(a_json(creada))
    respuesta.status_code = 201
    respuesta.headers["Location"] = f"/api/atenciones/{resultado.inserted_id}"
    return respuesta


# ---------------------------------------------------------------- ACTUALIZAR
@bp.put("/<id_atencion>")
def actualizar(id_atencion):
    db = obtener_db()
    oid, _ = _buscar_o_404(db.atenciones, id_atencion)

    limpio, errores = validar_atencion(cuerpo_json(), parcial=True)
    if errores:
        fallar(400, "Hay errores en los datos enviados.", errores)

    limpio["actualizado_en"] = ahora()
    # $set cambia solo esos campos; si viene "medicamentos" reemplaza la receta completa.
    actualizada = db.atenciones.find_one_and_update(
        {"_id": oid}, {"$set": limpio}, return_document=ReturnDocument.AFTER)
    return jsonify(a_json(actualizada)), 200


# ---------------------------------------------------------------- ELIMINAR
@bp.delete("/<id_atencion>")
def eliminar(id_atencion):
    db = obtener_db()
    oid, _ = _buscar_o_404(db.atenciones, id_atencion)
    db.atenciones.delete_one({"_id": oid})
    return "", 204
