"""
Carga datos de ejemplo en la base de datos.

    python semilla.py

Borra la coleccion `atenciones` y deja 6 atenciones (cita_id 1 a 6) con
recetas de distinto largo, para probar filtros, proyeccion y agregacion.
"""

from datetime import datetime, timedelta, timezone

from app import crear_app
from app.db import crear_indices, obtener_db, probar_conexion


def med(nombre, dosis, dias):
    return {"medicamento": nombre, "dosis": dosis, "duracion_dias": dias}


ATENCIONES = [
    (1, "Otitis externa leve en oido izquierdo", "Limpieza diaria del canal auditivo",
     [med("Otomax", "2 gotas cada 12 h", 7)]),
    (2, "Gastroenteritis aguda", "Dieta blanda y reposo",
     [med("Metronidazol", "1 comprimido cada 12 h", 5), med("Probiotico", "1 sobre al dia", 10)]),
    (3, "Control anual sin hallazgos", None, []),
    (4, "Dermatitis alergica por pulgas", "Antipulgas y bano medicado",
     [med("Prednisolona", "0.5 mg/kg cada 24 h", 5), med("Antipulgas", "1 pipeta", 30)]),
    (5, "Infeccion respiratoria superior", "Humidificar el ambiente",
     [med("Amoxicilina", "1 comprimido cada 12 h", 7)]),
    (6, "Herida cortante en almohadilla", "Curacion cada 48 h",
     [med("Amoxicilina", "1 comprimido cada 12 h", 5), med("Meloxicam", "0.1 mg/kg cada 24 h", 3)]),
]


def main():
    app = crear_app()
    with app.app_context():
        ok, detalle = probar_conexion()
        if not ok:
            print("  No se pudo conectar a MongoDB.")
            print(f"  {detalle[:200]}")
            print("\n  Revise:")
            print("   1. que MONGO_URI en .env sea la cadena de su cluster")
            print("   2. que su IP este autorizada en Atlas -> Network Access")
            print("   3. que la clave del usuario no tenga caracteres sin codificar")
            return 1

        db = obtener_db()
        db.atenciones.delete_many({})
        hoy = datetime.now(timezone.utc).replace(microsecond=0)
        db.atenciones.insert_many([
            {"cita_id": c, "diagnostico": d, "tratamiento": t, "medicamentos": m,
             "fecha_registro": hoy - timedelta(days=7 - c), "actualizado_en": hoy - timedelta(days=7 - c)}
            for c, d, t, m in ATENCIONES
        ])
        crear_indices()

        print(f"  Base de datos '{app.config['MONGO_DB']}' cargada:")
        print(f"   {db.atenciones.count_documents({})} atenciones")
        print(f"   indices: {', '.join(db.atenciones.index_information())}")
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
