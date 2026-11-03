import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api/api_client.dart';
import 'api/modelos.dart';

/// Token y usuario conectado. Se guarda en el telefono para no pedir login
/// cada vez que se abre la app, hasta que el token expira.
class EstadoSesion extends ChangeNotifier {
  EstadoSesion(this.api) {
    api.alExpirarSesion = cerrar;
  }

  final ApiClient api;
  UsuarioSesion? usuario;

  static const _claveToken = 'token';
  static const _claveUsuario = 'usuario';
  static const _claveExpira = 'expira';

  Future<void> cargar() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_claveToken);
    final datos = prefs.getString(_claveUsuario);
    final expira = prefs.getInt(_claveExpira) ?? 0;
    if (token == null ||
        datos == null ||
        DateTime.now().millisecondsSinceEpoch >= expira) {
      return;
    }
    api.token = token;
    usuario = UsuarioSesion.fromJson(jsonDecode(datos) as Map<String, dynamic>);
    notifyListeners();
  }

  /// Con [recordar] en false la sesion dura solo mientras la app este abierta.
  Future<void> iniciar(
    String email,
    String clave, {
    bool recordar = true,
  }) async {
    final sesion = await api.login(email, clave);
    api.token = sesion.token;
    usuario = sesion.usuario;
    final prefs = await SharedPreferences.getInstance();
    if (!recordar) {
      await _borrarGuardado(prefs);
      notifyListeners();
      return;
    }
    await prefs.setString(_claveToken, sesion.token);
    await prefs.setString(_claveUsuario, jsonEncode(sesion.usuario.toJson()));
    await prefs.setInt(
      _claveExpira,
      DateTime.now()
          .add(Duration(seconds: sesion.expiraEn))
          .millisecondsSinceEpoch,
    );
    notifyListeners();
  }

  Future<void> cerrar() async {
    if (usuario == null && api.token == null) return;
    api.token = null;
    usuario = null;
    notifyListeners();
    await _borrarGuardado(await SharedPreferences.getInstance());
  }

  Future<void> _borrarGuardado(SharedPreferences prefs) async {
    await prefs.remove(_claveToken);
    await prefs.remove(_claveUsuario);
    await prefs.remove(_claveExpira);
  }
}

/// Da acceso a la sesion desde cualquier pantalla: `SesionScope.of(context)`.
class SesionScope extends InheritedNotifier<EstadoSesion> {
  const SesionScope({
    super.key,
    required EstadoSesion sesion,
    required super.child,
  }) : super(notifier: sesion);

  static EstadoSesion of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SesionScope>()!.notifier!;

  /// Sin suscribirse a cambios (para callbacks).
  static EstadoSesion leer(BuildContext context) =>
      context.getInheritedWidgetOfExactType<SesionScope>()!.notifier!;
}
