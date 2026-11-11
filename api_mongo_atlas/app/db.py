"""
Conexion a MongoDB.

Una sola conexion para toda la aplicacion. PyMongo ya maneja internamente un
pool de conexiones, asi que NO hay que crear un MongoClient por cada peticion:
eso es el error de rendimiento mas comun al partir.
"""

from flask import current_app, g
from pymongo import MongoClient, ASCENDING, DESCENDING
from pymongo.errors import ServerSelectionTimeoutError

# El cliente se guarda a nivel de modulo porque debe sobrevivir entre peticiones.
_cliente = None


def obtener_cliente():
    """Devuelve el MongoClient, creandolo la primera vez."""
    global _cliente
    if _cliente is None:
        _cliente = MongoClient(
            current_app.config["MONGO_URI"],
            # Si Atlas no responde en 5 segundos, falla rapido en vez de colgarse.
            serverSelectionTimeoutMS=5000,
            tz_aware=True,
        )
    return _cliente


def obtener_db():
    """Devuelve la base de datos de esta peticion."""
    if "db" not in g:
        g.db = obtener_cliente()[current_app.config["MONGO_DB"]]
    return g.db


def probar_conexion():
    """
    Hace ping al servidor. Sirve para que el error de conexion aparezca al
    arrancar y no en la primera peticion de un alumno confundido.
    """
    try:
        obtener_cliente().admin.command("ping")
        return True, "conexion correcta"
    except ServerSelectionTimeoutError as e:
        return False, str(e)


def crear_indices():
    """
    Los indices se declaran una vez al arrancar. create_index es idempotente.
    """
    db = obtener_db()

    # Una sola atencion por cita: la regla la hace cumplir la base de datos.
    # Un POST repetido para la misma cita termina en DuplicateKeyError (409).
    db.atenciones.create_index([("cita_id", ASCENDING)], name="idx_cita", unique=True)

    # Listados y filtros por fecha, de la mas reciente a la mas antigua.
    db.atenciones.create_index([("fecha_registro", DESCENDING)], name="idx_fecha")

    # Busqueda por medicamento dentro del arreglo anidado.
    db.atenciones.create_index([("medicamentos.medicamento", ASCENDING)], name="idx_medicamento")
