import 'package:flutter/material.dart';

import '../estado_sesion.dart';
import 'comun.dart';

/// E02. Un dueño crea su cuenta; el servidor le asigna el rol "dueno".
class RegistroPantalla extends StatefulWidget {
  const RegistroPantalla({super.key});

  @override
  State<RegistroPantalla> createState() => _RegistroPantallaState();
}

class _RegistroPantallaState extends State<RegistroPantalla> {
  final _form = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _email = TextEditingController();
  final _clave = TextEditingController();
  final _telefono = TextEditingController();
  bool _enviando = false;

  @override
  void dispose() {
    for (final c in [_nombre, _email, _clave, _telefono]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _registrar() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _enviando = true);
    final sesion = SesionScope.leer(context);
    try {
      await sesion.api.registro(
        nombre: _nombre.text.trim(),
        email: _email.text.trim(),
        clave: _clave.text,
        telefono: _telefono.text.trim(),
      );
      await sesion.iniciar(_email.text.trim(), _clave.text);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) mostrarError(context, e);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crear cuenta')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
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
                labelText: 'Clave (mínimo 8 caracteres)',
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
              onPressed: _enviando ? null : _registrar,
              child: const Text('Crear cuenta'),
            ),
          ],
        ),
      ),
    );
  }
}
