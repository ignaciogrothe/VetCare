import 'package:mysql_client/exception.dart';
import 'package:mysql_client/mysql_client.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'auth.dart';
import 'errores.dart';
import 'validacion.dart';

const _especies = ['perro', 'gato', 'ave', 'conejo', 'otro'];
const _sexos = ['macho', 'hembra'];
const _estadosCita = ['agendada', 'atendida', 'cancelada'];
const _rolesPersonal = ['veterinario', 'recepcionista', 'administrador'];

const _personal = {'veterinario', 'recepcionista', 'administrador'};
const _recepcion = {'recepcionista', 'administrador'};
const _soloAdmin = {'administrador'};
const _soloVeterinario = {'veterinario'};

/// Codigos de error de MySQL que se traducen a 409.
const _errorDuplicado = 1062;
const _errorFkConHijos = 1451;

typedef Ejecutar = Future<IResultSet> Function(
  String sql, [
  Map<String, dynamic>? params,
]);

extension on IResultSet {
  List<Map<String, String?>> get filas => rows.map((r) => r.assoc()).toList();
}

/// Endpoints E01-E16 de la especificacion "Caso 2 - Veterinaria".
class VeterinariaApi {
  VeterinariaApi(this.pool, this.auth);

  final MySQLConnectionPool pool;
  final Auth auth;

  Handler get handler {
    final r = Router(
      notFoundHandler: (_) async => throw ApiError(404, 'Ruta no encontrada'),
    );

    r.post('/api/auth/login', _login); // E01
    r.post('/api/auth/registro', _registro); // E02
    r.get('/api/auth/yo', _yo); // destino del Location de E02
    r.post('/api/usuarios', _crearPersonal); // E03
    r.get('/api/veterinarios', _veterinarios); // E04

    r.get('/api/mascotas', _listarMascotas); // E05
    r.post('/api/mascotas', _crearMascota); // E06
    r.get('/api/mascotas/<id>', _verMascota); // E07
    r.patch('/api/mascotas/<id>', _modificarMascota); // E08
    r.delete('/api/mascotas/<id>', _eliminarMascota); // E09

    r.get('/api/citas', _listarCitas); // E10
    r.post('/api/citas', _crearCita); // E11
    r.get('/api/citas/<id>', _verCita); // E12
    r.post('/api/citas/<id>/cancelacion', _cancelarCita); // E13
    r.post('/api/citas/<id>/atencion', _registrarAtencion); // E14
    r.get('/api/citas/<id>/atencion', _verAtencion); // E15
    r.patch('/api/citas/<id>/atencion', _corregirAtencion); // E16

    return const Pipeline().addMiddleware(manejarErrores()).addHandler(r.call);
  }

  /// pool.transactional de mysql_client no libera la conexion si el callback
  /// lanza una excepcion (por ejemplo un ApiError 409): aqui se captura dentro
  /// de withConnection, tras el ROLLBACK, y se relanza fuera.
  Future<T> _transaccion<T>(Future<T> Function(MySQLConnection conn) cb) async {
    Object? error;
    StackTrace? pila;
    final resultado = await pool.withConnection((conn) async {
      try {
        return await conn.transactional(cb);
      } catch (e, st) {
        error = e;
        pila = st;
        return null;
      }
    });
    if (error != null) Error.throwWithStackTrace(error!, pila!);
    return resultado as T;
  }

  // ---------------------------------------------------------------- Auth

  /// E01. Mismo 401 si el email no existe, la clave es incorrecta o el
  /// usuario esta inactivo.
  Future<Response> _login(Request peticion) async {
    final v = Validador(await leerJson(peticion));
    final email = v.email('email');
    final clave = v.texto('clave', obligatorio: true, min: 1, max: 200);
    v.verificar();

    final usuario = await auth.buscarPorEmail(email!);
    final valido =
        usuario != null &&
        usuario.activo &&
        Auth.claveCorrecta(clave!, usuario.claveHash!);
    if (!valido) throw ApiError(401, 'Credenciales invalidas');

    return respuestaJson(200, {
      'access_token': auth.emitirToken(usuario),
      'token_type': 'Bearer',
      'expira_en': segundosToken,
      'usuario': {
        'id': usuario.id,
        'nombre': usuario.nombre,
        'rol': usuario.rol,
      },
    });
  }

