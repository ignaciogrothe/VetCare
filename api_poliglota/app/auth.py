import os
from datetime import datetime, timedelta, timezone

import bcrypt
import jwt
from flask import request

from .db import uno
from .errores import ApiError

SEGUNDOS_TOKEN = 3600


def _secreto():
    return os.environ["JWT_SECRET"]


def hash_clave(clave):
    return bcrypt.hashpw(clave.encode("utf-8"), bcrypt.gensalt()).decode("ascii")


def clave_correcta(clave, hash_):
    try:
        return bcrypt.checkpw(clave.encode("utf-8"), hash_.encode("ascii"))
    except ValueError:
        return False


def usuario_desde_fila(f):
    return {
        "id": f["id"],
        "nombre": f["nombre"],
        "email": f["email"],
        "telefono": f["telefono"],
        "rol": f["rol"],
        "activo": bool(f["activo"]),
        "clave_hash": f["clave_hash"],
    }


def usuario_json(u):
    """La clave nunca sale en ninguna respuesta."""
    return {k: u[k] for k in ("id", "nombre", "email", "telefono", "rol", "activo")}


def buscar_por_email(email):
    f = uno("SELECT * FROM usuarios WHERE email = %s", (email,))
    return usuario_desde_fila(f) if f else None


def emitir_token(u):
    ahora = datetime.now(timezone.utc)
    return jwt.encode(
        {
            "sub": str(u["id"]),
            "rol": u["rol"],
            "iat": ahora,
            "exp": ahora + timedelta(seconds=SEGUNDOS_TOKEN),
        },
        _secreto(),
        algorithm="HS256",
    )


def autenticar(roles=None):
    """401 si falta o es invalido el token; 403 si el rol no esta en `roles`.
    El rol se lee de la base, no del token: un cambio de rol o una baja
    surten efecto de inmediato."""
    cabecera = request.headers.get("Authorization", "")
    if not cabecera.startswith("Bearer "):
        raise ApiError(401, "Falta el token de acceso")
    try:
        datos = jwt.decode(cabecera[7:].strip(), _secreto(), algorithms=["HS256"])
    except jwt.ExpiredSignatureError:
        raise ApiError(401, "El token expiro")
    except jwt.InvalidTokenError:
        raise ApiError(401, "Token invalido")
    sub = datos.get("sub", "")
    f = uno("SELECT * FROM usuarios WHERE id = %s", (int(sub),)) if sub.isdigit() else None
    if not f:
        raise ApiError(401, "Token invalido")
    usuario = usuario_desde_fila(f)
    if not usuario["activo"]:
        raise ApiError(401, "Token invalido")
    if roles is not None and usuario["rol"] not in roles:
        raise ApiError(403, "No tiene permiso para esta operacion")
    return usuario
