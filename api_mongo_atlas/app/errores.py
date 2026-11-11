"""
Manejo centralizado de errores.

Una API nunca debe responder una pagina HTML de error ni una traza de Python.
Todo error sale por aqui, en JSON y en espanol, con la misma forma siempre:

    { "error": "...", "detalle": { ... } }
"""

from flask import jsonify
from pymongo.errors import DuplicateKeyError, ServerSelectionTimeoutError
from werkzeug.exceptions import HTTPException


def registrar_errores(app):

    @app.errorhandler(400)
    def _400(e):
        detalle = getattr(e, "detalle", None)
        cuerpo = {"error": getattr(e, "mensaje", "La peticion no es valida.")}
        if detalle:
            cuerpo["detalle"] = detalle
        return jsonify(cuerpo), 400

    @app.errorhandler(404)
    def _404(e):
        return jsonify({"error": getattr(e, "mensaje", "El recurso no existe.")}), 404

    @app.errorhandler(405)
    def _405(e):
        return jsonify({"error": "Metodo no permitido en esta ruta."}), 405

    @app.errorhandler(409)
    def _409(e):
        return jsonify({"error": getattr(e, "mensaje", "Conflicto con el estado actual.")}), 409

    @app.errorhandler(415)
    def _415(e):
        return jsonify({
            "error": "El cuerpo debe ser JSON con la cabecera "
                     "Content-Type: application/json."
        }), 415

    @app.errorhandler(DuplicateKeyError)
    def _duplicado(e):
        # Un indice unique de Mongo rechazo el documento.
        return jsonify({"error": "Ya existe un registro con ese valor unico."}), 409

    @app.errorhandler(ServerSelectionTimeoutError)
    def _sin_base(e):
        # Atlas no respondio: casi siempre es la lista de IP permitidas.
        return jsonify({
            "error": "No se pudo conectar con la base de datos.",
            "detalle": "Revise MONGO_URI y que su IP este autorizada en "
                       "Atlas (Network Access)."
        }), 503

    @app.errorhandler(HTTPException)
    def _http(e):
        return jsonify({"error": e.description}), e.code

    @app.errorhandler(Exception)
    def _inesperado(e):
        # Red de seguridad: el cliente nunca ve la traza.
        app.logger.exception("Error no controlado")
        return jsonify({"error": "Error interno del servidor."}), 500
