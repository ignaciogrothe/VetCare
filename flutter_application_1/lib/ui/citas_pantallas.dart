import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/modelos.dart';
import '../estado_sesion.dart';
import 'atencion_pantalla.dart';
import 'comun.dart';

/// E10. Un dueño ve solo las citas de sus mascotas. Nunca muestra diagnóstico.
class CitasLista extends StatefulWidget {
  const CitasLista({super.key});

  @override
  State<CitasLista> createState() => _CitasListaState();
}

class _CitasListaState extends State<CitasLista> {
  final _items = <CitaResumen>[];
  String? _estado;
  DateTime? _fecha;
  int _pagina = 0;
  bool _hayMas = true;
  bool _cargando = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _recargar());
  }

  Future<void> _recargar() async {
    _items.clear();
    _pagina = 0;
    _hayMas = true;
    await _cargarMas();
  }

  Future<void> _cargarMas() async {
    if (_cargando || !_hayMas) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final p = await SesionScope.leer(context).api.citas(
        estado: _estado,
        fecha: _fecha == null ? null : fechaApi(_fecha!),
        pagina: _pagina + 1,
      );
      setState(() {
        _items.addAll(p.items);
        _pagina = p.pagina;
        _hayMas = p.hayMas;
      });
    } catch (e) {
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _elegirFecha() async {
    final hoy = DateTime.now();
    final f = await showDatePicker(
      context: context,
      firstDate: DateTime(hoy.year - 5),
      lastDate: DateTime(hoy.year + 2),
      initialDate: _fecha ?? hoy,
    );
    if (f == null) return;
    setState(() => _fecha = f);
    _recargar();
  }

  Future<void> _abrir(Widget pantalla) async {
    final cambio = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => pantalla));
    if (cambio == true) _recargar();
  }

  @override
  Widget build(BuildContext context) {
    final usuario = SesionScope.of(context).usuario!;
    return Scaffold(
      floatingActionButton: usuario.esRecepcion
          ? FloatingActionButton.extended(
              onPressed: () => _abrir(const CitaFormulario()),
              icon: const Icon(Icons.add),
              label: const Text('Agendar'),
            )
          : null,
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                InputChip(
                  avatar: const Icon(Icons.calendar_today, size: 18),
                  label: Text(_fecha == null ? 'Fecha' : formatoFecha(_fecha!)),
                  selected: _fecha != null,
                  onPressed: _elegirFecha,
                  onDeleted: _fecha == null
                      ? null
                      : () {
                          setState(() => _fecha = null);
                          _recargar();
                        },
                ),
                const SizedBox(width: 8),
                for (final e in [null, ...estadosCita])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(e == null ? 'Todas' : capitalizar(e)),
                      selected: _estado == e,
                      onSelected: (_) {
                        setState(() => _estado = e);
                        _recargar();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(child: _lista()),
        ],
      ),
    );
  }

  Widget _lista() {
    if (_error != null && _items.isEmpty) {
      return ErrorCarga(error: _error!, reintentar: _recargar);
    }
    if (_items.isEmpty) {
      return _cargando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _recargar,
              child: ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(child: Text('No hay citas')),
                ],
              ),
            );
    }
    return RefreshIndicator(
      onRefresh: _recargar,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 88),
        itemCount: _items.length + (_hayMas ? 1 : 0),
        itemBuilder: (context, i) {
          if (i == _items.length) {
            return Padding(
              padding: const EdgeInsets.all(12),
              child: Center(
                child: _cargando
                    ? const CircularProgressIndicator()
                    : OutlinedButton(
                        onPressed: _cargarMas,
                        child: const Text('Cargar más'),
                      ),
              ),
            );
          }
          final c = _items[i];
          return ListTile(
            leading: const CircleAvatar(child: Icon(Icons.event)),
            title: Text(formatoFechaHora(c.fechaHora)),
            subtitle: Text(
              c.motivo,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: EstadoCitaChip(c.estado),
            onTap: () => _abrir(CitaDetalle(id: c.id)),
          );
        },
      ),
    );
  }
}

/// E12. Detalle de la cita (sin diagnóstico), con las acciones de cada rol:
/// cancelar (E13), registrar atención (E14) y ver atención (E15).
class CitaDetalle extends StatefulWidget {
  const CitaDetalle({super.key, required this.id});

  final int id;

  @override
  State<CitaDetalle> createState() => _CitaDetalleState();
}

