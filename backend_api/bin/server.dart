import 'dart:io';

import 'package:mysql_client/mysql_client.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:veterinaria_api/src/api.dart';
import 'package:veterinaria_api/src/auth.dart';

/// Configuracion por variables de entorno (ver README.md).
String _env(String nombre, String defecto) =>
    Platform.environment[nombre] ?? defecto;

Future<void> main() async {
  final pool = MySQLConnectionPool(
    host: _env('DB_HOST', '127.0.0.1'),
    port: int.parse(_env('DB_PORT', '3306')),
    userName: _env('DB_USER', 'root'),
    password: _env('DB_PASSWORD', ''),
    databaseName: _env('DB_NAME', 'veterinaria'),
    maxConnections: 10,
    secure: _env('DB_SSL', 'true') == 'true',
  );

  final secreto = _env('JWT_SECRET', 'cambiar-este-secreto-en-produccion');
  final auth = Auth(pool, secreto);
  await _crearAdministradorInicial(pool);

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addHandler(VeterinariaApi(pool, auth).handler);

  final puerto = int.parse(_env('PORT', '8080'));
  // 0.0.0.0 para que el emulador o un telefono en la misma red lleguen.
  final servidor = await io.serve(handler, InternetAddress.anyIPv4, puerto);
  stdout.writeln(
    'API veterinaria escuchando en http://${servidor.address.host}:$puerto',
  );
}

/// Sin administrador nadie podria crear personal (E03), asi que si no existe
/// ninguno se crea uno con ADMIN_EMAIL / ADMIN_CLAVE.
Future<void> _crearAdministradorInicial(MySQLConnectionPool pool) async {
  final r = await pool.execute(
    "SELECT 1 FROM usuarios WHERE rol = 'administrador' LIMIT 1",
  );
  if (r.rows.isNotEmpty) return;
  final email = _env('ADMIN_EMAIL', 'admin@clinica.cl');
  final clave = _env('ADMIN_CLAVE', 'admin12345');
  await pool.execute(
    'INSERT INTO usuarios (nombre, email, clave_hash, rol) '
    "VALUES ('Administrador', :email, :hash, 'administrador')",
    {'email': email, 'hash': Auth.hashClave(clave)},
  );
  stdout.writeln('Administrador inicial creado: $email');
}
