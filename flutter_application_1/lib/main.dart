import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'estado_sesion.dart';
import 'pages/login.dart';
import 'ui/inicio_pantalla.dart';
import 'ui/recuperar_clave_pantalla.dart';
import 'ui/registro_pantalla.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final sesion = EstadoSesion(ApiClient());
  await sesion.cargar();
  runApp(MyApp(sesion: sesion));
}

class MyApp extends StatelessWidget {
  MyApp({super.key, required this.sesion});

  final EstadoSesion sesion;
  final _navegador = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return SesionScope(
      sesion: sesion,
      child: MaterialApp(
        title: 'VetCare',
        debugShowCheckedModeBanner: false,
        navigatorKey: _navegador,
        theme: ThemeData(
          colorScheme: .fromSeed(seedColor: VetColors.primary),
          scaffoldBackgroundColor: VetColors.background,
        ),
        // Rutas que usa la pantalla de login.
        routes: {
          '/register': (_) => const RegistroPantalla(),
          '/forgot-password': (_) => const RecuperarClavePantalla(),
        },
        home: ListenableBuilder(
          listenable: sesion,
          // Al cerrar sesion (o recibir 401) se vuelve al login, quitando
          // las pantallas que hubiera abiertas encima.
          builder: (context, _) {
            if (sesion.usuario != null) return const InicioPantalla();
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => _navegador.currentState?.popUntil((r) => r.isFirst),
            );
            return LoginScreen(
              onSubmit: (email, clave, recordar) =>
                  sesion.iniciar(email, clave, recordar: recordar),
            );
          },
        ),
      ),
    );
  }
}
