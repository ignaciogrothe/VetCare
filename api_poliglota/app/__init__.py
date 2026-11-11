"""Fabrica de la aplicacion. gunicorn arranca con `app:app`."""

import os
import sys
import time

import pymysql.err
import pymongo.errors
from flask import Flask

from . import auth
from .db import cerrar, consulta, ejecutar, mongo
from .errores import registrar_manejadores
from .rutas import bp


def crear_app():
    app = Flask(__name__)
    app.json.ensure_ascii = False   # tildes tal cual en el JSON
    app.json.sort_keys = False
    app.teardown_appcontext(cerrar)
    app.register_blueprint(bp)
    registrar_manejadores(app)
    return app


def _inicializar(app):
    """Indice unico en Mongo y administrador inicial en MySQL. Reintenta unos
    segundos por si una base aun no acepta conexiones."""
    for intento in range(30):
        try:
            with app.app_context():
                mongo().atenciones.create_index("cita_id", unique=True)
                if not consulta("SELECT 1 AS x FROM usuarios WHERE rol = 'administrador' LIMIT 1"):
                    email = os.environ.get("ADMIN_EMAIL", "admin@clinica.cl")
                    clave = os.environ["ADMIN_CLAVE"]
                    try:
                        ejecutar(
                            "INSERT INTO usuarios (nombre, email, clave_hash, rol) "
                            "VALUES ('Administrador', %s, %s, 'administrador')",
                            (email, auth.hash_clave(clave)),
                        )
                        print("Administrador inicial creado: %s" % email, flush=True)
                    except pymysql.err.IntegrityError:
                        pass  # otro worker lo creo primero
            return
        except (pymysql.err.OperationalError, pymongo.errors.PyMongoError) as e:
            print("Esperando las bases (%d/30): %s" % (intento + 1, e), file=sys.stderr, flush=True)
            time.sleep(1)


app = crear_app()
_inicializar(app)
