import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_bro/main.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  Future<void> registration(WidgetTester tester, Api api) async {
    await tester.pumpWidget(MaterialApp(home: AuthScreen(api: api, onSuccess: (_) async {})));
    await tester.tap(find.text('Créer un compte'));
    await tester.pumpAndSettle();
  }

  testWidgets('registration validates required fields without contacting API', (tester) async {
    var calls = 0;
    await registration(tester, Api(clientFactory: () => MockClient((_) async {
      calls++;
      return http.Response('{}', 201);
    })));
    await tester.tap(find.text('Créer mon compte'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('Pseudo requis.'), findsOneWidget);
    expect(find.text('Email requis.'), findsOneWidget);
    expect(find.text('Mot de passe requis.'), findsOneWidget);
  });

  testWidgets('registration rejects bad pseudo/email/short and long password, clears error on edit', (tester) async {
    var calls = 0;
    await registration(tester, Api(clientFactory: () => MockClient((_) async {
      calls++;
      return http.Response('{}', 201);
    })));
    await tester.enterText(find.byKey(const Key('handle')), 'Inv@lide');
    await tester.enterText(find.byKey(const Key('email')), 'not-an-email');
    await tester.enterText(find.byKey(const Key('password')), 'court');
    await tester.tap(find.text('Créer mon compte'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('Pseudo : 3 à 32 lettres minuscules, chiffres ou _.'), findsOneWidget);
    expect(find.text('Saisissez une adresse email valide.'), findsOneWidget);
    expect(find.text('Mot de passe : 12 à 128 caractères.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('handle')), 'athlete_1');
    await tester.enterText(find.byKey(const Key('email')), 'athlete@example.test');
    await tester.enterText(find.byKey(const Key('password')), 'x' * 129);
    await tester.pump();
    expect(find.text('Pseudo : 3 à 32 lettres minuscules, chiffres ou _.'), findsNothing);
    expect(find.text('Saisissez une adresse email valide.'), findsNothing);
    expect(find.text('Mot de passe : 12 à 128 caractères.'), findsOneWidget);
    await tester.tap(find.text('Créer mon compte'));
    await tester.pumpAndSettle();
    expect(calls, 0);
  });

  testWidgets('valid registration sends normalized fields once and keeps input after server 400', (tester) async {
    var calls = 0;
    await registration(tester, Api(clientFactory: () => MockClient((request) async {
      calls++;
      expect(request.url.path, '/api/v1/auth/register');
      expect(request.body, contains('athlete_1'));
      return http.Response('private-server-body', 400);
    })));
    await tester.enterText(find.byKey(const Key('handle')), ' athlete_1 ');
    await tester.enterText(find.byKey(const Key('email')), ' athlete@example.test ');
    await tester.enterText(find.byKey(const Key('password')), 'abcdefghijkl');
    await tester.tap(find.text('Créer mon compte'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('Inscription refusée. Vérifiez les champs et réessayez.'), findsOneWidget);
    expect(find.textContaining('HTTP 400'), findsNothing);
    expect(find.textContaining('private-server-body'), findsNothing);
    expect(tester.widget<TextField>(find.byKey(const Key('email'))).controller!.text, ' athlete@example.test ');
  });

  testWidgets('login 401, registration 409 and network failures have safe actionable messages', (tester) async {
    for (final (register, status, message) in [
      (false, 401, 'Identifiants incorrects.'),
      (true, 409, 'Inscription impossible avec ces informations. Essayez un autre pseudo ou email.'),
    ]) {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(MaterialApp(home: AuthScreen(api: Api(clientFactory: () => MockClient((_) async => http.Response('private', status))), onSuccess: (_) async {})));
      if (register) await tester.tap(find.text('Créer un compte'));
      await tester.pumpAndSettle();
      if (register) await tester.enterText(find.byKey(const Key('handle')), 'athlete_1');
      await tester.enterText(find.byKey(const Key('email')), 'athlete@example.test');
      await tester.enterText(find.byKey(const Key('password')), 'abcdefghijkl');
      await tester.tap(find.widgetWithText(FilledButton, register ? 'Créer mon compte' : 'Connexion'));
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget);
      expect(find.textContaining('private'), findsNothing);
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(MaterialApp(home: AuthScreen(api: Api(
      clientFactory: () => MockClient((_) async => throw http.ClientException('private network detail'))), onSuccess: (_) async {})));
    await tester.enterText(find.byKey(const Key('email')), 'athlete@example.test');
    await tester.enterText(find.byKey(const Key('password')), 'abcdefghijkl');
    await tester.tap(find.widgetWithText(FilledButton, 'Connexion'));
    await tester.pumpAndSettle();
    expect(find.textContaining('réessayez'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
