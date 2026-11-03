import 'errores.dart';

final _regexEmail = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
final _regexFecha = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
final _regexFechaHora = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2}))?$',
);
final _regexEntero = RegExp(r'^\d+$');

/// Acumula los errores de validacion por campo y al final responde un unico
/// 400 con todos ellos en "detalles".
class Validador {
  Validador(this.datos);

  final Map<String, dynamic> datos;
  final Map<String, List<String>> errores = {};

  void error(String campo, String mensaje) =>
      errores.putIfAbsent(campo, () => []).add(mensaje);

  bool tiene(String campo) => datos.containsKey(campo);

  /// Rechaza cualquier campo fuera de [permitidos] (por ejemplo id, rol, estado).
  void soloCampos(Set<String> permitidos) {
    for (final campo in datos.keys) {
      if (!permitidos.contains(campo)) error(campo, 'Campo no permitido.');
    }
  }

  void verificar() {
    if (errores.isNotEmpty) {
      throw ApiError(
        400,
        'Datos invalidos en: ${errores.keys.join(', ')}',
        detalles: errores,
      );
    }
  }

  String? texto(
    String campo, {
    bool obligatorio = false,
    int min = 0,
    required int max,
  }) {
    final valor = datos[campo];
    if (valor == null) {
      if (obligatorio) error(campo, 'Es obligatorio.');
      return null;
    }
    if (valor is! String) {
      error(campo, 'Debe ser un texto.');
      return null;
    }
    final limpio = valor.trim();
    if (limpio.length < min || limpio.length > max) {
      error(
        campo,
        min > 0
            ? 'Debe tener entre $min y $max caracteres.'
            : 'Debe tener como maximo $max caracteres.',
      );
      return null;
    }
    return limpio;
  }

  String? email(String campo) {
    final valor = texto(campo, obligatorio: true, min: 3, max: 254);
    if (valor == null) return null;
    if (!_regexEmail.hasMatch(valor)) {
      error(campo, 'Formato de correo invalido.');
      return null;
    }
    return valor.toLowerCase();
  }

  String? opcion(
    String campo,
    List<String> opciones, {
    bool obligatorio = false,
  }) {
    final valor = datos[campo];
    if (valor == null) {
      if (obligatorio) error(campo, 'Es obligatorio.');
      return null;
    }
    if (valor is! String || !opciones.contains(valor)) {
      error(campo, 'Debe ser uno de: ${opciones.join(', ')}.');
      return null;
    }
    return valor;
  }

  int? entero(String campo, {bool obligatorio = false, int min = 1, int? max}) {
    final valor = datos[campo];
    if (valor == null) {
      if (obligatorio) error(campo, 'Es obligatorio.');
      return null;
    }
    if (valor is! int || valor < min || (max != null && valor > max)) {
      error(
        campo,
        max == null
            ? 'Debe ser un entero mayor o igual a $min.'
            : 'Debe ser un entero entre $min y $max.',
      );
      return null;
    }
    return valor;
  }

  /// Peso en kg: mayor que 0 y hasta [max].
  num? positivo(String campo, {required num max}) {
    final valor = datos[campo];
    if (valor == null) return null;
    if (valor is! num || valor <= 0 || valor > max) {
      error(campo, 'Debe ser un numero mayor que 0 y hasta $max.');
      return null;
    }
    return valor;
  }

  /// Fecha AAAA-MM-DD que no puede ser futura.
  String? fechaPasada(String campo) {
    final valor = datos[campo];
    if (valor == null) return null;
    final fecha = valor is String ? _parsearFecha(valor) : null;
    if (fecha == null) {
      error(campo, 'Debe tener formato AAAA-MM-DD.');
      return null;
    }
    if (fecha.isAfter(DateTime.now())) {
      error(campo, 'No puede ser una fecha futura.');
      return null;
    }
    return valor as String;
  }

  /// Fecha y hora futura en bloques de 30 minutos (hh:00 o hh:30).
  DateTime? fechaHoraAgenda(String campo) {
    final valor = datos[campo];
    if (valor == null) {
      error(campo, 'Es obligatorio.');
      return null;
    }
    final fecha = valor is String ? _parsearFechaHora(valor) : null;
    if (fecha == null) {
      error(campo, 'Debe tener formato AAAA-MM-DDThh:mm:ss.');
      return null;
    }
    if (fecha.minute % 30 != 0 || fecha.second != 0) {
      error(campo, 'Debe ser un bloque de 30 minutos (hh:00 o hh:30).');
      return null;
    }
    if (!fecha.isAfter(DateTime.now())) {
      error(campo, 'Debe ser una fecha futura.');
      return null;
    }
    return fecha;
  }