  /// E02. El rol siempre es "dueno": si el cliente envia "rol" se ignora.
  Future<Response> _registro(Request peticion) async {
    final v = Validador(await leerJson(peticion));
    final usuario = await _crearUsuario(v, 'dueno');
    return respuestaJson(
      201,
      usuario.aJson(),
      cabeceras: {'location': '/api/auth/yo'},
    );
  }

  Future<Response> _yo(Request peticion) async {
    final usuario = await auth.autenticar(peticion);
    return respuestaJson(200, usuario.aJson());
  }

  /// E03. Unico lugar donde se asigna un rol distinto de "dueno".
  Future<Response> _crearPersonal(Request peticion) async {
    await auth.autenticar(peticion, roles: _soloAdmin);
    final v = Validador(await leerJson(peticion))
      ..soloCampos({'nombre', 'email', 'clave', 'rol', 'telefono'});
    final rol = v.opcion('rol', _rolesPersonal, obligatorio: true);
    final usuario = await _crearUsuario(v, rol);
    return respuestaJson(
      201,
      usuario.aJson(),
      cabeceras: {'location': '/api/usuarios/${usuario.id}'},
    );
  }

  Future<Usuario> _crearUsuario(Validador v, String? rol) async {
    final nombre = v.texto('nombre', obligatorio: true, min: 2, max: 80);
    final email = v.email('email');
    final clave = v.texto('clave', obligatorio: true, min: 8, max: 200);
    final telefono = v.texto('telefono', max: 15);
    if (telefono != null && !RegExp(r'^\d{8,15}$').hasMatch(telefono)) {
      v.error('telefono', 'Solo digitos, entre 8 y 15.');
    }
    v.verificar();

    if (await auth.buscarPorEmail(email!) != null) {
      throw ApiError(409, 'El email ya esta registrado');
    }
    try {
      await pool.execute(
        'INSERT INTO usuarios (nombre, email, clave_hash, rol, telefono) '
        'VALUES (:nombre, :email, :hash, :rol, :telefono)',
        {
          'nombre': nombre,
          'email': email,
          'hash': Auth.hashClave(clave!),
          'rol': rol,
          'telefono': telefono,
        },
      );
    } on MySQLServerException catch (e) {
      if (e.errorCode == _errorDuplicado) {
        throw ApiError(409, 'El email ya esta registrado');
      }
      rethrow;
    }
    return (await auth.buscarPorEmail(email))!;
  }

  /// E04. Solo id y nombre: no expone email ni telefono.
  Future<Response> _veterinarios(Request peticion) async {
    await auth.autenticar(peticion, roles: _personal);
    final r = await pool.execute(
      "SELECT id, nombre FROM usuarios WHERE rol = 'veterinario' "
      'AND activo = TRUE ORDER BY nombre',
    );
    return respuestaJson(200, [
      for (final f in r.filas)
        {'id': int.parse(f['id']!), 'nombre': f['nombre']},
    ]);
  }

  // ------------------------------------------------------------ Mascotas

  static const _sqlMascota =
      'SELECT m.id, m.nombre, m.especie, m.sexo, m.fecha_nacimiento, '
      'm.peso_kg, m.dueno_id, u.nombre AS dueno_nombre '
      'FROM mascotas m JOIN usuarios u ON u.id = m.dueno_id';

  static Map<String, Object?> _mascotaJson(Map<String, String?> f) => {
    'id': int.parse(f['id']!),
    'nombre': f['nombre'],
    'especie': f['especie'],
    'sexo': f['sexo'],
    'fecha_nacimiento': f['fecha_nacimiento'],
    'peso_kg': f['peso_kg'] == null ? null : num.parse(f['peso_kg']!),
    'dueno': {'id': int.parse(f['dueno_id']!), 'nombre': f['dueno_nombre']},
  };

  Future<Map<String, String?>?> _buscarMascota(int id) async {
    final r = await pool.execute('$_sqlMascota WHERE m.id = :id', {'id': id});
    return r.rows.isEmpty ? null : r.rows.first.assoc();
  }

