"""Errores de la API con el formato del contrato:
{"error": "...", "codigo": 400, "detalles": {...}}"""

import json
import sys
import traceback

import pymongo.errors
import pymysql.err
from flask import jsonify, request
from werkzeug.exceptions import HTTPException


class ApiError(Exception):
    def __init__(self, codigo, mensaje, detalles=None):
        super().__init__(mensaje)
        self.codigo = codigo
        self.mensaje = mensaje
        self.detalles = detalles


def respuesta(estado, cuerpo=None, cabeceras=None):
    if estado == 204:
        r = jsonify({})
        r.set_data(b"")
    else:
        r = jsonify(cuerpo)
    r.status_code = estado
    for k, v in (cabeceras or {}).items():
        r.headers[k] = v
    return r


def _error_json(codigo, mensaje, detalles=None):
    cuerpo = {"error": mensaje, "codigo": codigo}
    if detalles:
        cuerpo["detalles"] = detalles
    return respuesta(codigo, cuerpo)


def leer_json():
    """Cuerpo como objeto JSON. Un cuerpo vacio cuenta como {}."""
    crudo = request.get_data()
    try:
        texto = crudo.decode("utf-8")
    except UnicodeDecodeError:
        raise ApiError(400, "El cuerpo debe ser un objeto JSON valido")
    if not texto.strip():
        return {}
    try:
        datos = json.loads(texto)
    except ValueError:
        datos = None
    if isinstance(datos, dict):
        return datos
    raise ApiError(400, "El cuerpo debe ser un objeto JSON valido")


def registrar_manejadores(app):
    @app.errorhandler(ApiError)
    def _api(e):
        return _error_json(e.codigo, e.mensaje, e.detalles)

    @app.errorhandler(HTTPException)
    def _http(e):
        if e.code == 404:
            return _error_json(404, "Ruta no encontrada")
        if e.code == 405:
            return _error_json(405, "Metodo no permitido")
        return _error_json(e.code or 500, e.name)

    @app.errorhandler(pymongo.errors.PyMongoError)
    def _mongo(e):
        print("MongoDB no disponible: %s" % e, file=sys.stderr)
        return _error_json(503, "Servicio de documentos no disponible")

    @app.errorhandler(pymysql.err.OperationalError)
    @app.errorhandler(pymysql.err.InterfaceError)
    def _mysql(e):
        print("MySQL no disponible: %s" % e, file=sys.stderr)
        return _error_json(503, "Base relacional no disponible")

    @app.errorhandler(Exception)
    def _otro(e):
        traceback.print_exc()
        return _error_json(500, "Error interno del servidor")
