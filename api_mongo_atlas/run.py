"""
Punto de entrada.

    python run.py

Antes de la primera ejecucion:
    1. pip install -r requirements.txt
    2. copie .env.ejemplo como .env y ponga su cadena de Atlas
"""

import os

from app import crear_app
from app.db import crear_indices, probar_conexion

app = crear_app()

if __name__ == "__main__":
    with app.app_context():
        ok, detalle = probar_conexion()
        if ok:
            crear_indices()
            print(f"  Base de datos: {app.config['MONGO_DB']}  [conectada]")
        else:
            print("  AVISO: no se pudo conectar a MongoDB.")
            print(f"  {detalle[:160]}")
            print("  Revise MONGO_URI en .env y la lista de IP en Atlas "
                  "(Network Access).")

    print("  API      http://127.0.0.1:5001/api/atenciones")
    app.run(debug=True, port=int(os.environ.get("PORT", 5001)))
