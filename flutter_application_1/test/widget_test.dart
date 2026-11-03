import 'package:flutter_application_1/api/api_client.dart';
import 'package:flutter_application_1/estado_sesion.dart';
import 'package:flutter_application_1/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Sin sesion se muestra el login de VetCare', (tester) async {
    await tester.pumpWidget(MyApp(sesion: EstadoSesion(ApiClient())));

    expect(find.text('¡Hola de nuevo!'), findsOneWidget);
    expect(find.text('Iniciar sesión'), findsOneWidget);
  });

  test('ApiException muestra el detalle de cada campo', () {
    final e = ApiException(400, 'Datos invalidos en: precio', {
      'precio': ['Debe ser mayor o igual a 0.'],
    });
    expect(
      e.textoCompleto,
      'Datos invalidos en: precio\n• precio: Debe ser mayor o igual a 0.',
    );
  });
}