class _CitaDetalleState extends State<CitaDetalle> {
  late Future<Cita> _cita;
  bool _cambio = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cita = SesionScope.leer(context).api.cita(widget.id);
  }

  void _recargar() =>
      setState(() => _cita = SesionScope.leer(context).api.cita(widget.id));

  Future<void> _cancelar() async {
    if (!await confirmar(context, '¿Cancelar esta cita?')) return;
    if (!mounted) return;
    try {
      await SesionScope.leer(context).api.cancelarCita(widget.id);
      if (!mounted) return;
      _cambio = true;
      mostrarMensaje(context, 'Cita cancelada');
      _recargar();
    } catch (e) {
      if (mounted) mostrarError(context, e);
    }
  }

  Future<void> _registrarAtencion(Cita c) async {
    final registrada = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AtencionFormulario(cita: c)),
    );
    if (registrada == true) {
      _cambio = true;
      _recargar();
    }
  }

  @override
  Widget build(BuildContext context) {
    final usuario = SesionScope.of(context).usuario!;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_cambio);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Cita')),
        body: FutureBuilder<Cita>(
          future: _cita,
          builder: (context, snap) {
            if (snap.hasError) {
              return ErrorCarga(error: snap.error!, reintentar: _recargar);
            }
            final c = snap.data;
            if (c == null) {
              return const Center(child: CircularProgressIndicator());
            }
            final agendada = c.estado == 'agendada';
            final esSuVeterinario =
                usuario.esVeterinario && c.veterinario.id == usuario.id;
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        formatoFechaHora(c.fechaHora),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    EstadoCitaChip(c.estado),
                  ],
                ),
                const SizedBox(height: 16),
                Dato('Mascota', c.mascota.nombre),
                Dato('Veterinario', c.veterinario.nombre),
                Dato('Motivo', c.motivo),
                const SizedBox(height: 24),
                if (agendada && esSuVeterinario)
                  FilledButton.icon(
                    onPressed: () => _registrarAtencion(c),
                    icon: const Icon(Icons.medical_services),
                    label: const Text('Registrar atención'),
                  ),
                if (c.estado == 'atendida' && usuario.veDiagnosticos)
                  FilledButton.tonalIcon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AtencionDetalle(cita: c),
                      ),
                    ),
                    icon: const Icon(Icons.description),
                    label: const Text('Ver diagnóstico y receta'),
                  ),
                if (agendada && usuario.esRecepcion) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _cancelar,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                    icon: const Icon(Icons.event_busy),
                    label: const Text('Cancelar cita'),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// E11. Agenda una hora: mascota (E05), veterinario (E04), bloque de 30 min.
class CitaFormulario extends StatefulWidget {
  const CitaFormulario({super.key});

  @override
  State<CitaFormulario> createState() => _CitaFormularioState();
}

class _CitaFormularioState extends State<CitaFormulario> {
  final _form = GlobalKey<FormState>();
  final _motivo = TextEditingController();
  late Future<(List<Mascota>, List<Referencia>)> _opciones;
  int? _mascotaId;
  int? _veterinarioId;
  DateTime _dia = DateTime.now().add(const Duration(days: 1));
  String? _bloque;
  bool _enviando = false;

  /// Bloques de atención de 08:00 a 19:30.
  static final _bloques = [
    for (var h = 8; h < 20; h++)
      for (final m in ['00', '30']) '${h.toString().padLeft(2, '0')}:$m',
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _opciones = _cargarOpciones();
  }

  Future<(List<Mascota>, List<Referencia>)> _cargarOpciones() async {
    final api = SesionScope.leer(context).api;
    final veterinarios = api.veterinarios();
    final mascotas = <Mascota>[];
    for (var pagina = 1; ; pagina++) {
      final p = await api.mascotas(pagina: pagina, tamano: 50);
      mascotas.addAll(p.items);
      if (!p.hayMas) break;
    }
    return (mascotas, await veterinarios);
  }

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  DateTime? get _fechaHora {
    final b = _bloque;
    if (b == null) return null;
    final partes = b.split(':');
    return DateTime(
      _dia.year,
      _dia.month,
      _dia.day,
      int.parse(partes[0]),
      int.parse(partes[1]),
    );
  }

  Future<void> _elegirDia() async {
    final hoy = DateTime.now();
    final f = await showDatePicker(
      context: context,
      firstDate: DateTime(hoy.year, hoy.month, hoy.day),
      lastDate: hoy.add(const Duration(days: 365)),
      initialDate: _dia,
    );
    if (f != null) setState(() => _dia = f);
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _enviando = true);
    try {
      await SesionScope.leer(context).api.crearCita(
        mascotaId: _mascotaId!,
        veterinarioId: _veterinarioId!,
        fechaHora: _fechaHora!,
        motivo: _motivo.text.trim(),
      );
      if (!mounted) return;
      mostrarMensaje(context, 'Cita agendada');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) mostrarError(context, e);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Agendar cita')),
      body: FutureBuilder(
        future: _opciones,
        builder: (context, snap) {
          if (snap.hasError) {
            return ErrorCarga(
              error: snap.error!,
              reintentar: () => setState(() => _opciones = _cargarOpciones()),
            );
          }
          final datos = snap.data;
          if (datos == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final (mascotas, veterinarios) = datos;
          return Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                DropdownButtonFormField<int>(
                  initialValue: _mascotaId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Mascota',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final m in mascotas)
                      DropdownMenuItem(
                        value: m.id,
                        child: Text('${m.nombre} (${m.dueno.nombre})'),
                      ),
                  ],
                  onChanged: (v) => setState(() => _mascotaId = v),
                  validator: (v) => v == null ? 'Elija la mascota' : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  initialValue: _veterinarioId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Veterinario',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final v in veterinarios)
                      DropdownMenuItem(value: v.id, child: Text(v.nombre)),
                  ],
                  onChanged: (v) => setState(() => _veterinarioId = v),
                  validator: (v) => v == null ? 'Elija el veterinario' : null,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _elegirDia,
                        icon: const Icon(Icons.calendar_today),
                        label: Text(formatoFecha(_dia)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _bloque,
                        decoration: const InputDecoration(
                          labelText: 'Hora',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final b in _bloques)
                            DropdownMenuItem(value: b, child: Text(b)),
                        ],
                        onChanged: (v) => setState(() => _bloque = v),
                        validator: (_) {
                          final f = _fechaHora;
                          if (f == null) return 'Elija la hora';
                          return f.isAfter(DateTime.now())
                              ? null
                              : 'Debe ser futura';
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _motivo,
                  decoration: const InputDecoration(
                    labelText: 'Motivo',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    final n = v?.trim().length ?? 0;
                    return n < 3 || n > 200 ? 'Entre 3 y 200 caracteres' : null;
                  },
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _enviando ? null : _guardar,
                  child: const Text('Agendar'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
