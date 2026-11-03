import 'package:bcrypt/bcrypt.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:mysql_client/mysql_client.dart';
import 'package:shelf/shelf.dart';

import 'errores.dart';

const segundosToken = 3600;

class Usuario {
  Usuario.desdeFila(Map<String, String?> f)
    : id = int.parse(f['id']!),
      nombre = f['nombre']!,
      email = f['email']!,
      rol = f['rol']!,
      telefono = f['telefono'],
      activo = f['activo'] == '1',
      claveHash = f['clave_hash'];

  final int id;
  final String nombre;
  final String email;
  final String rol;
  final String? telefono;
  final bool activo;
  final String? claveHash;

  bool get esDueno => rol == 'dueno';

  /// La clave nunca sale en ninguna respuesta.
  Map<String, Object?> aJson() => {
    'id': id,
    'nombre': nombre,
    'email': email,
    'telefono': telefono,
    'rol': rol,
    'activo': activo,
  };
}

class Auth {
  Auth(this.pool, String secreto) : _clave = SecretKey(secreto);

  final MySQLConnectionPool pool;
  final SecretKey _clave;

  static String hashClave(String clave) =>
      BCrypt.hashpw(clave, BCrypt.gensalt());

  static bool claveCorrecta(String clave, String hash) =>
      BCrypt.checkpw(clave, hash);

  String emitirToken(Usuario u) => JWT(
    {'rol': u.rol},
    subject: '${u.id}',
  ).sign(_clave, expiresIn: const Duration(seconds: segundosToken));

  Future<Usuario?> buscarPorEmail(String email) async {
    final r = await pool.execute(
      'SELECT * FROM usuarios WHERE email = :email',
      {'email': email},
    );
    return r.rows.isEmpty ? null : Usuario.desdeFila(r.rows.first.assoc());
  }

  /// Valida la cabecera Authorization (401) y, si se indican [roles],
  /// que el usuario tenga uno de ellos (403). El rol se lee de la base de
  /// datos, no del token, para que un cambio de rol o una baja surtan efecto
  /// de inmediato.
  Future<Usuario> autenticar(Request peticion, {Set<String>? roles}) async {
    final cabecera = peticion.headers['authorization'];
    if (cabecera == null || !cabecera.startsWith('Bearer ')) {
      throw ApiError(401, 'Falta el token de acceso');
    }
    final JWT jwt;
    try {
      jwt = JWT.verify(cabecera.substring(7).trim(), _clave);
    } on JWTExpiredException {
      throw ApiError(401, 'El token expiro');
    } on JWTException {
      throw ApiError(401, 'Token invalido');
    }
    final id = int.tryParse(jwt.subject ?? '');
    final r = id == null
        ? null
        : await pool.execute('SELECT * FROM usuarios WHERE id = :id', {
            'id': id,
          });
    if (r == null || r.rows.isEmpty) throw ApiError(401, 'Token invalido');
    final usuario = Usuario.desdeFila(r.rows.first.assoc());
    if (!usuario.activo) throw ApiError(401, 'Token invalido');
    if (roles != null && !roles.contains(usuario.rol)) {
      throw ApiError(403, 'No tiene permiso para esta operacion');
    }
    return usuario;
  }
}
