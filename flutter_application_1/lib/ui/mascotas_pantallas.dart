import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/modelos.dart';
import '../estado_sesion.dart';
import 'comun.dart';

const _iconosEspecie = {
  'perro': Icons.pets,
  'gato': Icons.pets,
  'ave': Icons.flutter_dash,
  'conejo': Icons.cruelty_free,
  'otro': Icons.help_outline,
};

/// E05. Un dueño ve solo sus mascotas; el personal ve todas.
class MascotasLista extends StatefulWidget {
  const MascotasLista({super.key});

  @override
  State<MascotasLista> createState() => _MascotasListaState();
}

class _MascotasListaState extends State<MascotasLista> {
  final _items = <Mascota>[];
  String? _especie;
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
      final p = await SesionScope.leer(context).api
          .mascotas(especie: _especie, pagina: _pagina + 1);
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
              onPressed: () => _abrir(const MascotaFormulario()),
              icon: const Icon(Icons.add),
              label: const Text('Mascota'),
            )
          : null,
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                for (final e in [null, ...especies])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(e == null ? 'Todas' : capitalizar(e)),
                      selected: _especie == e,
                      onSelected: (_) {
                        setState(() => _especie = e);
                        _recargar();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(child: _lista(usuario)),
        ],
      ),
    );
  }

  Widget _lista(UsuarioSesion usuario) {
    if (_error != null && _items.isEmpty) {
      return ErrorCarga(error: _error!, reintentar: _recargar);
    }
    if (_items.isEmpty) {
      return _cargando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _recargar,
              child: ListView(
                children: [
                  const SizedBox(height: 120),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      usuario.esDueno
                          ? 'Aún no tiene mascotas registradas.\nEn recepción '
                                'indique su número de cliente: ${usuario.id}'
                          : 'No hay mascotas registradas',
                      textAlign: TextAlign.center,
                    ),
                  ),
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
          final m = _items[i];
          return ListTile(
            leading: CircleAvatar(child: Icon(_iconosEspecie[m.especie])),
            title: Text(m.nombre),
            subtitle: Text(
              usuario.esDueno
                  ? '${capitalizar(m.especie)} · ${m.sexo}'
                  : '${capitalizar(m.especie)} · dueño: ${m.dueno.nombre}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _abrir(MascotaDetalle(id: m.id)),
          );
        },
      ),
    );
  }
}

/// E07. Ficha de la mascota, con editar (E08) y eliminar (E09) según rol.
class MascotaDetalle extends StatefulWidget {
  const MascotaDetalle({super.key, required this.id});

  final int id;

  @override
  State<MascotaDetalle> createState() => _MascotaDetalleState();
}

