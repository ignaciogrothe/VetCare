import 'dart:convert';

import 'package:http/http.dart' as http;

import 'modelos.dart';

/// URL de la API. 10.0.2.2 es el "localhost" del computador visto desde el
/// emulador de Android. En un telefono fisico usar la IP del computador:
///   flutter run --dart-define=API_URL=http://192.168.1.20:8080
const apiUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'http://10.0.2.2:8080',
);

/// Error con el formato del contrato: {"error", "codigo", "detalles"}.
/// codigo 0 = no hubo respuesta del servidor.
class ApiException implements Exception {
  ApiException(this.codigo, this.mensaje, [this.detalles]);

  final int codigo;
  final String mensaje;
  final Map<String, dynamic>? detalles;

  /// Mensaje con el detalle de cada campo que fallo.
  String get textoCompleto {
    final d = detalles;
    if (d == null || d.isEmpty) return mensaje;
    final lineas = d.entries.map((e) {
      final valor = e.value;
      return '• ${e.key}: ${valor is List ? valor.join(' ') : valor}';
    });
    return '$mensaje\n${lineas.join('\n')}';
  }

  @override
  String toString() => textoCompleto;
}

class ApiClient {
  ApiClient({http.Client? cliente, this.baseUrl = apiUrl})
    : _http = cliente ?? http.Client();

  final http.Client _http;
  final String baseUrl;

  String? token;

  /// Se llama cuando un endpoint protegido responde 401: hay que volver al
  /// login. Un 403 no cierra la sesion.
  void Function()? alExpirarSesion;

  Future<dynamic> _enviar(
    String metodo,
    String ruta, {
    Object? cuerpo,
    Map<String, Object?>? query,
  }) async {
    final parametros = {
      for (final e in (query ?? {}).entries)
        if (e.value != null) e.key: '${e.value}',
    };
    final uri = Uri.parse('$baseUrl$ruta')
        .replace(queryParameters: parametros.isEmpty ? null : parametros);
    final peticion = http.Request(metodo, uri)
      ..headers['accept'] = 'application/json';
    final tokenEnviado = token;
    if (tokenEnviado != null) {
      peticion.headers['authorization'] = 'Bearer $tokenEnviado';
    }
    if (cuerpo != null) {
      peticion.headers['content-type'] = 'application/json; charset=utf-8';
      peticion.body = jsonEncode(cuerpo);
    }

    final http.Response respuesta;
    try {
      respuesta = await http.Response.fromStream(
        await _http.send(peticion).timeout(const Duration(seconds: 15)),
      );
    } on Exception {
      throw ApiException(0, 'No se pudo conectar con el servidor ($baseUrl)');
    }

    final texto = utf8.decode(respuesta.bodyBytes);
    dynamic datos;
    try {
      datos = texto.isEmpty ? null : jsonDecode(texto);
    } on FormatException {
      datos = null;
    }
    if (respuesta.statusCode >= 200 && respuesta.statusCode < 300) {
      return datos;
    }
    if (respuesta.statusCode == 401 && tokenEnviado != null) {
      alExpirarSesion?.call();
    }
    final error = datos is Map<String, dynamic> ? datos : <String, dynamic>{};
    throw ApiException(
      respuesta.statusCode,
      error['error'] as String? ?? 'Error ${respuesta.statusCode}',
      error['detalles'] as Map<String, dynamic>?,
    );
  }

  // -------------------------------------------------------------- Auth

  /// E01
  Future<Sesion> login(String email, String clave) async => Sesion.fromJson(
    await _enviar(
      'POST',
      '/api/auth/login',
      cuerpo: {'email': email, 'clave': clave},
    ),
  );

  /// E02. El servidor fija el rol "dueno".
  Future<Usuario> registro({
    required String nombre,
    required String email,
    required String clave,
    String? telefono,
  }) async => Usuario.fromJson(
    await _enviar(
      'POST',
      '/api/auth/registro',
      cuerpo: {
        'nombre': nombre,
        'email': email,
        'clave': clave,
        if (telefono != null && telefono.isNotEmpty) 'telefono': telefono,
      },
    ),
  );

  /// E03. Solo administrador.
  Future<Usuario> crearPersonal({
    required String nombre,
    required String email,
    required String clave,
    required String rol,
    String? telefono,
  }) async => Usuario.fromJson(
    await _enviar(
      'POST',
      '/api/usuarios',
      cuerpo: {
        'nombre': nombre,
        'email': email,
        'clave': clave,
        'rol': rol,
        if (telefono != null && telefono.isNotEmpty) 'telefono': telefono,
      },
    ),
  );

  /// E04. Solo personal.
  Future<List<Referencia>> veterinarios() async =>
      ((await _enviar('GET', '/api/veterinarios')) as List)
          .map((e) => Referencia.fromJson(e as Map<String, dynamic>))
          .toList();

  // ---------------------------------------------------------- Mascotas

