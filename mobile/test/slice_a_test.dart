import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gym_bro/main.dart';

class FakeApi extends Api {
  bool published = false;
  bool other = false, blocked = false, reported = false;
  int sessions = 0;
  Map? workout;
  @override Future<dynamic> call(String method, String path, [Object? body]) async {
    if (path == '/me/summary') return {'handle': 'alice', 'sessions': sessions, 'publications': published ? 1 : 0};
    if (path == '/exercises') return [{'name': 'Squat', 'category': 'Jambes', 'unit': 'kg'}, {'name': 'Tractions', 'category': 'Dos', 'unit': 'kg'}];
    if (path == '/feed') return (published || other) && !blocked ? [{'id': 'post-1', 'title': 'Leg day', 'author': 'alice', 'sport': 'STRENGTH', 'date': '2026-10-17'}] : [];
    if (path == '/sessions' && method == 'GET') return [];
    if (path == '/sessions' && method == 'POST') { sessions++; workout = body as Map; return {'id': 'session-1', 'status': 'DRAFT'}; }
    if (path == '/sessions/session-1' && method == 'PUT') return {};
    if (path == '/sessions/session-1/complete') return {'id': 'session-1', 'title': 'Leg day', 'status': 'COMPLETED', 'workout': workout};
    if (path == '/sessions/session-1/posts') { published = true; return {'id': 'post-1'}; }
    if (path == '/posts/post-1') return {'id': 'post-1', 'title': 'Leg day', 'author': 'alice', if (other) 'authorId': 'alice-id', 'sport': 'STRENGTH', 'exerciseCount': 1, 'date': '2026-10-17'};
    if (path == '/posts/post-1/reports') { reported = true; return {'id': 'report-1'}; }
    if (path == '/users/alice-id/block') { blocked = true; return {'blocked': true}; }
    throw StateError('Unexpected $method $path');
  }
}

class StartupApi extends Api {
  bool offline = false, unauthorized = false;
  Completer<dynamic>? pendingMe;
  int calls = 0;
  @override Future<dynamic> call(String method, String path, [Object? body]) async {
    calls++;
    if (offline) throw StateError('network down');
    if (unauthorized) throw ApiUnauthorized();
    if (path == '/me') return pendingMe?.future ?? {'id': 'alice'};
    if (path == '/me/summary') return {'handle': 'alice', 'sessions': 0, 'publications': 0};
    if (path == '/feed' || path == '/sessions') return [];
    throw StateError('Unexpected $method $path');
  }
}

