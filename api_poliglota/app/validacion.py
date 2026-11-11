"""Validacion de la entrada. Nunca se confia en el cliente."""

import re
from datetime import datetime

from .errores import ApiError

RE_EMAIL = re.compile(r"[^@\s]+@[^@\s]+\.[^@\s]+")
RE_FECHA = re.compile(r"(\d{4})-(\d{2})-(\d{2})", re.ASCII)
RE_FECHA_HORA = re.compile(
    r"(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2}))?", re.ASCII
)
RE_ENTERO = re.compile(r"\d+", re.ASCII)


def _es_entero(v):
    return isinstance(v, int) and not isinstance(v, bool)


def _es_numero(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def _fecha_exacta(a, me, d, h=0, mi=0, s=0):
    try:
        return datetime(a, me, d, h, mi, s)
    except ValueError:
        return None  # 30 de febrero, mes 13, etc.


def parsear_fecha(texto):
    m = RE_FECHA.fullmatch(texto)
    return _fecha_exacta(*(int(x) for x in m.groups())) if m else None


def parsear_fecha_hora(texto):
    m = RE_FECHA_HORA.fullmatch(texto)
    if not m:
        return None
    a, me, d, h, mi, s = m.groups()
    return _fecha_exacta(int(a), int(me), int(d), int(h), int(mi), int(s or 0))


def a_iso(f):
    return f.strftime("%Y-%m-%dT%H:%M:%S") if f else None


def fecha_hora_mysql(f):
    return f.strftime("%Y-%m-%d %H:%M:%S")


class Validador:
    """Acumula errores por campo y responde un unico 400 con todos."""

    def __init__(self, datos):
        self.datos = datos
        self.errores = {}

    def error(self, campo, mensaje):
        self.errores.setdefault(campo, []).append(mensaje)

    def tiene(self, campo):
        return campo in self.datos

    def solo_campos(self, permitidos):
        for campo in self.datos:
            if campo not in permitidos:
                self.error(campo, "Campo no permitido.")

    def verificar(self):
        if self.errores:
            raise ApiError(
                400,
                "Datos invalidos en: " + ", ".join(self.errores),
                self.errores,
            )

    def texto(self, campo, obligatorio=False, minimo=0, maximo=0):
        valor = self.datos.get(campo)
        if valor is None:
            if obligatorio:
                self.error(campo, "Es obligatorio.")
            return None
        if not isinstance(valor, str):
            self.error(campo, "Debe ser un texto.")
            return None
        limpio = valor.strip()
        if len(limpio) < minimo or len(limpio) > maximo:
            self.error(
                campo,
                "Debe tener entre %d y %d caracteres." % (minimo, maximo)
                if minimo > 0
                else "Debe tener como maximo %d caracteres." % maximo,
            )
            return None
        return limpio

    def email(self, campo):
        valor = self.texto(campo, obligatorio=True, minimo=3, maximo=254)
        if valor is None:
            return None
        if not RE_EMAIL.fullmatch(valor):
            self.error(campo, "Formato de correo invalido.")
            return None
        return valor.lower()

    def opcion(self, campo, opciones, obligatorio=False):
        valor = self.datos.get(campo)
        if valor is None:
            if obligatorio:
                self.error(campo, "Es obligatorio.")
            return None
        if not isinstance(valor, str) or valor not in opciones:
            self.error(campo, "Debe ser uno de: %s." % ", ".join(opciones))
            return None
        return valor

    def entero(self, campo, obligatorio=False, minimo=1, maximo=None):
        valor = self.datos.get(campo)
        if valor is None:
            if obligatorio:
                self.error(campo, "Es obligatorio.")
            return None
        if not _es_entero(valor) or valor < minimo or (
            maximo is not None and valor > maximo
        ):
            self.error(
                campo,
                "Debe ser un entero mayor o igual a %d." % minimo
                if maximo is None
                else "Debe ser un entero entre %d y %d." % (minimo, maximo),
            )
            return None
        return valor

    def positivo(self, campo, maximo):
        valor = self.datos.get(campo)
        if valor is None:
            return None
        if not _es_numero(valor) or valor <= 0 or valor > maximo:
            self.error(campo, "Debe ser un numero mayor que 0 y hasta %s." % maximo)
            return None
        return valor

    def fecha_pasada(self, campo):
        valor = self.datos.get(campo)
        if valor is None:
            return None
        fecha = parsear_fecha(valor) if isinstance(valor, str) else None
        if fecha is None:
            self.error(campo, "Debe tener formato AAAA-MM-DD.")
            return None
        if fecha > datetime.now():
            self.error(campo, "No puede ser una fecha futura.")
            return None
        return valor

    def fecha_hora_agenda(self, campo):
        """Fecha y hora futura en bloques de 30 minutos (hh:00 o hh:30)."""
        valor = self.datos.get(campo)
        if valor is None:
            self.error(campo, "Es obligatorio.")
            return None
        fecha = parsear_fecha_hora(valor) if isinstance(valor, str) else None
        if fecha is None:
            self.error(campo, "Debe tener formato AAAA-MM-DDThh:mm:ss.")
            return None
        if fecha.minute % 30 != 0 or fecha.second != 0:
            self.error(campo, "Debe ser un bloque de 30 minutos (hh:00 o hh:30).")
            return None
        if fecha <= datetime.now():
            self.error(campo, "Debe ser una fecha futura.")
            return None
        return fecha

    def medicamentos(self, campo):
        """Lista de medicamentos de la receta. None si no se envio."""
        if not self.tiene(campo):
            return None
        valor = self.datos[campo]
        if not isinstance(valor, list):
            self.error(campo, "Debe ser una lista.")
            return None
        resultado = []
        for i, item in enumerate(valor):
            if not isinstance(item, dict):
                self.error("%s[%d]" % (campo, i), "Debe ser un objeto.")
                continue
            v = Validador(item)
            v.solo_campos({"medicamento", "dosis", "duracion_dias"})
            medicamento = v.texto("medicamento", True, 2, 80)
            dosis = v.texto("dosis", True, 1, 100)
            dias = v.entero("duracion_dias", True, 1, 90)
            for sub, mensajes in v.errores.items():
                for m in mensajes:
                    self.error("%s[%d].%s" % (campo, i, sub), m)
            if not v.errores:
                resultado.append(
                    {"medicamento": medicamento, "dosis": dosis, "duracion_dias": dias}
                )
        return resultado


class ValidadorQuery(Validador):
    """Parametros del query string (siempre llegan como texto)."""

    def entero_texto(self, campo, defecto, minimo=1, maximo=None):
        valor = self.datos.get(campo)
        if not valor:
            return defecto
        numero = int(valor) if RE_ENTERO.fullmatch(valor) else None
        if numero is None or numero < minimo or (
            maximo is not None and numero > maximo
        ):
            self.error(
                campo,
                "Debe ser un entero mayor o igual a %d." % minimo
                if maximo is None
                else "Debe ser un entero entre %d y %d." % (minimo, maximo),
            )
            return defecto
        return numero

    def fecha(self, campo):
        valor = self.datos.get(campo)
        if not valor:
            return None
        if parsear_fecha(valor) is None:
            self.error(campo, "Debe tener formato AAAA-MM-DD.")
            return None
        return valor
