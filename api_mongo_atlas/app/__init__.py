"""
Fabrica de la aplicacion.

API de atenciones clinicas de la veterinaria sobre MongoDB (Atlas).
La coleccion `atenciones` tiene el mismo documento que el lado Mongo de la
API poliglota (api_poliglota): cita_id, diagnostico, tratamiento,
medicamentos[] y fecha_registro.
"""

from flask import Flask, jsonify

from .errores import registrar_errores


def crear_app(config=None):
    app = Flask(__name__, static_folder=None)

    from config import Config
    app.config.from_object(Config)
    if config:
        app.config.update(config)

    app.json.sort_keys = False
    app.json.ensure_ascii = False

    registrar_errores(app)

    from .rutas.atenciones import bp as bp_atenciones
    app.register_blueprint(bp_atenciones)

    @app.get("/api/salud")
    def salud():
        """Comprueba que la API responde y que la base de datos contesta."""
        from .db import probar_conexion
        ok, detalle = probar_conexion()
        return jsonify({
            "api": "ok",
            "base_de_datos": "ok" if ok else "sin conexion",
            "detalle": detalle,
            "motor": "MongoDB",
        }), (200 if ok else 503)

    return app
