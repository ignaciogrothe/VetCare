import 'package:flutter/material.dart';

import '../api/api_client.dart';

void mostrarError(BuildContext context, Object error) {
  final texto = error is ApiException ? error.textoCompleto : '$error';
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
}

void mostrarMensaje(BuildContext context, String texto) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(texto)));
}

Future<bool> confirmar(BuildContext context, String pregunta) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(pregunta),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sí'),
          ),
        ],
      ),
    ) ??
    false;

String _dos(int n) => n.toString().padLeft(2, '0');

String formatoFecha(DateTime f) => '${_dos(f.day)}-${_dos(f.month)}-${f.year}';

String formatoFechaHora(DateTime f) =>
    '${formatoFecha(f)} ${_dos(f.hour)}:${_dos(f.minute)}';

/// "2021-03-15" -> "15-03-2021"
String formatoFechaApi(String? fecha) =>
    fecha == null ? '—' : formatoFecha(DateTime.parse(fecha));

String capitalizar(String texto) =>
    texto.isEmpty ? texto : texto[0].toUpperCase() + texto.substring(1);

class EstadoCitaChip extends StatelessWidget {
  const EstadoCitaChip(this.estado, {super.key});

  final String estado;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final (fondo, texto) = switch (estado) {
      'agendada' => (esquema.primaryContainer, esquema.onPrimaryContainer),
      'atendida' => (esquema.tertiaryContainer, esquema.onTertiaryContainer),
      _ => (esquema.surfaceContainerHighest, esquema.onSurfaceVariant),
    };
    return Chip(
      label: Text(capitalizar(estado), style: TextStyle(color: texto)),
      backgroundColor: fondo,
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
    );
  }
}

/// Muestra un error de carga con boton para reintentar.
class ErrorCarga extends StatelessWidget {
  const ErrorCarga({super.key, required this.error, required this.reintentar});

  final Object error;
  final VoidCallback reintentar;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48),
          const SizedBox(height: 12),
          Text(
            error is ApiException
                ? (error as ApiException).textoCompleto
                : '$error',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: reintentar,
            child: const Text('Reintentar'),
          ),
        ],
      ),
    ),
  );
}

/// Fila "etiqueta: valor" para las fichas de detalle.
class Dato extends StatelessWidget {
  const Dato(this.etiqueta, this.valor, {super.key});

  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(etiqueta, style: Theme.of(context).textTheme.labelLarge),
        ),
        Expanded(child: Text(valor)),
      ],
    ),
  );
}