  Future<Map<String, String?>> _mascotaExistente(String idRuta) async {
    final id = _idRuta(idRuta);
    final fila = id == null ? null : await _buscarMascota(id);
    if (fila == null) throw ApiError(404, 'La mascota no existe');
    return fila;
  }

  /// E05. Un dueno ve solo sus mascotas; el personal ve todas.
  Future<Response> _listarMascotas(Request peticion) async {
    final usuario = await auth.autenticar(peticion);
    final q = ValidadorQuery(peticion.url.queryParameters);
    final especie = q.opcion('especie', _especies);
    final pagina = q.enteroTexto('pagina', defecto: 1);
    final tamano = q.enteroTexto('tamano', defecto: 20, max: 50);
    q.verificar();

    final filtros = <String>[];
    final params = <String, dynamic>{};
    if (usuario.esDueno) {
      filtros.add('m.dueno_id = :dueno');
      params['dueno'] = usuario.id;
    }
    if (especie != null) {
      filtros.add('m.especie = :especie');
      params['especie'] = especie;
    }
    final where = filtros.isEmpty ? '' : ' WHERE ${filtros.join(' AND ')}';

    final total = await pool.execute(
      'SELECT COUNT(*) AS n FROM mascotas m$where',
      params,
    );
    final r = await pool.execute(
      '$_sqlMascota$where ORDER BY m.nombre, m.id '
      'LIMIT $tamano OFFSET ${(pagina - 1) * tamano}',
      params,
    );
    return respuestaJson(200, {
      'items': r.filas.map(_mascotaJson).toList(),
      'pagina': pagina,
      'tamano': tamano,
      'total': int.parse(total.rows.first.colByName('n')!),
    });
  }

  /// E06.
  Future<Response> _crearMascota(Request peticion) async {
    await auth.autenticar(peticion, roles: _recepcion);
    final v = Validador(await leerJson(peticion))
      ..soloCampos({
        'nombre',
        'especie',
        'sexo',
        'fecha_nacimiento',
        'peso_kg',
        'dueno_id',
      });
    final nombre = v.texto('nombre', obligatorio: true, min: 2, max: 60);
    final especie = v.opcion('especie', _especies, obligatorio: true);
    final sexo = v.opcion('sexo', _sexos, obligatorio: true);
    final nacimiento = v.fechaPasada('fecha_nacimiento');
    final peso = v.positivo('peso_kg', max: 200);
    final duenoId = v.entero('dueno_id', obligatorio: true);
    v.verificar();

    final dueno = await pool.execute(
      "SELECT id FROM usuarios WHERE id = :id AND rol = 'dueno'",
      {'id': duenoId},
    );
    if (dueno.rows.isEmpty) throw ApiError(422, 'dueno_id invalido');

    final r = await pool.execute(
      'INSERT INTO mascotas (nombre, especie, sexo, fecha_nacimiento, '
      'peso_kg, dueno_id) VALUES (:nombre, :especie, :sexo, :nacimiento, '
      ':peso, :dueno)',
      {
        'nombre': nombre,
        'especie': especie,
        'sexo': sexo,
        'nacimiento': nacimiento,
        'peso': peso,
        'dueno': duenoId,
      },
    );
    final id = r.lastInsertID.toInt();
    return respuestaJson(
      201,
      _mascotaJson((await _buscarMascota(id))!),
      cabeceras: {'location': '/api/mascotas/$id'},
    );
  }

  /// E07. Un dueno solo accede a sus mascotas (403); el personal a todas.
  Future<Response> _verMascota(Request peticion, String idRuta) async {
    final usuario = await auth.autenticar(peticion);
    final fila = await _mascotaExistente(idRuta);
    if (usuario.esDueno && fila['dueno_id'] != '${usuario.id}') {
      throw ApiError(403, 'La mascota no le pertenece');
    }
    return respuestaJson(200, _mascotaJson(fila));
  }

