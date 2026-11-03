import 'package:flutter/material.dart';

import '../api/modelos.dart';
import '../estado_sesion.dart';
import 'comun.dart';

/// E15. Diagnóstico y receta. Si es el veterinario de la cita, puede
/// corregirla (E16).
class AtencionDetalle extends StatefulWidget {
  const AtencionDetalle({super.key, required this.cita});

  final Cita cita;

  @override
  State<AtencionDetalle> createState() => _AtencionDetalleState();
}

class _AtencionDetalleState extends State<AtencionDetalle> {
  late Future<Atencion> _atencion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _atencion = SesionScope.leer(context).api.atencion(widget.cita.id);
  }

  void _recargar() => setState(
    () => _atencion = SesionScope.leer(context).api.atencion(widget.cita.id),
  );

  Future<void> _corregir(Atencion a) async {
    final cambio = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AtencionFormulario(cita: widget.cita, atencion: a),
      ),
    );
    if (cambio == true) _recargar();
  }

  @override
  Widget build(BuildContext context) {
    final usuario = SesionScope.of(context).usuario!;
    final textos = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text('Atención de ${widget.cita.mascota.nombre}')),
      body: FutureBuilder<Atencion>(
        future: _atencion,
        builder: (context, snap) {
          if (snap.hasError) {
            return ErrorCarga(error: snap.error!, reintentar: _recargar);
          }
          final a = snap.data;
          if (a == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Dato('Fecha cita', formatoFechaHora(widget.cita.fechaHora)),
              Dato('Veterinario', widget.cita.veterinario.nombre),
              Dato('Registrada', formatoFechaHora(a.fechaRegistro)),
              const Divider(height: 32),
              Text('Diagnóstico', style: textos.titleMedium),
              const SizedBox(height: 4),
              Text(a.diagnostico),
              const SizedBox(height: 16),
              Text('Tratamiento', style: textos.titleMedium),
              const SizedBox(height: 4),
              Text(a.tratamiento ?? '—'),
              const SizedBox(height: 16),
              Text('Receta', style: textos.titleMedium),
              if (a.medicamentos.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('Sin medicamentos'),
                ),
              for (final m in a.medicamentos)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.medication),
                  title: Text(m.medicamento),
                  subtitle: Text('${m.dosis} · ${m.duracionDias} días'),
                ),
              if (usuario.esVeterinario &&
                  widget.cita.veterinario.id == usuario.id) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => _corregir(a),
                  icon: const Icon(Icons.edit),
                  label: const Text('Corregir atención'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// E14 (registrar) y E16 (corregir). La receta se envía completa.
class AtencionFormulario extends StatefulWidget {
  const AtencionFormulario({super.key, required this.cita, this.atencion});

  final Cita cita;
  final Atencion? atencion;

  @override
  State<AtencionFormulario> createState() => _AtencionFormularioState();
}

class _FilaMedicamento {
  _FilaMedicamento([Medicamento? m])
    : nombre = TextEditingController(text: m?.medicamento),
      dosis = TextEditingController(text: m?.dosis),
      dias = TextEditingController(text: m?.duracionDias.toString());

  final TextEditingController nombre;
  final TextEditingController dosis;
  final TextEditingController dias;

  Medicamento get valor => Medicamento(
    medicamento: nombre.text.trim(),
    dosis: dosis.text.trim(),
    duracionDias: int.parse(dias.text.trim()),
  );

  void dispose() {
    nombre.dispose();
    dosis.dispose();
    dias.dispose();
  }
}

class _AtencionFormularioState extends State<AtencionFormulario> {
  final _form = GlobalKey<FormState>();
  late final _diagnostico = TextEditingController(
    text: widget.atencion?.diagnostico,
  );
  late final _tratamiento = TextEditingController(
    text: widget.atencion?.tratamiento,
  );
  late final _medicamentos = [
    for (final m in widget.atencion?.medicamentos ?? <Medicamento>[])
      _FilaMedicamento(m),
  ];
  bool _enviando = false;

  bool get _corrigiendo => widget.atencion != null;

  @override
  void dispose() {
    _diagnostico.dispose();
    _tratamiento.dispose();
    for (final f in _medicamentos) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _enviando = true);
    final api = SesionScope.leer(context).api;
    final medicamentos = [for (final f in _medicamentos) f.valor];
    try {
      if (_corrigiendo) {
        await api.corregirAtencion(
          widget.cita.id,
          diagnostico: _diagnostico.text.trim(),
          tratamiento: _tratamiento.text.trim(),
          medicamentos: medicamentos,
        );
      } else {
        await api.registrarAtencion(
          widget.cita.id,
          diagnostico: _diagnostico.text.trim(),
          tratamiento: _tratamiento.text.trim(),
          medicamentos: medicamentos,
        );
      }
      if (!mounted) return;
      mostrarMensaje(
        context,
        _corrigiendo ? 'Atención corregida' : 'Atención registrada',
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) mostrarError(context, e);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  String? _largo(String? v, int min, int max) {
    final n = v?.trim().length ?? 0;
    return n < min || n > max ? 'Entre $min y $max caracteres' : null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_corrigiendo ? 'Corregir atención' : 'Registrar atención'),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              '${widget.cita.mascota.nombre} · '
              '${formatoFechaHora(widget.cita.fechaHora)}',
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _diagnostico,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Diagnóstico',
                border: OutlineInputBorder(),
              ),
              validator: (v) => _largo(v, 5, 2000),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _tratamiento,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Tratamiento (opcional)',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v?.length ?? 0) > 2000 ? 'Hasta 2000 caracteres' : null,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Receta',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton.icon(
                  onPressed: () =>
                      setState(() => _medicamentos.add(_FilaMedicamento())),
                  icon: const Icon(Icons.add),
                  label: const Text('Medicamento'),
                ),
              ],
            ),
            for (final (i, f) in _medicamentos.indexed)
              Card(
                margin: const EdgeInsets.symmetric(vertical: 6),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: f.nombre,
                              decoration: const InputDecoration(
                                labelText: 'Medicamento',
                              ),
                              validator: (v) => _largo(v, 2, 80),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Quitar',
                            icon: const Icon(Icons.close),
                            onPressed: () => setState(
                              () => _medicamentos.removeAt(i).dispose(),
                            ),
                          ),
                        ],
                      ),
                      TextFormField(
                        controller: f.dosis,
                        decoration: const InputDecoration(
                          labelText: 'Dosis',
                          hintText: '1 comprimido cada 12 horas',
                        ),
                        validator: (v) => _largo(v, 1, 100),
                      ),
                      TextFormField(
                        controller: f.dias,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Duración (días)',
                        ),
                        validator: (v) {
                          final d = int.tryParse(v?.trim() ?? '');
                          return d == null || d < 1 || d > 90
                              ? 'Entre 1 y 90'
                              : null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _enviando ? null : _guardar,
              child: Text(_corrigiendo ? 'Guardar corrección' : 'Registrar'),
            ),
          ],
        ),
      ),
    );
  }
}
