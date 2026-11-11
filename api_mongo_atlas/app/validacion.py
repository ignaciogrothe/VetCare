"""
Validacion de la entrada.

MongoDB acepta practicamente cualquier documento: la coherencia de los datos
es responsabilidad de la API. Aqui se define como es una atencion valida.
"""

CAMPOS_ATENCION = {"cita_id", "diagnostico", "tratamiento", "medicamentos"}
CAMPOS_ACTUALIZABLES = CAMPOS_ATENCION - {"cita_id"}   # la cita no se cambia
CAMPOS_MEDICAMENTO = {"medicamento", "dosis", "duracion_dias"}


def _texto(valor):
    return valor.strip() if isinstance(valor, str) else None


def _entero(valor):
    # bool es subclase de int en Python: True pasaria como numero valido.
    return isinstance(valor, int) and not isinstance(valor, bool)


def _validar_medicamentos(lista, errores):
    """Cada medicamento es un objeto anidado: {medicamento, dosis, duracion_dias}."""
    if not isinstance(lista, list):
        errores["medicamentos"] = "Debe ser una lista."
        return None
    resultado = []
    for i, item in enumerate(lista):
        pref = f"medicamentos[{i}]"
        if not isinstance(item, dict):
            errores[pref] = "Debe ser un objeto."
            continue
        antes = len(errores)
        sobrantes = set(item) - CAMPOS_MEDICAMENTO
        if sobrantes:
            errores[pref] = f"Campos no permitidos: {', '.join(sorted(sobrantes))}."
        nombre = _texto(item.get("medicamento"))
        if not nombre or not 2 <= len(nombre) <= 80:
            errores[f"{pref}.medicamento"] = "Obligatorio, entre 2 y 80 caracteres."
        dosis = _texto(item.get("dosis"))
        if not dosis or not 1 <= len(dosis) <= 100:
            errores[f"{pref}.dosis"] = "Obligatoria, entre 1 y 100 caracteres."
        dias = item.get("duracion_dias")
        if not _entero(dias) or not 1 <= dias <= 90:
            errores[f"{pref}.duracion_dias"] = "Debe ser un entero entre 1 y 90."
        if len(errores) == antes:
            resultado.append({"medicamento": nombre, "dosis": dosis, "duracion_dias": dias})
    return resultado


def validar_atencion(datos, parcial=False):
    """
    Devuelve (documento_limpio, errores).
    parcial=True se usa en PUT: solo valida lo que vino y no admite cita_id.
    """
    errores = {}
    if not isinstance(datos, dict):
        return None, {"_": "El cuerpo debe ser un objeto JSON."}

    permitidos = CAMPOS_ACTUALIZABLES if parcial else CAMPOS_ATENCION
    sobrantes = set(datos) - permitidos
    if sobrantes:
        errores["_"] = f"Campos no permitidos: {', '.join(sorted(sobrantes))}."

    limpio = {}

    if "cita_id" in datos:
        cita_id = datos["cita_id"]
        if not _entero(cita_id) or cita_id < 1:
            errores["cita_id"] = "Debe ser un entero mayor o igual a 1."
        else:
            limpio["cita_id"] = cita_id
    elif not parcial:
        errores["cita_id"] = "cita_id es obligatorio."

    if "diagnostico" in datos:
        diagnostico = _texto(datos["diagnostico"])
        if not diagnostico or not 5 <= len(diagnostico) <= 2000:
            errores["diagnostico"] = "Obligatorio, entre 5 y 2000 caracteres."
        else:
            limpio["diagnostico"] = diagnostico
    elif not parcial:
        errores["diagnostico"] = "El diagnostico es obligatorio."

    if "tratamiento" in datos:
        if datos["tratamiento"] is None:
            limpio["tratamiento"] = None
        else:
            tratamiento = _texto(datos["tratamiento"])
            if tratamiento is None or len(tratamiento) > 2000:
                errores["tratamiento"] = "Debe ser un texto de hasta 2000 caracteres."
            else:
                limpio["tratamiento"] = tratamiento or None

    if "medicamentos" in datos:
        medicamentos = _validar_medicamentos(datos["medicamentos"], errores)
        if medicamentos is not None:
            limpio["medicamentos"] = medicamentos
    elif not parcial:
        limpio["medicamentos"] = []

    if parcial and not limpio and not errores:
        errores["_"] = "No se envio ningun campo para actualizar."

    return (None, errores) if errores else (limpio, None)