  /// E08. Solo nombre y peso: dueno_id, especie o id dan 400.
  Future<Response> _modificarMascota(Request peticion, String idRuta) async {
    await auth.autenticar(peticion, roles: _recepcion);
    final fila = await _mascotaExistente(idRuta);
    final v = Validador(await leerJson(peticion))
      ..soloCampos({'nombre', 'peso_kg'});
    if (v.datos.isEmpty) v.error('cuerpo', 'Envie al menos nombre o peso_kg.');
    final nombre = v.texto('nombre', min: 2, max: 60);
    if (v.tiene('nombre') && v.datos['nombre'] == null) {
      v.error('nombre', 'No puede ser nulo.');
    }
    final peso = v.positivo('peso_kg', max: 200);
    v.verificar();

    final cambios = <String>[];
    final params = <String, dynamic>{'id': int.parse(fila['id']!)};
    if (v.tiene('nombre')) {
      cambios.add('nombre = :nombre');
      params['nombre'] = nombre;
    }
    if (v.tiene('peso_kg')) {
      cambios.add('peso_kg = :peso');
      params['peso'] = peso;
    }
    await pool.execute(
      'UPDATE mascotas SET ${cambios.join(', ')} WHERE id = :id',
      params,
    );
    return respuestaJson(
      200,
      _mascotaJson((await _buscarMascota(params['id'] as int))!),
    );
  }

  /// E09. 409 si tiene citas, para no perder el historial clinico.
  Future<Response> _eliminarMascota(Request peticion, String idRuta) async {
    await auth.autenticar(peticion, roles: _soloAdmin);
    final fila = await _mascotaExistente(idRuta);
    const conCitas = 'No se puede eliminar: la mascota tiene citas';
    final citas = await pool.execute(
      'SELECT 1 FROM citas WHERE mascota_id = :id LIMIT 1',
      {'id': fila['id']},
    );
    if (citas.rows.isNotEmpty) throw ApiError(409, conCitas);
    try {
      await pool.execute('DELETE FROM mascotas WHERE id = :id', {
        'id': fila['id'],
      });
    } on MySQLServerException catch (e) {
      if (e.errorCode == _errorFkConHijos) throw ApiError(409, conCitas);
      rethrow;
    }
    return Response(204);
  }

  // --------------------------------------------------------------- Citas

  static const _sqlCita =
      'SELECT c.id, c.mascota_id, c.veterinario_id, c.fecha_hora, c.motivo, '
      'c.estado, m.nombre AS mascota_nombre, m.dueno_id, '
      'v.nombre AS veterinario_nombre '
      'FROM citas c JOIN mascotas m ON m.id = c.mascota_id '
      'JOIN usuarios v ON v.id = c.veterinario_id';

  /// Detalle de una cita: nunca incluye diagnostico.
  static Map<String, Object?> _citaJson(Map<String, String?> f) => {
    'id': int.parse(f['id']!),
    'mascota': {
      'id': int.parse(f['mascota_id']!),
      'nombre': f['mascota_nombre'],
    },
    'veterinario': {
      'id': int.parse(f['veterinario_id']!),
      'nombre': f['veterinario_nombre'],
    },
    'fecha_hora': deMysqlAIso(f['fecha_hora']),
    'motivo': f['motivo'],
    'estado': f['estado'],
  };

  Future<Map<String, String?>?> _buscarCita(
    int id, [
    Ejecutar? ejecutar,
  ]) async {
    final r = await (ejecutar ?? pool.execute)('$_sqlCita WHERE c.id = :id', {
      'id': id,
    });
    return r.rows.isEmpty ? null : r.rows.first.assoc();
  }

  Future<Map<String, String?>> _citaExistente(String idRuta) async {
    final id = _idRuta(idRuta);
    final fila = id == null ? null : await _buscarCita(id);
    if (fila == null) throw ApiError(404, 'La cita no existe');
    return fila;
  }

  static void _verificarDuenoDeCita(
    Usuario usuario,
    Map<String, String?> cita,
  ) {
    if (usuario.esDueno && cita['dueno_id'] != '${usuario.id}') {
      throw ApiError(403, 'La cita no corresponde a una mascota suya');
    }
  }

  static void _verificarVeterinarioDeCita(
    Usuario usuario,
    Map<String, String?> cita,
  ) {
    if (cita['veterinario_id'] != '${usuario.id}') {
      throw ApiError(403, 'Solo el veterinario asignado puede hacer esto');
    }
  }

