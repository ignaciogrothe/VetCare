"""Acceso a los dos motores. Los hosts son nombres de servicio de Compose."""

import os

import pymysql
import pymysql.cursors
from flask import g
from pymongo import MongoClient

_cliente_mongo = None


def conexion():
    """Una conexion MySQL por peticion; se cierra al terminar."""
    if "db" not in g:
        g.db = pymysql.connect(
            host=os.environ.get("DB_HOST", "mysql"),
            port=int(os.environ.get("DB_PORT", "3306")),
            user=os.environ["DB_USER"],
            password=os.environ["DB_PASSWORD"],
            database=os.environ["DB_NAME"],
            charset="utf8mb4",
            cursorclass=pymysql.cursors.DictCursor,
            autocommit=True,
        )
    return g.db


def cerrar(_exc=None):
    db = g.pop("db", None)
    if db is not None:
        db.close()


def consulta(sql, params=()):
    """SELECT parametrizado: devuelve la lista de filas (dict)."""
    with conexion().cursor() as c:
        c.execute(sql, params)
        return c.fetchall()


def uno(sql, params=()):
    filas = consulta(sql, params)
    return filas[0] if filas else None


def ejecutar(sql, params=()):
    """INSERT/UPDATE/DELETE parametrizado: devuelve (ultimo_id, filas_afectadas)."""
    with conexion().cursor() as c:
        c.execute(sql, params)
        return c.lastrowid, c.rowcount


def mongo():
    """Base de documentos (la del MONGO_URI). Un solo cliente para todo el proceso."""
    global _cliente_mongo
    if _cliente_mongo is None:
        _cliente_mongo = MongoClient(
            os.environ["MONGO_URI"], serverSelectionTimeoutMS=5000
        )
    return _cliente_mongo.get_default_database()
