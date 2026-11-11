"""
Traduccion entre documentos de MongoDB y JSON.

Este archivo existe por un solo motivo: el _id de Mongo es un ObjectId, y
jsonify() no sabe convertirlo. Si usted devuelve el documento tal cual, Flask
responde:

    TypeError: Object of type ObjectId is not JSON serializable

Es el primer error que se encuentra todo el mundo al conectar Flask con Mongo.
"""

from datetime import datetime, timezone

from bson import ObjectId
from bson.errors import InvalidId


def a_json(documento):
    """
    Convierte un documento de Mongo en algo que jsonify() pueda entregar.

    Cambia la clave '_id' (ObjectId) por 'id' (texto), porque hacia afuera la
    API entrega un identificador de texto y el cliente no tiene por que saber
    que la base de datos es MongoDB.
    """
    if documento is None:
        return None

    salida = {}
    for clave, valor in documento.items():
        if clave == "_id":
            salida["id"] = str(valor)
        elif isinstance(valor, ObjectId):
            salida[clave] = str(valor)
        elif isinstance(valor, datetime):
            salida[clave] = valor.astimezone(timezone.utc).isoformat()
        else:
            salida[clave] = valor
    return salida


def lista_a_json(documentos):
    return [a_json(d) for d in documentos]


def a_object_id(texto):
    """
    Convierte el id que llego en la URL a ObjectId.

    Devuelve None si el texto no tiene la forma de un ObjectId (24 caracteres
    hexadecimales). Quien llama decide si eso es un 400 o un 404.
    """
    try:
        return ObjectId(texto)
    except (InvalidId, TypeError):
        return None


def ahora():
    """Fecha y hora actual en UTC. Guardar siempre en UTC, convertir al mostrar."""
    return datetime.now(timezone.utc)