  /// E10. Un dueno ve solo citas de sus mascotas. Nunca incluye diagnostico.
  Future<Response> _listarCitas(Request peticion) async {
    final usuario = await auth.autenticar(peticion);
    final q = ValidadorQuery(peticion.url.queryParameters);
    final fecha = q.fecha('fecha');
    final estado = q.opcion('estado', _estadosCita);
    final pagina = q.enteroTexto('pagina', defecto: 1);
    final tamano = q.enteroTexto('tamano', defecto: 20, max: 50);
    q.verificar();

    final filtros = <String>[];
    final params = <String, dynamic>{};
    if (usuario.esDueno) {
      filtros.add('m.dueno_id = :dueno');
      params['dueno'] = usuario.id;
    }
    if (fecha != null) {
      filtros.add(
        'c.fecha_hora >= :fecha AND c.fecha_hora < :fecha + INTERVAL 1 DAY',
      );
      params['fecha'] = fecha;
    }
    if (estado != null) {
      filtros.add('c.estado = :estado');
      params['estado'] = estado;
    }
    final where = filtros.isEmpty ? '' : ' WHERE ${filtros.join(' AND ')}';
    const desde = ' FROM citas c JOIN mascotas m ON m.id = c.mascota_id';

    final total = await pool.execute(
      'SELECT COUNT(*) AS n$desde$where',
      params,
    );
    final r = await pool.execute(
      'SELECT c.id, c.mascota_id, c.veterinario_id, c.fecha_hora, c.motivo, '
      'c.estado$desde$where ORDER BY c.fecha_hora, c.id '
      'LIMIT $tamano OFFSET ${(pagina - 1) * tamano}',
      params,
    );
    return respuestaJson(200, {
      'items': [
        for (final f in r.filas)
          {
            'id': int.parse(f['id']!),
            'mascota_id': int.parse(f['mascota_id']!),
            'veterinario_id': int.parse(f['veterinario_id']!),
            'fecha_hora': deMysqlAIso(f['fecha_hora']),
            'motivo': f['motivo'],
            'estado': f['estado'],
          },
      ],
      'pagina': pagina,
      'tamano': tamano,
      'total': int.parse(total.rows.first.colByName('n')!),
    });
  }

  /// E11. 409 si el veterinario ya tiene una cita agendada en ese bloque.
  Future<Response> _crearCita(Request peticion) async {
    await auth.autenticar(peticion, roles: _recepcion);
    final v = Validador(await leerJson(peticion))
      ..soloCampos({'mascota_id', 'veterinario_id', 'fecha_hora', 'motivo'});
    final mascotaId = v.entero('mascota_id', obligatorio: true);
    final veterinarioId = v.entero('veterinario_id', obligatorio: true);
    final fechaHora = v.fechaHoraAgenda('fecha_hora');
    final motivo = v.texto('motivo', obligatorio: true, min: 3, max: 200);
    v.verificar();

    final mascota = await pool.execute(
      'SELECT 1 FROM mascotas WHERE id = :id',
      {'id': mascotaId},
    );
    final veterinario = await pool.execute(
      "SELECT 1 FROM usuarios WHERE id = :id AND rol = 'veterinario' "
      'AND activo = TRUE',
      {'id': veterinarioId},
    );
    if (mascota.rows.isEmpty || veterinario.rows.isEmpty) {
      throw ApiError(422, 'Referencia invalida');
    }

    const ocupado = 'El veterinario no esta disponible en ese horario';
    final params = {
      'mascota': mascotaId,
      'veterinario': veterinarioId,
      'fecha': fechaHoraMysql(fechaHora!),
      'motivo': motivo,
    };
    final choque = await pool.execute(
      "SELECT 1 FROM citas WHERE veterinario_id = :veterinario "
      "AND fecha_hora = :fecha AND estado = 'agendada'",
      params,
    );
    if (choque.rows.isNotEmpty) throw ApiError(409, ocupado);

    final IResultSet r;
    try {
      r = await pool.execute(
        'INSERT INTO citas (mascota_id, veterinario_id, fecha_hora, motivo) '
        'VALUES (:mascota, :veterinario, :fecha, :motivo)',
        params,
      );
    } on MySQLServerException catch (e) {
      // Dos recepcionistas agendando el mismo bloque a la vez.
      if (e.errorCode == _errorDuplicado) throw ApiError(409, ocupado);
      rethrow;
    }
    final id = r.lastInsertID.toInt();
    return respuestaJson(
      201,
      _citaJson((await _buscarCita(id))!),
      cabeceras: {'location': '/api/citas/$id'},
    );
  }

