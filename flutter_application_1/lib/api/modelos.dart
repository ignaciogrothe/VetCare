/// Modelos de la API de la veterinaria (ver backend_api/ y la hoja 5-Payloads).
library;

const especies = ['perro', 'gato', 'ave', 'conejo', 'otro'];
const sexos = ['macho', 'hembra'];
const estadosCita = ['agendada', 'atendida', 'cancelada'];
const rolesPersonal = ['veterinario', 'recepcionista', 'administrador'];

class Referencia {
  const Referencia(this.id, this.nombre);

  Referencia.fromJson(Map<String, dynamic> j)
    : id = j['id'] as int,
      nombre = j['nombre'] as String;

  final int id;
  final String nombre;
}

/// Usuario de la sesion (lo que devuelve el login).
class UsuarioSesion {
  const UsuarioSesion({
    required this.id,
    required this.nombre,
    required this.rol,
  });

  UsuarioSesion.fromJson(Map<String, dynamic> j)
    : id = j['id'] as int,
      nombre = j['nombre'] as String,
      rol = j['rol'] as String;

  final int id;
  final String nombre;
  final String rol;

  bool get esDueno => rol == 'dueno';
  bool get esVeterinario => rol == 'veterinario';
  bool get esRecepcionista => rol == 'recepcionista';
  bool get esAdministrador => rol == 'administrador';

  /// Puede registrar y editar mascotas, y agendar o cancelar citas.
  bool get esRecepcion => esRecepcionista || esAdministrador;

  /// Puede ver diagnosticos (E15).
  bool get veDiagnosticos => !esRecepcionista;

  Map<String, dynamic> toJson() => {'id': id, 'nombre': nombre, 'rol': rol};
}

class Usuario {
  Usuario.fromJson(Map<String, dynamic> j)
    : id = j['id'] as int,
      nombre = j['nombre'] as String,
      email = j['email'] as String,
      telefono = j['telefono'] as String?,
      rol = j['rol'] as String,
      activo = j['activo'] as bool;

  final int id;
  final String nombre;
  final String email;
  final String? telefono;
  final String rol;
  final bool activo;
}

class Sesion {
  Sesion.fromJson(Map<String, dynamic> j)
    : token = j['access_token'] as String,
      expiraEn = j['expira_en'] as int,
      usuario = UsuarioSesion.fromJson(j['usuario'] as Map<String, dynamic>);

  final String token;
  final int expiraEn;
  final UsuarioSesion usuario;
}

class Pagina<T> {
  Pagina.fromJson(Map<String, dynamic> j, T Function(Map<String, dynamic>) item)
    : items = (j['items'] as List)
          .map((e) => item(e as Map<String, dynamic>))
          .toList(),
      pagina = j['pagina'] as int,
      tamano = j['tamano'] as int,
      total = j['total'] as int;

  final List<T> items;
  final int pagina;
  final int tamano;
  final int total;

  bool get hayMas => pagina * tamano < total;
}

class Mascota {
  Mascota.fromJson(Map<String, dynamic> j)
    : id = j['id'] as int,
      nombre = j['nombre'] as String,
      especie = j['especie'] as String,
      sexo = j['sexo'] as String,
      fechaNacimiento = j['fecha_nacimiento'] as String?,
      pesoKg = (j['peso_kg'] as num?)?.toDouble(),
      dueno = Referencia.fromJson(j['dueno'] as Map<String, dynamic>);

  final int id;
  final String nombre;
  final String especie;
  final String sexo;
  final String? fechaNacimiento;
  final double? pesoKg;
  final Referencia dueno;
}

/// Item del listado de citas (E10).
class CitaResumen {
  CitaResumen.fromJson(Map<String, dynamic> j)
    : id = j['id'] as int,
      mascotaId = j['mascota_id'] as int,
      veterinarioId = j['veterinario_id'] as int,
      fechaHora = DateTime.parse(j['fecha_hora'] as String),
      motivo = j['motivo'] as String,
      estado = j['estado'] as String;

  final int id;
  final int mascotaId;
  final int veterinarioId;
  final DateTime fechaHora;
  final String motivo;
  final String estado;
}

/// Detalle de una cita (E11, E12, E13). Nunca trae diagnostico.
class Cita {
  Cita.fromJson(Map<String, dynamic> j)
    : id = j['id'] as int,
      mascota = Referencia.fromJson(j['mascota'] as Map<String, dynamic>),
      veterinario = Referencia.fromJson(
        j['veterinario'] as Map<String, dynamic>,
      ),
      fechaHora = DateTime.parse(j['fecha_hora'] as String),
      motivo = j['motivo'] as String,
      estado = j['estado'] as String;

  final int id;
  final Referencia mascota;
  final Referencia veterinario;
  final DateTime fechaHora;
  final String motivo;
  final String estado;
}

class Medicamento {
  const Medicamento({
    required this.medicamento,
    required this.dosis,
    required this.duracionDias,
  });

  Medicamento.fromJson(Map<String, dynamic> j)
    : medicamento = j['medicamento'] as String,
      dosis = j['dosis'] as String,
      duracionDias = j['duracion_dias'] as int;

  final String medicamento;
  final String dosis;
  final int duracionDias;

  Map<String, dynamic> toJson() => {
    'medicamento': medicamento,
    'dosis': dosis,
    'duracion_dias': duracionDias,
  };
}

/// Diagnostico y receta de una cita (E14, E15, E16).
class Atencion {
  Atencion.fromJson(Map<String, dynamic> j)
    : citaId = j['cita_id'] as int,
      diagnostico = j['diagnostico'] as String,
      tratamiento = j['tratamiento'] as String?,
      medicamentos = (j['medicamentos'] as List)
          .map((e) => Medicamento.fromJson(e as Map<String, dynamic>))
          .toList(),
      fechaRegistro = DateTime.parse(j['fecha_registro'] as String);

  final int citaId;
  final String diagnostico;
  final String? tratamiento;
  final List<Medicamento> medicamentos;
  final DateTime fechaRegistro;
}