void main() {
  test('diagnostic allowlist excludes exception payloads and unknown phases', () {
    final error = PlatformException(code: 'private-token', message: 'private-draft', details: 'private-email');
    expect(startupDiagnostic('prefs.open', error),
      'Gym Bro $diagnosticBuild · prefs.open · PlatformException · D-OPEN-ERROR · native:unknown');
    expect(startupDiagnostic('private-email', error),
      'Gym Bro $diagnosticBuild · unknown · PlatformException · D-OTHER-ERROR · native:unknown');
  });
  test('native cause chain retains known categories and discards payloads', () {
    expect(classifyJavaCauseChain(['java.lang.RuntimeException', 'java.io.StreamCorruptedException']),
      'RuntimeException>StreamCorruptedException');
    expect(classifyJavaCauseChain(['java.lang.RuntimeException', 'private-token.private-email']),
      'RuntimeException>Unknown');
    expect(classifyJavaCauseChain(['private-draft', 'java.lang.SecurityException', 'private-token']),
      'Unknown>SecurityException>Unknown');
    expect(classifyJavaCauseChain(['java.lang.IllegalArgumentException', 'java.io.InvalidClassException', 'java.lang.NumberFormatException', 'java.lang.SecurityException']),
      'IllegalArgumentException>InvalidClassException>NumberFormatException');
  });
  test('PlatformException code is only surfaced from a fixed list', () {
    expect(startupDiagnostic('prefs.open', PlatformException(code: 'channel-error', message: 'private-email')),
      'Gym Bro $diagnosticBuild · prefs.open · PlatformException · D-OPEN-ERROR · native:channel-error');
    expect(startupDiagnostic('prefs.open', PlatformException(code: 'null-error', details: 'private-token')),
      'Gym Bro $diagnosticBuild · prefs.open · PlatformException · D-OPEN-ERROR · native:null-error');
  });
  testWidgets('plugin exception screen excludes payload and retains stored draft', (tester) async {
    SharedPreferences.setMockInitialValues({'draft:alice': 'private-draft'});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(GymApp(openPreferences: () async =>
      throw PlatformException(code: 'private-token', message: 'private-email', details: 'private-draft')));
    await tester.pumpAndSettle();
    expect(find.textContaining('prefs.open · PlatformException · D-OPEN-ERROR · native:unknown'), findsOneWidget);
    expect(find.textContaining('private-token'), findsNothing);
    expect(find.textContaining('private-email'), findsNothing);
    expect(find.textContaining('private-draft'), findsNothing);
    expect(prefs.getString('draft:alice'), 'private-draft');
  });
  testWidgets('storage error leaves spinner and allows safe retry without losing draft', (tester) async {
    SharedPreferences.setMockInitialValues({'draft:alice': '{"title":"Saved"}'});
    final prefs = await SharedPreferences.getInstance();
    var attempts = 0;
    await tester.pumpWidget(GymApp(openPreferences: () async {
      if (attempts++ == 0) throw StateError('plugin unavailable');
      return prefs;
    }));
    await tester.pumpAndSettle();
    expect(find.text('Réessayer'), findsOneWidget);
    expect(find.textContaining('$diagnosticBuild · prefs.open · StateError · D-OPEN-ERROR'), findsOneWidget);
    expect(find.textContaining('plugin unavailable'), findsNothing);
    expect(find.text('Copier le diagnostic'), findsOneWidget);
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(find.text('Connexion'), findsWidgets);
    expect(prefs.getString('draft:alice'), '{"title":"Saved"}');
  });
  testWidgets('storage that never completes times out and retry can recover', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final stuck = Completer<SharedPreferences>();
    var attempts = 0;
    await tester.pumpWidget(GymApp(openPreferences: () => attempts++ == 0 ? stuck.future : Future.value(prefs)));
    await tester.pump(const Duration(seconds: 9));
    expect(find.text('Réessayer'), findsOneWidget);
    expect(find.textContaining('$diagnosticBuild · prefs.open · TimeoutException · D-OPEN-TIMEOUT'), findsOneWidget);
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(find.text('Connexion'), findsWidgets);
    stuck.complete(prefs);
    await tester.pump();
    expect(find.text('Connexion'), findsWidgets);
  });
  testWidgets('read and post-401 removal identify phases without values', (tester) async {
    SharedPreferences.setMockInitialValues({'token': 'private-token', 'userId': 'alice', 'draft:alice': 'private-draft'});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(GymApp(openPreferences: () async => prefs,
      readPreference: (prefs, key) => key == 'token' ? throw StateError('private-token') : prefs.getString(key)));
    await tester.pumpAndSettle();
    expect(find.textContaining('prefs.read.token · StateError · D-READ-ERROR'), findsOneWidget);
    expect(find.textContaining('private-token'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(GymApp(api: StartupApi()..unauthorized = true,
      openPreferences: () async => prefs,
      removePreference: (prefs, key) async { throw StateError('private-draft'); }));
    await tester.pumpAndSettle();
    expect(find.textContaining('prefs.remove.token · StateError · D-REMOVE-ERROR'), findsOneWidget);
    expect(find.textContaining('private-draft'), findsNothing);
    expect(prefs.getString('draft:alice'), 'private-draft');
  });
  testWidgets('network exception identifies validation phase without token', (tester) async {
    SharedPreferences.setMockInitialValues({'token': 'private-token', 'userId': 'alice'});
    await tester.pumpWidget(GymApp(api: StartupApi()..offline = true));
    await tester.pumpAndSettle();
    expect(find.textContaining('api.me · StateError · D-NETWORK-ERROR'), findsOneWidget);
    expect(find.textContaining('private-token'), findsNothing);
  });
  testWidgets('cached token network outage is recoverable; anonymous startup needs no network', (tester) async {
    SharedPreferences.setMockInitialValues({'token': 'cached', 'userId': 'alice', 'draft:alice': '{"title":"Saved"}'});
    final prefs = await SharedPreferences.getInstance();
    final api = StartupApi()..offline = true;
    await tester.pumpWidget(GymApp(api: api, openPreferences: () async => prefs));
    await tester.pumpAndSettle();
    expect(find.text('Réessayer'), findsOneWidget);
    expect(prefs.getString('token'), 'cached');
    expect(prefs.getString('draft:alice'), '{"title":"Saved"}');
    api.offline = false;
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(find.text('GYM BRO'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    SharedPreferences.setMockInitialValues({});
    final anonymous = StartupApi()..offline = true;
    await tester.pumpWidget(GymApp(api: anonymous));
    await tester.pumpAndSettle();
    expect(find.text('Connexion'), findsWidgets);
    expect(anonymous.calls, 0);
  });
  testWidgets('cached token 401 returns login, preserving the draft', (tester) async {
    SharedPreferences.setMockInitialValues({'token': 'expired', 'userId': 'alice', 'draft:alice': '{"title":"Saved"}'});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(GymApp(api: StartupApi()..unauthorized = true, openPreferences: () async => prefs));
    await tester.pumpAndSettle();
    expect(find.text('Connexion'), findsWidgets);
    expect(prefs.getString('token'), isNull);
    expect(prefs.getString('draft:alice'), '{"title":"Saved"}');
  });
  testWidgets('stalled token validation times out then retry restores feed', (tester) async {
    SharedPreferences.setMockInitialValues({'token': 'cached', 'userId': 'alice'});
    final api = StartupApi()..pendingMe = Completer<dynamic>();
    await tester.pumpWidget(GymApp(api: api));
    await tester.pump();
    await tester.pump(const Duration(seconds: 26));
    expect(find.text('Réessayer'), findsOneWidget);
    api.pendingMe = null;
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Pas encore de séances publiques ici.'), findsOneWidget);
  });
  test('API network timeout fails with an actionable message', () async {
    final api = Api(clientFactory: () => MockClient((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      return http.Response('{}', 200);
    }), timeout: const Duration(milliseconds: 10));
    await expectLater(api.call('GET', '/feed'), throwsA(predicate((e) =>
      '$e'.contains('Réseau indisponible') && '$e'.contains('Réessayer'))));
  });
  test('401 is distinguishable from temporary network outage', () async {
    final api = Api(clientFactory: () => MockClient((_) async => http.Response('', 401)));
    await expectLater(api.call('GET', '/me'), throwsA(isA<ApiUnauthorized>()));
  });
  testWidgets('registration and feed-first shell', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const GymApp());
    await tester.pumpAndSettle();
    expect(find.text('Connexion'), findsWidgets);
    await tester.tap(find.text('Créer un compte'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('handle')), findsOneWidget);
  });
  test('draft survives store reopening without another account reading it', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await DraftStore.open();
    await store.save('user-a', {'clientId': 'stable', 'title': 'Test'});
    final reopened = await DraftStore.open();
    expect(reopened.read('user-a')?['clientId'], 'stable');
    expect(reopened.read('user-b'), isNull);
  });
  testWidgets('private completion requires explicit publication; feed opens detail', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await DraftStore.open();
    final api = FakeApi();
    await tester.pumpWidget(MaterialApp(home: HomeScreen(api: api, store: store, userId: 'alice', onLogout: () async {})));
    await tester.pumpAndSettle();
    expect(find.textContaining('Pas encore de séances publiques ici.'), findsOneWidget);
    await tester.tap(find.text('Commencer une séance'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('workout-title')), 'Leg day');
    await tester.enterText(find.widgetWithText(TextField, 'Exercice'), 'Squat');
    await tester.enterText(find.widgetWithText(TextField, 'Répétitions'), '5');
    await tester.enterText(find.widgetWithText(TextField, 'Charge (kg)'), '80');
    await tester.pumpAndSettle();
    expect(store.read('alice')?['title'], 'Leg day');
    tester.testTextInput.hide();
    await tester.scrollUntilVisible(find.text('Ajouter une série'), 220, scrollable: find.descendant(of: find.byType(WorkoutScreen), matching: find.byType(Scrollable)).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajouter une série'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Répétitions').last, '6');
    await tester.enterText(find.widgetWithText(TextField, 'Charge (kg)').last, '85');
    await tester.pumpAndSettle();
    expect(((store.read('alice')?['exercises'] as List).first['sets'] as List).length, 2);
    await tester.scrollUntilVisible(find.text('Terminer en privé'), 250, scrollable: find.descendant(of: find.byType(WorkoutScreen), matching: find.byType(Scrollable)).first);
    await tester.tap(find.text('Terminer en privé'));
    await tester.pumpAndSettle();
    expect(api.published, false);
    expect(((api.workout!['exercises'] as List).first['sets'] as List).length, 2);
    expect(find.text('Enregistrée dans votre historique privé. La publication est facultative.'), findsOneWidget);
    await tester.tap(find.text('Publier publiquement'));
    await tester.pumpAndSettle();
    expect(api.published, false);
    await tester.tap(find.text('Confirmer la publication'));
    await tester.pumpAndSettle();
    expect(api.published, true);
    await tester.tap(find.text('Retour à l’accueil'));
    await tester.pumpAndSettle();
    expect(find.text('Leg day'), findsOneWidget);
    await tester.ensureVisible(find.text('Leg day'));
    await tester.tap(find.text('Leg day'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 exercice(s)'), findsOneWidget);
  });
  testWidgets('another account can report and block a public post', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final api = FakeApi()..other = true;
    await tester.pumpWidget(MaterialApp(home: HomeScreen(api: api, store: await DraftStore.open(), userId: 'bob-id', onLogout: () async {})));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Leg day'));
    await tester.tap(find.text('Leg day'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Signaler'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Motif'), 'Contenu à vérifier');
    await tester.tap(find.text('Envoyer'));
    await tester.pumpAndSettle();
    expect(api.reported, true);
    await tester.ensureVisible(find.text('Leg day'));
    await tester.tap(find.text('Leg day'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bloquer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bloquer').last);
    await tester.pumpAndSettle();
    expect(api.blocked, true);
    expect(find.textContaining('Pas encore de séances publiques ici.'), findsOneWidget);
  });
  testWidgets('two exercises and checked sets survive leaving and reopening before private completion', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final api = FakeApi(), store = await DraftStore.open();
    await tester.pumpWidget(MaterialApp(home: WorkoutScreen(api: api, store: store, userId: 'alice')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('workout-title')), 'Dos et jambes');
    await tester.tap(find.text('Squat'));
    await tester.enterText(find.widgetWithText(TextField, 'Répétitions'), '5');
    await tester.enterText(find.widgetWithText(TextField, 'Charge (kg)'), '80');
    tester.testTextInput.hide();
    await tester.scrollUntilVisible(find.text('Série validée'), 220,
      scrollable: find.descendant(of: find.byType(WorkoutScreen), matching: find.byType(Scrollable)).first);
    await tester.drag(find.descendant(of: find.byType(WorkoutScreen), matching: find.byType(Scrollable)).first, const Offset(0, -140));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Série validée'));
    await tester.scrollUntilVisible(find.text('Ajouter un exercice'), 220,
      scrollable: find.descendant(of: find.byType(WorkoutScreen), matching: find.byType(Scrollable)).first);
    await tester.tap(find.text('Ajouter un exercice'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('exercise-1')), 'Tractions');
    await tester.enterText(find.widgetWithText(TextField, 'Répétitions').last, '8');
    await tester.enterText(find.widgetWithText(TextField, 'Charge (kg)').last, '0');
    await tester.pumpAndSettle();
    expect((store.read('alice')?['exercises'] as List).length, 2);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(MaterialApp(home: WorkoutScreen(api: api, store: store, userId: 'alice')));
    await tester.pumpAndSettle();
    expect(((store.read('alice')?['exercises'] as List).first['sets'] as List).first['checked'], true);
    await tester.scrollUntilVisible(find.byKey(const Key('exercise-1')), 250,
      scrollable: find.descendant(of: find.byType(WorkoutScreen), matching: find.byType(Scrollable)).first);
    expect(find.byKey(const Key('exercise-1')), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Terminer en privé'), 250,
      scrollable: find.descendant(of: find.byType(WorkoutScreen), matching: find.byType(Scrollable)).first);
    await tester.tap(find.text('Terminer en privé'));
    await tester.pumpAndSettle();
    expect((api.workout?['exercises'] as List).length, 2);
    expect(api.published, false);
    expect(store.read('alice'), isNull);
  });
}
