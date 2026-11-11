"""
Ayudas compartidas por los blueprints para fallar de forma uniforme.
"""

from flask import abort, request
from werkzeug.exceptions import BadRequest, Conflict, NotFound

_CLASES = {400: BadRequest, 404: NotFound, 409: Conflict}


def fallar(codigo, mensaje, detalle=None):
    """
    Lanza un error HTTP llevando un mensaje en espanol y, opcionalmente, el
    detalle campo por campo. Los manejadores de errores.py los leen y arman
    el JSON de respuesta.
    """
    error = _CLASES[codigo]()
    error.mensaje = mensaje
    if detalle:
        error.detalle = detalle
    raise error


def cuerpo_json():
    """Devuelve el JSON del cuerpo, o falla con el codigo correcto."""
    if not request.is_json:
        abort(415)
    datos = request.get_json(silent=True)
    if datos is None:
        fallar(400, "El cuerpo no es JSON valido.")
    return datos
