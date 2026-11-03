// login.dart
// Pantalla de inicio de sesion - VetCare (veterinaria online)
//
// Sin dependencias externas: solo Flutter/Material.
// La ilustracion (perro + gato) y las huellitas se dibujan con CustomPainter.
//
// Uso:
//   MaterialApp(
//     routes: {
//       '/': (_) => LoginScreen(
//             onSubmit: (email, password, remember) async {
//               // await authApi.login(email, password);
//             },
//           ),
//       '/forgot-password': (_) => const ForgotPasswordScreen(),
//       '/register': (_) => const RegisterScreen(),
//     },
//   );

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';

/// Paleta y tipografia del diseno.
class VetColors {
  static const primary = Color(0xFF0E6B5C);
  static const ring = Color(0xFFD7EEE8);
  static const background = Color(0xFFF4F8F6);
  static const ink = Color(0xFF12302A);
  static const muted = Color(0xFF52625D);
  static const hint = Color(0xFF6B7A75);
  static const border = Color(0xFFD3E1DC);
  static const heroCircle = Color(0xFF1A8270);
  static const heroSubtitle = Color(0xFFCFE8E1);
  static const error = Color(0xFFB3261E);
  static const errorBg = Color(0xFFFCE8E6);

  /// Registra 'PlusJakartaSans' en pubspec.yaml para usarla.
  /// Si no esta registrada, Flutter usa la fuente del sistema.
  static const fontFamily = 'PlusJakartaSans';
}

TextStyle _t(double size, FontWeight weight, Color color, {double? height}) =>
    TextStyle(
      fontFamily: VetColors.fontFamily,
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
    );

