import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gym_bro/main.dart';

class WodApi extends Api {
  final calls = <String>[];
  Map? submitted;
  @override Future<dynamic> call(String method, String path, [Object? body]) async {
    calls.add('$method $path');
    if (path == '/feed' || path == '/sessions' || path == '/templates' || path == '/me/follow-requests') return <dynamic>[];
    if (path == '/feed/following') return {'items': [], 'nextCursor': null};
    if (path == '/me/summary') return {'handle': 'athlete', 'sessions': 0, 'publications': 0};
    if (path == '/me') return {'id': 'athlete', 'handle': 'athlete', 'private': false, 'unit': 'kg'};
    if (path == '/wods' && method == 'POST') {
      submitted = body as Map;
      return {'id': 'wod1', 'clientId': submitted!['clientId'], 'title': submitted!['title'], 'resultSchemaVersion': 2,
        'status': 'DRAFT', 'workout': submitted, 'published': false};
    }
    if (path == '/wods/wod1' && method == 'PUT') { return {'id': 'wod1', 'status': 'DRAFT'}; }
    if (path == '/sessions/wod1/complete') {
      return {'id': 'wod1', 'title': submitted!['title'], 'status': 'COMPLETED',
        'resultSchemaVersion': 2, 'workout': submitted, 'published': false};
    }
    throw StateError('Unexpected $method $path');
  }
}
void main() {
  testWidgets('WOD draft resumes and finishes privately with typed result', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final api = WodApi();
    final store = await DraftStore.open();
    await tester.pumpWidget(MaterialApp(home: HomeScreen(api: api, store: store, userId: 'athlete', onLogout: () async {})));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entraînement'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Créer un WOD CrossFit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('wod-title')), 'WOD du jour');
    await tester.enterText(find.byKey(const Key('wod-movements')), 'Burpees\nTractions');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reprendre mon WOD'));
    await tester.pumpAndSettle();
    expect(find.text('WOD du jour'), findsOneWidget);
    expect(find.text('Burpees\nTractions'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('wod-rounds')), '5');
    await tester.enterText(find.byKey(const Key('wod-reps')), '7');
    final scroll = find.descendant(of: find.byType(ListView).last, matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.text('Terminer en privé'), 280, scrollable: scroll);
    await tester.tap(find.text('Terminer en privé'));
    await tester.pumpAndSettle();
    expect(api.submitted!['format'], 'AMRAP');
    expect(api.submitted!['result'], {'rounds': 5, 'reps': 7, 'scaled': false});
    expect(api.calls, contains('POST /sessions/wod1/complete'));
    expect(find.textContaining('Enregistrée dans votre historique privé'), findsOneWidget);
  });
}