  /// E12. Sin diagnostico: para eso esta E15.
  Future<Response> _verCita(Request peticion, String idRuta) async {
    final usuario = await auth.autenticar(peticion);
    final cita = await _citaExistente(idRuta);
    _verificarDuenoDeCita(usuario, cita);
    return respuestaJson(200, _citaJson(cita));
  }

  /// E13. Solo desde "agendada". La cita no se borra.
  Future<Response> _cancelarCita(Request peticion, String idRuta) async {
    await auth.autenticar(peticion, roles: _recepcion);
    final cita = await _citaExistente(idRuta);
    final r = await pool.execute(
      "UPDATE citas SET estado = 'cancelada' "
      "WHERE id = :id AND estado = 'agendada'",
      {'id': cita['id']},
    );
    if (r.affectedRows == BigInt.zero) {
      throw ApiError(409, 'La cita no se puede cancelar en su estado actual');
    }
    return respuestaJson(
      200,
      _citaJson((await _buscarCita(int.parse(cita['id']!)))!),
    );
  }

  // ----------------------------------------------------------- Atencion

  Future<Map<String, Object?>?> _atencionJson(
    int citaId, [
    Ejecutar? ejecutar,
  ]) async {
    final ej = ejecutar ?? pool.execute;
    final r = await ej(
      'SELECT id, cita_id, diagnostico, tratamiento, fecha_registro '
      'FROM atenciones WHERE cita_id = :cita',
      {'cita': citaId},
    );
    if (r.rows.isEmpty) return null;
    final a = r.rows.first.assoc();
    final recetas = await ej(
      'SELECT medicamento, dosis, duracion_dias FROM recetas '
      'WHERE atencion_id = :id ORDER BY id',
      {'id': a['id']},
    );
    return {
      'cita_id': int.parse(a['cita_id']!),
      'diagnostico': a['diagnostico'],
      'tratamiento': a['tratamiento'],
      'medicamentos': [
        for (final m in recetas.filas)
          {
            'medicamento': m['medicamento'],
            'dosis': m['dosis'],
            'duracion_dias': int.parse(m['duracion_dias']!),
          },
      ],
      'fecha_registro': deMysqlAIso(a['fecha_registro']),
    };
  }

  static Future<void> _insertarRecetas(
    MySQLConnection conn,
    int atencionId,
    List<Map<String, Object>> medicamentos,
  ) async {
    for (final m in medicamentos) {
      await conn.execute(
        'INSERT INTO recetas (atencion_id, medicamento, dosis, duracion_dias) '
        'VALUES (:atencion, :medicamento, :dosis, :dias)',
        {
          'atencion': atencionId,
          'medicamento': m['medicamento'],
          'dosis': m['dosis'],
          'dias': m['duracion_dias'],
        },
      );
    }
  }