class _MascotaDetalleState extends State<MascotaDetalle> {
  late Future<Mascota> _mascota;
  bool _cambio = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _mascota = SesionScope.leer(context).api.mascota(widget.id);
  }

  void _recargar() => setState(
    () => _mascota = SesionScope.leer(context).api.mascota(widget.id),
  );

  Future<void> _editar(Mascota m) async {
    final cambio = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => MascotaFormulario(mascota: m)),
    );
    if (cambio == true) {
      _cambio = true;
      _recargar();
    }
  }

  Future<void> _eliminar(Mascota m) async {
    if (!await confirmar(context, '¿Eliminar a ${m.nombre}?')) return;
    if (!mounted) return;
    try {
      await SesionScope.leer(context).api.eliminarMascota(m.id);
      if (!mounted) return;
      mostrarMensaje(context, 'Mascota eliminada');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) mostrarError(context, e);
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
        appBar: AppBar(title: const Text('Ficha de la mascota')),
        body: FutureBuilder<Mascota>(
          future: _mascota,
          builder: (context, snap) {
            if (snap.hasError) {
              return ErrorCarga(error: snap.error!, reintentar: _recargar);
            }
            final m = snap.data;
            if (m == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      child: Icon(_iconosEspecie[m.especie], size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        m.nombre,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Dato('Especie', capitalizar(m.especie)),
                Dato('Sexo', capitalizar(m.sexo)),
                Dato('Nacimiento', formatoFechaApi(m.fechaNacimiento)),
                Dato(
                  'Peso',
                  m.pesoKg == null ? '—' : '${m.pesoKg!.toString()} kg',
                ),
                Dato('Dueño', '${m.dueno.nombre} (id ${m.dueno.id})'),
                const SizedBox(height: 24),
                if (usuario.esRecepcion)
                  OutlinedButton.icon(
                    onPressed: () => _editar(m),
                    icon: const Icon(Icons.edit),
                    label: const Text('Editar nombre o peso'),
                  ),
                if (usuario.esAdministrador) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _eliminar(m),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                    icon: const Icon(Icons.delete),
                    label: const Text('Eliminar mascota'),
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

/// E06 (crear) y E08 (editar: solo nombre y peso).
class MascotaFormulario extends StatefulWidget {
  const MascotaFormulario({super.key, this.mascota});

  final Mascota? mascota;

  @override
  State<MascotaFormulario> createState() => _MascotaFormularioState();
}

class _MascotaFormularioState extends State<MascotaFormulario> {
  final _form = GlobalKey<FormState>();
  late final _nombre = TextEditingController(text: widget.mascota?.nombre);
  late final _peso = TextEditingController(
    text: widget.mascota?.pesoKg?.toString(),
  );
  final _duenoId = TextEditingController();
  String _especie = especies.first;
  String _sexo = sexos.first;
  DateTime? _nacimiento;
  bool _enviando = false;

  bool get _editando => widget.mascota != null;

  @override
  void dispose() {
    _nombre.dispose();
    _peso.dispose();
    _duenoId.dispose();
    super.dispose();
  }

  double? get _pesoValor {
    final t = _peso.text.trim().replaceAll(',', '.');
    return t.isEmpty ? null : double.tryParse(t);
  }

  Future<void> _elegirNacimiento() async {
    final hoy = DateTime.now();
    final f = await showDatePicker(
      context: context,
      firstDate: DateTime(hoy.year - 40),
      lastDate: hoy,
      initialDate: _nacimiento ?? hoy,
    );
    if (f != null) setState(() => _nacimiento = f);
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _enviando = true);
    final api = SesionScope.leer(context).api;
    try {
      if (_editando) {
        final m = widget.mascota!;
        final nombre = _nombre.text.trim();
        if (nombre == m.nombre && _pesoValor == m.pesoKg) {
          Navigator.of(context).pop(false);
          return;
        }
        await api.modificarMascota(
          m.id,
          nombre: nombre != m.nombre ? nombre : null,
          pesoKg: _pesoValor != m.pesoKg ? _pesoValor : null,
        );
      } else {
        await api.crearMascota(
          nombre: _nombre.text.trim(),
          especie: _especie,
          sexo: _sexo,
          fechaNacimiento: _nacimiento == null ? null : fechaApi(_nacimiento!),
          pesoKg: _pesoValor,
          duenoId: int.parse(_duenoId.text.trim()),
        );
      }
      if (!mounted) return;
      mostrarMensaje(
        context,
        _editando ? 'Mascota actualizada' : 'Mascota registrada',
      );
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
      appBar: AppBar(
        title: Text(_editando ? 'Editar mascota' : 'Nueva mascota'),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: _nombre,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                final n = v?.trim().length ?? 0;
                return n < 2 || n > 60 ? 'Entre 2 y 60 caracteres' : null;
              },
            ),
            const SizedBox(height: 16),
            if (!_editando) ...[
              DropdownButtonFormField<String>(
                initialValue: _especie,
                decoration: const InputDecoration(
                  labelText: 'Especie',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final e in especies)
                    DropdownMenuItem(value: e, child: Text(capitalizar(e))),
                ],
                onChanged: (v) => setState(() => _especie = v!),
              ),
              const SizedBox(height: 16),
              SegmentedButton<String>(
                segments: [
                  for (final s in sexos)
                    ButtonSegment(value: s, label: Text(capitalizar(s))),
                ],
                selected: {_sexo},
                onSelectionChanged: (s) => setState(() => _sexo = s.first),
              ),
              const SizedBox(height: 16),
              ListTile(
                shape: RoundedRectangleBorder(
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                title: const Text('Fecha de nacimiento (opcional)'),
                subtitle: Text(
                  _nacimiento == null ? '—' : formatoFecha(_nacimiento!),
                ),
                trailing: const Icon(Icons.calendar_today),
                onTap: _elegirNacimiento,
              ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _peso,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Peso en kg (opcional)',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                if ((v ?? '').trim().isEmpty) return null;
                final p = _pesoValor;
                return p == null || p <= 0 || p > 200
                    ? 'Mayor que 0 y hasta 200'
                    : null;
              },
            ),
            if (!_editando) ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: _duenoId,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'ID del dueño',
                  helperText:
                      'Id de la cuenta creada por el dueño al registrarse',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => int.tryParse(v?.trim() ?? '') == null
                    ? 'Ingrese el id numérico del dueño'
                    : null,
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _enviando ? null : _guardar,
              child: Text(_editando ? 'Guardar cambios' : 'Registrar mascota'),
            ),
          ],
        ),
      ),
    );
  }
}
