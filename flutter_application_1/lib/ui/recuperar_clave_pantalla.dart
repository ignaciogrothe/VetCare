import 'package:flutter/material.dart';

/// La especificacion no tiene un endpoint para recuperar la clave, asi que
/// por ahora se le indica al usuario que lo haga en la clinica.
class RecuperarClavePantalla extends StatelessWidget {
  const RecuperarClavePantalla({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recuperar contraseña')),
      body: const Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.lock_reset_rounded, size: 64),
            SizedBox(height: 16),
            Text(
              'Para restablecer tu contraseña acércate a la recepción de la '
              'clínica o llámanos. Te ayudaremos a recuperar el acceso.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
