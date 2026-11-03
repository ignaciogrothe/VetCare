import 'package:flutter/material.dart';

import '../estado_sesion.dart';
import 'citas_pantallas.dart';
import 'comun.dart';
import 'mascotas_pantallas.dart';
import 'personal_pantalla.dart';

/// Pantalla principal: las pestañas dependen del rol (hoja 6-Matriz acceso).
class InicioPantalla extends StatefulWidget {
  const InicioPantalla({super.key});

  @override
  State<InicioPantalla> createState() => _InicioPantallaState();
}

class _InicioPantallaState extends State<InicioPantalla> {
  int _pestana = 0;

  @override
  Widget build(BuildContext context) {
    final sesion = SesionScope.of(context);
    final usuario = sesion.usuario!;

    final pestanas = <(String, IconData, Widget)>[
      ('Mascotas', Icons.pets, const MascotasLista()),
      ('Citas', Icons.event, const CitasLista()),
      if (usuario.esAdministrador)
        ('Personal', Icons.badge, const PersonalPantalla()),
    ];
    final actual = _pestana.clamp(0, pestanas.length - 1);

    return Scaffold(
      appBar: AppBar(
        title: Text(pestanas[actual].$1),
        actions: [
          Center(
            child: Text(
              '${usuario.nombre} · ${capitalizar(usuario.rol)}',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
            onPressed: sesion.cerrar,
          ),
        ],
      ),
      body: IndexedStack(
        index: actual,
        children: [for (final p in pestanas) p.$3],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: actual,
        onDestinationSelected: (i) => setState(() => _pestana = i),
        destinations: [
          for (final p in pestanas)
            NavigationDestination(icon: Icon(p.$2), label: p.$1),
        ],
      ),
    );
  }
}
