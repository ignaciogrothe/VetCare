import 'package:flutter/material.dart';

import '../api/modelos.dart';
import '../estado_sesion.dart';
import 'comun.dart';

/// E03. El administrador crea cuentas de veterinario, recepcionista o
/// administrador.
class PersonalPantalla extends StatefulWidget {
  const PersonalPantalla({super.key});

  @override
  State<PersonalPantalla> createState() => _PersonalPantallaState();
}

class _PersonalPantallaState extends State<PersonalPantalla> {
  final _form = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _email = TextEditingController();
  final _clave = TextEditingController();
  final _telefono = TextEditingController();
  String _rol = rolesPersonal.first;
  bool _enviando = false;
  final _creados = <Usuario>[];

  @override
  void dispose() {
    for (final c in [_nombre, _email, _clave, _telefono]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _crear() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _enviando = true);
    try {
      final u = await SesionScope.leer(context).api.crearPersonal(
        nombre: _nombre.text.trim(),
        email: _email.text.trim(),
        clave: _clave.text,
        rol: _rol,
        telefono: _telefono.text.trim(),
      );
      if (!mounted) return;
      setState(() => _creados.insert(0, u));
      _form.currentState!.reset();
      for (final c in [_nombre, _email, _clave, _telefono]) {
        c.clear();
      }
      mostrarMensaje(context, 'Cuenta creada para ${u.nombre}');
    } catch (e) {
      if (mounted) mostrarError(context, e);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Nueva cuenta de personal',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _rol,
            decoration: const InputDecoration(
              labelText: 'Rol',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final r in rolesPersonal)
                DropdownMenuItem(value: r, child: Text(capitalizar(r))),
            ],
            onChanged: (v) => setState(() => _rol = v!),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _nombre,
            decoration: const InputDecoration(
              labelText: 'Nombre',
              border: OutlineInputBorder(),
            ),
            validator: (v) {
              final n = v?.trim().length ?? 0;
              return n < 2 || n > 80 ? 'Entre 2 y 80 caracteres' : null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
            ),
            validator: (v) => v == null || !v.contains('@')
                ? 'Ingrese un email válido'
                : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _clave,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Clave inicial (mínimo 8)',
              border: OutlineInputBorder(),
            ),
            validator: (v) =>
                (v?.length ?? 0) < 8 ? 'Mínimo 8 caracteres' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _telefono,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Teléfono (opcional)',
              border: OutlineInputBorder(),
            ),
            validator: (v) {
              final t = v?.trim() ?? '';
              return t.isNotEmpty && !RegExp(r'^\d{8,15}$').hasMatch(t)
                  ? 'Solo dígitos, entre 8 y 15'
                  : null;
            },
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _enviando ? null : _crear,
            child: const Text('Crear cuenta'),
          ),
          if (_creados.isNotEmpty) ...[
            const Divider(height: 40),
            Text(
              'Creadas en esta sesión',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            for (final u in _creados)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person),
                title: Text(u.nombre),
                subtitle: Text(
                  '${capitalizar(u.rol)} · ${u.email} · id ${u.id}',
                ),
              ),
          ],
        ],
      ),
    );
  }
}
