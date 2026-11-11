"""
Configuracion de la aplicacion.

La cadena de conexion NUNCA va escrita en el codigo: lleva usuario y
contrasena. Va en el archivo .env, y .env va en el .gitignore.
"""

import os

from dotenv import load_dotenv

load_dotenv()          # lee el archivo .env si existe


class Config:
    # Cadena de conexion de Atlas. Formato:
    #   mongodb+srv://USUARIO:CLAVE@cluster0.xxxxx.mongodb.net/?retryWrites=true&w=majority
    # Por defecto apunta a un MongoDB local, para poder trabajar sin internet.
    MONGO_URI = os.getenv("MONGO_URI", "mongodb://localhost:27017")

    # Nombre de la base de datos dentro del cluster.
    MONGO_DB = os.getenv("MONGO_DB", "veterinaria")

    JSON_AS_ASCII = False      # para que las tildes salgan tal cual en el JSON