/// Firma del callback que conecta con la API.
/// Lanza una excepcion si el login falla.
typedef LoginCallback = Future<void> Function(
  String email,
  String password,
  bool remember,
);

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.onSubmit});

  final LoginCallback? onSubmit;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _passwordFocus = FocusNode();

  bool _obscure = true;
  bool _remember = true;
  bool _loading = false;
  String? _error;

  static final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _loading = true);
    try {
      await widget.onSubmit?.call(
        _emailCtrl.text.trim(),
        _passwordCtrl.text,
        _remember,
      );
      TextInput.finishAutofillContext();
    } catch (e) {
      // 401 (credenciales) y cualquier otro error muestran el mismo texto;
      // solo se distingue cuando el servidor no responde.
      final sinConexion = e is ApiException && e.codigo == 0;
      if (mounted) {
        setState(() => _error = sinConexion
            ? 'No pudimos conectar con el servidor. Revisa tu conexión.'
            : 'No pudimos iniciar sesión. Revisa tu correo y contraseña.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  InputDecoration _decoration({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    OutlineInputBorder border(Color c, [double w = 1.5]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c, width: w),
        );
    return InputDecoration(
      hintText: hint,
      hintStyle: _t(15, FontWeight.w400, VetColors.hint),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(vertical: 17),
      prefixIcon: Icon(icon, size: 20),
      prefixIconColor: WidgetStateColor.resolveWith((s) =>
          s.contains(WidgetState.focused) ? VetColors.primary : VetColors.muted),
      suffixIcon: suffix,
      enabledBorder: border(VetColors.border),
      focusedBorder: border(VetColors.primary, 1.8),
      errorBorder: border(VetColors.error),
      focusedErrorBorder: border(VetColors.error, 1.8),
      errorStyle: _t(12.5, FontWeight.w500, VetColors.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: VetColors.background,
        body: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(child: _Hero()),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 26, 24, 0),
                child: _buildForm(),
              ),
            ),
            SliverFillRemaining(
              hasScrollBody: false,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: _buildFooter(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('¡Hola de nuevo!',
                style: _t(26, FontWeight.w800, VetColors.ink)),
            const SizedBox(height: 6),
            Text(
              'Ingresa para ver las citas, vacunas y el historial de tu mascota.',
              style: _t(14.5, FontWeight.w400, VetColors.muted, height: 1.5),
            ),
            const SizedBox(height: 22),

            if (_error != null) ...[
              _ErrorBanner(message: _error!),
              const SizedBox(height: 16),
            ],

            _LabeledField(
              label: 'Correo electrónico',
              child: TextFormField(
                controller: _emailCtrl,
                enabled: !_loading,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                autocorrect: false,
                style: _t(15, FontWeight.w500, VetColors.ink),
                cursorColor: VetColors.primary,
                decoration: _decoration(
                  hint: 'tu@correo.cl',
                  icon: Icons.mail_outline_rounded,
                ),
                validator: (v) {
                  final value = (v ?? '').trim();
                  if (value.isEmpty) return 'Ingresa tu correo';
                  if (!_emailRegex.hasMatch(value)) return 'Correo no válido';
                  return null;
                },
                onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
              ),
            ),
            const SizedBox(height: 18),

            _LabeledField(
              label: 'Contraseña',
              child: TextFormField(
                controller: _passwordCtrl,
                focusNode: _passwordFocus,
                enabled: !_loading,
                obscureText: _obscure,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                style: _t(15, FontWeight.w500, VetColors.ink),
                cursorColor: VetColors.primary,
                decoration: _decoration(
                  hint: '••••••••',
                  icon: Icons.lock_outline_rounded,
                  suffix: IconButton(
                    tooltip:
                        _obscure ? 'Mostrar contraseña' : 'Ocultar contraseña',
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 20,
                      color: VetColors.muted,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: (v) =>
                    (v ?? '').isEmpty ? 'Ingresa tu contraseña' : null,
                onFieldSubmitted: (_) => _submit(),
              ),
            ),
            const SizedBox(height: 10),

            Row(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => setState(() => _remember = !_remember),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: Checkbox(
                            value: _remember,
                            activeColor: VetColors.primary,
                            side: const BorderSide(
                                color: VetColors.muted, width: 1.5),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(5)),
                            onChanged: (v) =>
                                setState(() => _remember = v ?? false),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('Recordarme',
                            style: _t(13.5, FontWeight.w500,
                                const Color(0xFF3C4C47))),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _loading
                      ? null
                      : () => Navigator.of(context)
                          .pushNamed('/forgot-password'),
                  style: TextButton.styleFrom(
                    foregroundColor: VetColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    minimumSize: const Size(44, 44),
                  ),
                  child: Text('¿Olvidaste tu contraseña?',
                      style: _t(13.5, FontWeight.w700, VetColors.primary)),
                ),
              ],
            ),
            const SizedBox(height: 14),

            FilledButton(
              onPressed: _loading ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: VetColors.primary,
                disabledBackgroundColor: VetColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(56),
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4, color: Colors.white),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Iniciar sesión',
                            style: _t(16, FontWeight.w700, Colors.white)),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward_rounded, size: 18),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('¿No tienes cuenta?',
                style: _t(14, FontWeight.w400, VetColors.muted)),
            TextButton(
              onPressed: _loading
                  ? null
                  : () => Navigator.of(context).pushNamed('/register'),
              style: TextButton.styleFrom(
                foregroundColor: VetColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: const Size(44, 44),
              ),
              child: Text('Regístrate',
                  style: _t(14, FontWeight.w700, VetColors.primary)),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Componentes
// ---------------------------------------------------------------------------

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: _t(13.5, FontWeight.w700, VetColors.ink)),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: VetColors.errorBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 20, color: VetColors.error),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message,
                  style: _t(13.5, FontWeight.w500, VetColors.error,
                      height: 1.4)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(36)),
      child: Container(
        color: VetColors.primary,
        padding: EdgeInsets.fromLTRB(24, top + 20, 24, 8),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Huellitas decorativas (blanco al 12%)
            const Positioned(left: -6, top: 98, child: _Paw(size: 34, angle: -24)),
            const Positioned(left: 20, top: 162, child: _Paw(size: 24, angle: -10)),
            const Positioned(right: -2, top: 66, child: _Paw(size: 28, angle: 22)),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _Logo(),
                  const SizedBox(height: 12),
                  Semantics(
                    label: 'Un perro y un gato sonriendo',
                    image: true,
                    child: const SizedBox(
                      width: 240,
                      height: 180,
                      child: CustomPaint(painter: _PetsPainter()),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: const _Paw(size: 22, color: VetColors.primary),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('VetCare',
                style: _t(21, FontWeight.w800, Colors.white, height: 1.1)),
            Text('Veterinaria online',
                style: _t(12, FontWeight.w500, VetColors.heroSubtitle)),
          ],
        ),
      ],
    );
  }
}

class _Paw extends StatelessWidget {
  const _Paw({
    required this.size,
    this.angle = 0,
    this.color = const Color(0x1FFFFFFF),
  });

  final double size;
  final double angle; // grados
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Transform.rotate(
        angle: angle * math.pi / 180,
        child: CustomPaint(
          size: Size.square(size),
          painter: _PawPainter(color),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Painters
// ---------------------------------------------------------------------------

class _PawPainter extends CustomPainter {
  const _PawPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    final p = Paint()..color = color;
    canvas.drawOval(
        Rect.fromCenter(center: const Offset(12, 16), width: 10, height: 8.4),
        p);
    canvas.drawCircle(const Offset(6, 10), 2.2, p);
    canvas.drawCircle(const Offset(9.5, 6), 2.2, p);
    canvas.drawCircle(const Offset(14.5, 6), 2.2, p);
    canvas.drawCircle(const Offset(18, 10), 2.2, p);
  }

  @override
  bool shouldRepaint(_PawPainter old) => old.color != color;
}

/// Perro y gato. Coordenadas en un lienzo de 240x180.
class _PetsPainter extends CustomPainter {
  const _PetsPainter();

  static const _ink = Color(0xFF2B1D16);
  static const _white = Color(0xFFFFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 240, size.height / 180);

    Paint fill(Color c) => Paint()..color = c;
    Paint stroke(Color c, double w) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round;

    void oval(double cx, double cy, double rx, double ry, Paint p,
        [double deg = 0]) {
      canvas.save();
      canvas.translate(cx, cy);
      if (deg != 0) canvas.rotate(deg * math.pi / 180);
      canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2),
          p);
      canvas.restore();
    }

