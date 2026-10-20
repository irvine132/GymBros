import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gym_bro/main.dart';

class HyroxApi extends Api {
  final calls = <String>[];
  Map? submitted;
  bool completed = false, published = false;
  @override Future<dynamic> call(String method, String path, [Object? body]) async {
    calls.add('$method $path');
    if (path == '/feed' || path == '/templates' || path == '/me/follow-requests') return <dynamic>[];
    if (path == '/sessions' && method == 'GET') {
      return completed ? [{'id': 'hyrox1', 'title': submitted!['title'],
        'status': 'COMPLETED', 'started_at': '2026-10-19', 'published': published}] : <dynamic>[];
    }
    if (path == '/feed/following') return {'items': [], 'nextCursor': null};
    if (path == '/me/summary') return {'handle': 'athlete', 'sessions': 0, 'publications': 0};
    if (path == '/me') return {'id': 'athlete', 'handle': 'athlete', 'private': false, 'unit': 'kg'};
    if (path == '/hyrox' && method == 'POST') {
      submitted = body as Map;
      return {'id': 'hyrox1', 'clientId': submitted!['clientId'], 'title': submitted!['title'],
        'resultSchemaVersion': 3, 'status': 'DRAFT', 'workout': submitted, 'published': false};
    }
    if (path == '/hyrox/hyrox1' && method == 'PUT') { return {'id': 'hyrox1', 'status': 'DRAFT'}; }
    if (path == '/sessions/hyrox1/complete-expected') {
      completed = true;
      return {'id': 'hyrox1', 'title': submitted!['title'],
        'status': 'COMPLETED', 'resultSchemaVersion': 3, 'workout': submitted, 'published': false};
    }
    throw StateError('Unexpected $method $path');
  }
}

void main() {
  testWidgets('Hyrox RUN and STATION draft resumes, finishes privately without publishing', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final api = HyroxApi(), store = await DraftStore.open();
    await tester.pumpWidget(MaterialApp(home: HomeScreen(api: api, store: store, userId: 'athlete', onLogout: () async {})));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entraînement'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Créer une séance Hyrox'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('hyrox-title')), 'Mon entraînement Hyrox');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reprendre ma séance Hyrox'));
    await tester.pumpAndSettle();
    expect(find.text('Mon entraînement Hyrox'), findsOneWidget);
    final scroll = find.descendant(of: find.byType(ListView).last, matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.byKey(const Key('hyrox-run-distance-0')), 180, scrollable: scroll);
    await tester.enterText(find.byKey(const Key('hyrox-run-distance-0')), '1000');
    await tester.enterText(find.byKey(const Key('hyrox-run-duration-0')), '330');
    await tester.scrollUntilVisible(find.byKey(const Key('hyrox-station-name-1')), 180, scrollable: scroll);
    await tester.enterText(find.byKey(const Key('hyrox-station-name-1')), 'SkiErg');
    await tester.scrollUntilVisible(find.byKey(const Key('hyrox-station-duration-1')), 180, scrollable: scroll);
    await tester.enterText(find.byKey(const Key('hyrox-station-duration-1')), '240');
    await tester.scrollUntilVisible(find.byKey(const Key('hyrox-total')), 180, scrollable: scroll);
    await tester.enterText(find.byKey(const Key('hyrox-total')), '640');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Terminer en privé'), 300, scrollable: scroll);
    await tester.ensureVisible(find.text('Terminer en privé'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Terminer en privé'));
    await tester.pumpAndSettle();
    expect(api.submitted!['totalSeconds'], 640);
    expect((api.submitted!['segments'] as List).map((s) => s['type']), ['RUN', 'STATION']);
    expect(api.calls, contains('POST /sessions/hyrox1/complete-expected'));
    expect(api.calls.where((s) => s.endsWith('/posts')), isEmpty);
    expect(find.textContaining('Enregistrée dans votre historique privé'), findsOneWidget);
    await tester.tap(find.text('Garder privée / Retour à l’accueil'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.textContaining('Terminée · 19/10/2026 · privée'), 200,
      scrollable: find.descendant(of: find.byType(ListView).last, matching: find.byType(Scrollable)).first);
    expect(find.textContaining('Terminée · 19/10/2026 · privée'), findsOneWidget);
    api.published = true;
    await tester.tap(find.byTooltip('Actualiser'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Terminée · 19/10/2026 · publiée'), findsOneWidget);
  });
}
