import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gym_bro/main.dart';

class FakeApi extends Api {
  bool published = false;
  bool other = false, blocked = false, reported = false;
  int sessions = 0;
  Map? workout;
  @override Future<dynamic> call(String method, String path, [Object? body]) async {
    if (path == '/feed') return (published || other) && !blocked ? [{'id': 'post-1', 'title': 'Leg day', 'author': 'alice', 'sport': 'STRENGTH', 'date': '2026-10-17'}] : [];
    if (path == '/sessions' && method == 'GET') return [];
    if (path == '/sessions' && method == 'POST') { sessions++; workout = body as Map; return {'id': 'session-1', 'status': 'DRAFT'}; }
    if (path == '/sessions/session-1' && method == 'PUT') return {};
    if (path == '/sessions/session-1/complete') return {'id': 'session-1', 'title': 'Leg day', 'status': 'COMPLETED'};
    if (path == '/sessions/session-1/posts') { published = true; return {'id': 'post-1'}; }
    if (path == '/posts/post-1') return {'id': 'post-1', 'title': 'Leg day', 'author': 'alice', if (other) 'authorId': 'alice-id', 'sport': 'STRENGTH', 'exerciseCount': 1, 'date': '2026-10-17'};
    if (path == '/posts/post-1/reports') { reported = true; return {'id': 'report-1'}; }
    if (path == '/users/alice-id/block') { blocked = true; return {'blocked': true}; }
    throw StateError('Unexpected $method $path');
  }
}

void main() {
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
    expect(find.text('Aucune publication publique pour le moment.'), findsOneWidget);
    await tester.tap(find.text('Nouvelle séance'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('workout-title')), 'Leg day');
    await tester.enterText(find.widgetWithText(TextField, 'Exercice'), 'Squat');
    await tester.enterText(find.widgetWithText(TextField, 'Répétitions'), '5');
    await tester.enterText(find.widgetWithText(TextField, 'Charge'), '80');
    await tester.pumpAndSettle();
    expect(store.read('alice')?['title'], 'Leg day');
    await tester.ensureVisible(find.text('Ajouter une série'));
    await tester.tap(find.text('Ajouter une série'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Répétitions').last, '6');
    await tester.enterText(find.widgetWithText(TextField, 'Charge').last, '85');
    await tester.pumpAndSettle();
    expect((store.read('alice')?['sets'] as List).length, 2);
    await tester.scrollUntilVisible(find.text('Terminer en privé'), 250, scrollable: find.descendant(of: find.byType(WorkoutScreen), matching: find.byType(Scrollable)).first);
    await tester.tap(find.text('Terminer en privé'));
    await tester.pumpAndSettle();
    expect(api.published, false);
    expect(((api.workout!['exercises'] as List).first['sets'] as List).length, 2);
    expect(find.text('Enregistrée dans votre historique privé. La publication est facultative.'), findsOneWidget);
    await tester.tap(find.text('Publier publiquement'));
    await tester.pumpAndSettle();
    expect(api.published, true);
    await tester.tap(find.text('Garder privée / Retour au feed'));
    await tester.pumpAndSettle();
    expect(find.text('Leg day'), findsOneWidget);
    await tester.tap(find.text('Leg day'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 exercice(s)'), findsOneWidget);
  });
  testWidgets('another account can report and block a public post', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final api = FakeApi()..other = true;
    await tester.pumpWidget(MaterialApp(home: HomeScreen(api: api, store: await DraftStore.open(), userId: 'bob-id', onLogout: () async {})));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leg day'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Signaler'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Motif'), 'Contenu à vérifier');
    await tester.tap(find.text('Envoyer'));
    await tester.pumpAndSettle();
    expect(api.reported, true);
    await tester.tap(find.text('Leg day'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bloquer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bloquer').last);
    await tester.pumpAndSettle();
    expect(api.blocked, true);
    expect(find.text('Aucune publication publique pour le moment.'), findsOneWidget);
  });
}