  /// E05
  Future<Pagina<Mascota>> mascotas({
    String? especie,
    int pagina = 1,
    int tamano = 20,
  }) async => Pagina.fromJson(
    await _enviar(
      'GET',
      '/api/mascotas',
      query: {'especie': especie, 'pagina': pagina, 'tamano': tamano},
    ),
    Mascota.fromJson,
  );

  /// E06
  Future<Mascota> crearMascota({
    required String nombre,
    required String especie,
    required String sexo,
    String? fechaNacimiento,
    double? pesoKg,
    required int duenoId,
  }) async => Mascota.fromJson(
    await _enviar(
      'POST',
      '/api/mascotas',
      cuerpo: {
        'nombre': nombre,
        'especie': especie,
        'sexo': sexo,
        'fecha_nacimiento': ?fechaNacimiento,
        'peso_kg': ?pesoKg,
        'dueno_id': duenoId,
      },
    ),
  );

  /// E07
  Future<Mascota> mascota(int id) async =>
      Mascota.fromJson(await _enviar('GET', '/api/mascotas/$id'));

  /// E08. Solo nombre y peso.
  Future<Mascota> modificarMascota(
    int id, {
    String? nombre,
    double? pesoKg,
  }) async => Mascota.fromJson(
    await _enviar(
      'PATCH',
      '/api/mascotas/$id',
      cuerpo: {'nombre': ?nombre, 'peso_kg': ?pesoKg},
    ),
  );

  /// E09. Solo administrador; 409 si tiene citas.
  Future<void> eliminarMascota(int id) =>
      _enviar('DELETE', '/api/mascotas/$id');

  // ------------------------------------------------------------- Citas

  /// E10. [fecha] en formato AAAA-MM-DD.
  Future<Pagina<CitaResumen>> citas({
    String? fecha,
    String? estado,
    int pagina = 1,
    int tamano = 20,
  }) async => Pagina.fromJson(
    await _enviar(
      'GET',
      '/api/citas',
      query: {
        'fecha': fecha,
        'estado': estado,
        'pagina': pagina,
        'tamano': tamano,
      },
    ),
    CitaResumen.fromJson,
  );

  /// E11. 409 si el veterinario ya tiene una cita en ese bloque.
  Future<Cita> crearCita({
    required int mascotaId,
    required int veterinarioId,
    required DateTime fechaHora,
    required String motivo,
  }) async => Cita.fromJson(
    await _enviar(
      'POST',
      '/api/citas',
      cuerpo: {
        'mascota_id': mascotaId,
        'veterinario_id': veterinarioId,
        'fecha_hora': fechaHoraApi(fechaHora),
        'motivo': motivo,
      },
    ),
  );

  /// E12
  Future<Cita> cita(int id) async =>
      Cita.fromJson(await _enviar('GET', '/api/citas/$id'));

  /// E13
  Future<Cita> cancelarCita(int id) async =>
      Cita.fromJson(await _enviar('POST', '/api/citas/$id/cancelacion'));

  /// E14. Solo el veterinario de la cita.
  Future<Atencion> registrarAtencion(
    int citaId, {
    required String diagnostico,
    String? tratamiento,
    List<Medicamento> medicamentos = const [],
  }) async => Atencion.fromJson(
    await _enviar(
      'POST',
      '/api/citas/$citaId/atencion',
      cuerpo: {
        'diagnostico': diagnostico,
        if (tratamiento != null && tratamiento.isNotEmpty)
          'tratamiento': tratamiento,
        'medicamentos': medicamentos.map((m) => m.toJson()).toList(),
      },
    ),
  );

  /// E15. La recepcionista recibe 403.
  Future<Atencion> atencion(int citaId) async =>
      Atencion.fromJson(await _enviar('GET', '/api/citas/$citaId/atencion'));

  /// E16. [medicamentos], si se envia, reemplaza la receta completa.
  Future<Atencion> corregirAtencion(
    int citaId, {
    String? diagnostico,
    String? tratamiento,
    List<Medicamento>? medicamentos,
  }) async => Atencion.fromJson(
    await _enviar(
      'PATCH',
      '/api/citas/$citaId/atencion',
      cuerpo: {
        'diagnostico': ?diagnostico,
        'tratamiento': ?tratamiento,
        if (medicamentos != null)
          'medicamentos': medicamentos.map((m) => m.toJson()).toList(),
      },
    ),
  );
}

/// Formato de fecha y hora de la API: 2026-11-03T10:30:00 (hora local).
String fechaHoraApi(DateTime f) =>
    '${fechaApi(f)}T${_dos(f.hour)}:${_dos(f.minute)}:00';

/// Formato de fecha de la API: 2026-11-03.
String fechaApi(DateTime f) =>
    '${f.year.toString().padLeft(4, '0')}-${_dos(f.month)}-${_dos(f.day)}';

String _dos(int n) => n.toString().padLeft(2, '0');