  /// Lista de medicamentos de una receta. Devuelve null si no se envio.
  List<Map<String, Object>>? medicamentos(String campo) {
    if (!tiene(campo)) return null;
    final valor = datos[campo];
    if (valor is! List) {
      error(campo, 'Debe ser una lista.');
      return null;
    }
    final resultado = <Map<String, Object>>[];
    for (var i = 0; i < valor.length; i++) {
      final item = valor[i];
      if (item is! Map<String, dynamic>) {
        error('$campo[$i]', 'Debe ser un objeto.');
        continue;
      }
      final v = Validador(item)
        ..soloCampos({'medicamento', 'dosis', 'duracion_dias'});
      final medicamento = v.texto(
        'medicamento',
        obligatorio: true,
        min: 2,
        max: 80,
      );
      final dosis = v.texto('dosis', obligatorio: true, min: 1, max: 100);
      final dias = v.entero('duracion_dias', obligatorio: true, max: 90);
      v.errores.forEach((sub, mensajes) {
        for (final m in mensajes) {
          error('$campo[$i].$sub', m);
        }
      });
      if (v.errores.isEmpty) {
        resultado.add({
          'medicamento': medicamento!,
          'dosis': dosis!,
          'duracion_dias': dias!,
        });
      }
    }
    return resultado;
  }
}

/// Validacion de parametros del query string (siempre llegan como texto).
class ValidadorQuery extends Validador {
  ValidadorQuery(Map<String, String> super.datos);

  int enteroTexto(String campo, {required int defecto, int min = 1, int? max}) {
    final valor = datos[campo] as String?;
    if (valor == null || valor.isEmpty) return defecto;
    final numero = _regexEntero.hasMatch(valor) ? int.tryParse(valor) : null;
    if (numero == null || numero < min || (max != null && numero > max)) {
      error(
        campo,
        max == null
            ? 'Debe ser un entero mayor o igual a $min.'
            : 'Debe ser un entero entre $min y $max.',
      );
      return defecto;
    }
    return numero;
  }

  String? fecha(String campo) {
    final valor = datos[campo] as String?;
    if (valor == null || valor.isEmpty) return null;
    if (_parsearFecha(valor) == null) {
      error(campo, 'Debe tener formato AAAA-MM-DD.');
      return null;
    }
    return valor;
  }
}

DateTime? _parsearFecha(String texto) {
  final m = _regexFecha.firstMatch(texto);
  if (m == null) return null;
  return _fechaExacta(
    int.parse(m[1]!),
    int.parse(m[2]!),
    int.parse(m[3]!),
    0,
    0,
    0,
  );
}

DateTime? _parsearFechaHora(String texto) {
  final m = _regexFechaHora.firstMatch(texto);
  if (m == null) return null;
  return _fechaExacta(
    int.parse(m[1]!),
    int.parse(m[2]!),
    int.parse(m[3]!),
    int.parse(m[4]!),
    int.parse(m[5]!),
    int.parse(m[6] ?? '0'),
  );
}

/// DateTime normaliza fechas imposibles (30 de febrero -> 2 de marzo):
/// aqui se rechazan comparando los componentes.
DateTime? _fechaExacta(int a, int me, int d, int h, int mi, int s) {
  final f = DateTime(a, me, d, h, mi, s);
  final igual =
      f.year == a &&
      f.month == me &&
      f.day == d &&
      f.hour == h &&
      f.minute == mi &&
      f.second == s;
  return igual ? f : null;
}

/// Formato de la API: 2026-11-03T10:30:00
String fechaHoraIso(DateTime f) {
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${f.year.toString().padLeft(4, '0')}-${dos(f.month)}-${dos(f.day)}'
      'T${dos(f.hour)}:${dos(f.minute)}:${dos(f.second)}';
}

/// MySQL devuelve "2026-11-03 10:30:00"; la API usa "T" como separador.
String? deMysqlAIso(String? valor) => valor?.replaceFirst(' ', 'T');

/// Formato DATETIME de MySQL.
String fechaHoraMysql(DateTime f) => fechaHoraIso(f).replaceFirst('T', ' ');