  /// E14. Solo el veterinario de la cita; la cita pasa a "atendida".
  Future<Response> _registrarAtencion(Request peticion, String idRuta) async {
    final usuario = await auth.autenticar(peticion, roles: _soloVeterinario);
    final cita = await _citaExistente(idRuta);
    _verificarVeterinarioDeCita(usuario, cita);

    final v = Validador(await leerJson(peticion))
      ..soloCampos({'diagnostico', 'tratamiento', 'medicamentos'});
    final diagnostico = v.texto(
      'diagnostico',
      obligatorio: true,
      min: 5,
      max: 2000,
    );
    final tratamiento = v.texto('tratamiento', max: 2000);
    final medicamentos = v.medicamentos('medicamentos') ?? [];
    v.verificar();

    const noAdmite = 'La cita no admite una atencion';
    final citaId = int.parse(cita['id']!);
    final atencion = await _transaccion((conn) async {
      final r = await conn.execute(
        "UPDATE citas SET estado = 'atendida' "
        "WHERE id = :id AND estado = 'agendada'",
        {'id': citaId},
      );
      if (r.affectedRows == BigInt.zero) throw ApiError(409, noAdmite);
      final IResultSet ins;
      try {
        ins = await conn.execute(
          'INSERT INTO atenciones (cita_id, diagnostico, tratamiento) '
          'VALUES (:cita, :diagnostico, :tratamiento)',
          {
            'cita': citaId,
            'diagnostico': diagnostico,
            'tratamiento': tratamiento,
          },
        );
      } on MySQLServerException catch (e) {
        if (e.errorCode == _errorDuplicado) throw ApiError(409, noAdmite);
        rethrow;
      }
      await _insertarRecetas(conn, ins.lastInsertID.toInt(), medicamentos);
      return _atencionJson(citaId, conn.execute);
    });
    return respuestaJson(
      201,
      atencion,
      cabeceras: {'location': '/api/citas/$citaId/atencion'},
    );
  }

  /// E15. La recepcionista siempre recibe 403.
  Future<Response> _verAtencion(Request peticion, String idRuta) async {
    final usuario = await auth.autenticar(
      peticion,
      roles: {'dueno', 'veterinario', 'administrador'},
    );
    final cita = await _citaExistente(idRuta);
    _verificarDuenoDeCita(usuario, cita);
    final atencion = await _atencionJson(int.parse(cita['id']!));
    if (atencion == null) {
      throw ApiError(404, 'La cita no tiene atencion registrada');
    }
    return respuestaJson(200, atencion);
  }

  /// E16. Si se envia "medicamentos", reemplaza la receta completa.
  Future<Response> _corregirAtencion(Request peticion, String idRuta) async {
    final usuario = await auth.autenticar(peticion, roles: _soloVeterinario);
    final cita = await _citaExistente(idRuta);
    _verificarVeterinarioDeCita(usuario, cita);
    final citaId = int.parse(cita['id']!);
    final existente = await pool.execute(
      'SELECT id FROM atenciones WHERE cita_id = :cita',
      {'cita': citaId},
    );
    if (existente.rows.isEmpty) {
      throw ApiError(404, 'La cita no tiene atencion registrada');
    }
    final atencionId = int.parse(existente.rows.first.colByName('id')!);

    final v = Validador(await leerJson(peticion))
      ..soloCampos({'diagnostico', 'tratamiento', 'medicamentos'});
    if (v.datos.isEmpty) {
      v.error('cuerpo', 'Envie al menos un campo a corregir.');
    }
    final diagnostico = v.texto('diagnostico', min: 5, max: 2000);
    if (v.tiene('diagnostico') && v.datos['diagnostico'] == null) {
      v.error('diagnostico', 'No puede ser nulo.');
    }
    final tratamiento = v.texto('tratamiento', max: 2000);
    final medicamentos = v.medicamentos('medicamentos');
    v.verificar();

    final atencion = await _transaccion((conn) async {
      final cambios = <String>[];
      final params = <String, dynamic>{'id': atencionId};
      if (v.tiene('diagnostico')) {
        cambios.add('diagnostico = :diagnostico');
        params['diagnostico'] = diagnostico;
      }
      if (v.tiene('tratamiento')) {
        cambios.add('tratamiento = :tratamiento');
        params['tratamiento'] = tratamiento;
      }
      if (cambios.isNotEmpty) {
        await conn.execute(
          'UPDATE atenciones SET ${cambios.join(', ')} WHERE id = :id',
          params,
        );
      }
      if (medicamentos != null) {
        await conn.execute('DELETE FROM recetas WHERE atencion_id = :id', {
          'id': atencionId,
        });
        await _insertarRecetas(conn, atencionId, medicamentos);
      }
      return _atencionJson(citaId, conn.execute);
    });
    return respuestaJson(200, atencion);
  }
}

/// Un id de ruta no numerico o gigante se trata como inexistente (404).
int? _idRuta(String texto) =>
    RegExp(r'^\d{1,10}$').hasMatch(texto) ? int.tryParse(texto) : null;