    Path tri(double x1, double y1, double x2, double y2, double x3,
            double y3) =>
        Path()
          ..moveTo(x1, y1)
          ..lineTo(x2, y2)
          ..lineTo(x3, y3)
          ..close();

    // Fondo
    canvas.drawCircle(const Offset(122, 104), 80, fill(VetColors.heroCircle));

    // --- Gato ---
    canvas.drawPath(tri(136, 96, 139, 58, 162, 80), fill(const Color(0xFFE9935B)));
    canvas.drawPath(tri(196, 96, 193, 58, 170, 80), fill(const Color(0xFFE9935B)));
    canvas.drawPath(tri(141, 86, 142, 68, 154, 79), fill(const Color(0xFFF8CDB4)));
    canvas.drawPath(tri(191, 86, 190, 68, 178, 79), fill(const Color(0xFFF8CDB4)));
    canvas.drawCircle(const Offset(166, 112), 36, fill(const Color(0xFFF0A06A)));
    canvas.drawPath(
      Path()
        ..moveTo(158, 80)
        ..relativeQuadraticBezierTo(3, 8, 0, 14)
        ..moveTo(166, 78)
        ..relativeQuadraticBezierTo(3, 9, 0, 16)
        ..moveTo(174, 80)
        ..relativeQuadraticBezierTo(3, 8, 0, 14),
      stroke(const Color(0xFFD9824B), 3),
    );
    oval(166, 124, 17, 12, fill(const Color(0xFFFBE6D6)));
    oval(153, 108, 3.6, 5.2, fill(_ink));
    oval(179, 108, 3.6, 5.2, fill(_ink));
    canvas.drawCircle(const Offset(154.2, 106), 1.3, fill(_white));
    canvas.drawCircle(const Offset(180.2, 106), 1.3, fill(_white));
    canvas.drawPath(tri(162, 118, 170, 118, 166, 123), fill(const Color(0xFFC9574A)));
    canvas.drawPath(
      Path()
        ..moveTo(166, 123)
        ..relativeQuadraticBezierTo(-4, 5, -9, 2)
        ..moveTo(166, 123)
        ..relativeQuadraticBezierTo(4, 5, 9, 2),
      stroke(_ink, 2),
    );
    final whisker = stroke(const Color(0xFFFBE6D6), 1.6);
    canvas.drawLine(const Offset(150, 121), const Offset(132, 118), whisker);
    canvas.drawLine(const Offset(150, 126), const Offset(132, 128), whisker);
    canvas.drawLine(const Offset(182, 121), const Offset(200, 118), whisker);
    canvas.drawLine(const Offset(182, 126), const Offset(200, 128), whisker);

    // --- Perro ---
    oval(50, 102, 17, 34, fill(const Color(0xFFB97A4E)), 20);
    oval(120, 102, 17, 34, fill(const Color(0xFFB97A4E)), -20);
    canvas.drawCircle(const Offset(85, 108), 42, fill(const Color(0xFFE9B98A)));
    oval(85, 127, 23, 17, fill(const Color(0xFFFBEBDD)));
    canvas.drawPath(
      Path()
        ..moveTo(80, 133)
        ..relativeQuadraticBezierTo(5, 9, 10, 0)
        ..close(),
      fill(const Color(0xFFE86F6F)),
    );
    oval(85, 118, 8.5, 6, fill(_ink));
    canvas.drawPath(
      Path()
        ..moveTo(85, 124)
        ..lineTo(85, 129)
        ..relativeQuadraticBezierTo(-6, 5, -11, 1)
        ..moveTo(85, 129)
        ..relativeQuadraticBezierTo(6, 5, 11, 1),
      stroke(_ink, 2.2),
    );
    canvas.drawCircle(const Offset(70, 99), 4.8, fill(_ink));
    canvas.drawCircle(const Offset(100, 99), 4.8, fill(_ink));
    canvas.drawCircle(const Offset(71.6, 97.4), 1.5, fill(_white));
    canvas.drawCircle(const Offset(101.6, 97.4), 1.5, fill(_white));

    // --- Insignia cruz veterinaria ---
    canvas.drawCircle(const Offset(208, 42), 17, fill(_white));
    final cross = stroke(VetColors.primary, 4.5);
    canvas.drawLine(const Offset(208, 33), const Offset(208, 51), cross);
    canvas.drawLine(const Offset(199, 42), const Offset(217, 42), cross);
  }

  @override
  bool shouldRepaint(_PetsPainter old) => false;
}