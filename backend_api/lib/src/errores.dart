import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';

/// Error de la API con el formato del contrato:
/// {"error": "...", "codigo": 400, "detalles": {...}}
class ApiError implements Exception {
  ApiError(this.codigo, this.mensaje, {this.detalles});

  final int codigo;
  final String mensaje;
  final Map<String, List<String>>? detalles;

  Response aRespuesta() => respuestaJson(codigo, {
    'error': mensaje,
    'codigo': codigo,
    if (detalles != null) 'detalles': detalles,
  });

  @override
  String toString() => 'ApiError($codigo, $mensaje)';
}

const _cabecerasJson = {'content-type': 'application/json; charset=utf-8'};

Response respuestaJson(
  int estado,
  Object? cuerpo, {
  Map<String, String>? cabeceras,
}) => Response(
  estado,
  body: jsonEncode(cuerpo),
  headers: {..._cabecerasJson, ...?cabeceras},
);

/// Convierte ApiError en su respuesta JSON y cualquier otra excepcion en 500.
Middleware manejarErrores() =>
    (interno) => (peticion) async {
      try {
        return await interno(peticion);
      } on ApiError catch (e) {
        return e.aRespuesta();
      } catch (e, pila) {
        stderr.writeln('Error no controlado: $e\n$pila');
        return respuestaJson(500, {
          'error': 'Error interno del servidor',
          'codigo': 500,
        });
      }
    };

/// Lee el cuerpo como objeto JSON. Un cuerpo vacio cuenta como {}.
Future<Map<String, dynamic>> leerJson(Request peticion) async {
  final texto = await peticion.readAsString();
  if (texto.trim().isEmpty) return {};
  try {
    final datos = jsonDecode(texto);
    if (datos is Map<String, dynamic>) return datos;
  } on FormatException {
    // cae al error de abajo
  }
  throw ApiError(400, 'El cuerpo debe ser un objeto JSON valido');
}
