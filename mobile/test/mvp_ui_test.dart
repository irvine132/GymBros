import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gym_bro/main.dart';

class MvpApi extends Api {
  final calls = <String>[];
  final List<Map<String, dynamic>> posts;
  final int completed;
  MvpApi({this.posts = const [], this.completed = 0});
  @override Future<dynamic> call(String method, String path, [Object? body]) async {
    calls.add('$method $path');
    if (path == '/feed') return posts;
    if (path == '/sessions') return [];
    if (path == '/me/summary') return {'handle': 'alice', 'sessions': completed, 'publications': 0};
    if (path == '/me') return {'id':'alice','handle':'alice','private':false,'unit':'kg'};
    if (path == '/me/follow-requests') return <dynamic>[];
    if (path == '/feed/following') return {'items':<dynamic>[], 'nextCursor':null};
    if (path == '/exercises') return [{'name': 'Squat', 'category': 'Jambes', 'unit': 'kg'}, {'name': 'Tractions', 'category': 'Dos', 'unit': 'kg'}];
    throw StateError('Unexpected $method $path');
  }
}

void main() {
  testWidgets('empty home leads to catalogue and profile uses real summary', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final api = MvpApi();
    await tester.pumpWidget(MaterialApp(home: HomeScreen(api: api, store: await DraftStore.open(), userId: 'alice', onLogout: () async {})));
    await tester.pumpAndSettle();
    expect(find.text('Commencer une séance'), findsOneWidget);
    await tester.tap(find.text('Commencer une séance'));
    await tester.pumpAndSettle();
    expect(find.text('Squat'), findsWidgets);
    expect(find.text('Tractions'), findsWidgets);
    expect(api.calls, contains('GET /exercises'));
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profil'));
    await tester.pumpAndSettle();
    expect(find.text('@alice'), findsOneWidget);
    expect(find.text('0 séances terminées'), findsOneWidget);
  });
  testWidgets('singular session and legacy technical feed entry are clearly labelled', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final api = MvpApi(completed: 1, posts: [{
      'id': 'fixture-id', 'title': 'Public smoke a1b2c3d4', 'author': 'alicea1b2c3d4',
      'sport': 'STRENGTH', 'date': '2026-10-19', 'exerciseCount': 1,
      'exercises': [{'name': 'Squat', 'sets': [{'reps': 5, 'weight': 80, 'unit': 'kg'}]}],
    }]);
    await tester.pumpWidget(MaterialApp(home: HomeScreen(api: api, store: await DraftStore.open(), userId: 'alice', onLogout: () async {})));
    await tester.pumpAndSettle();
    expect(find.textContaining('Séance de test technique'), findsOneWidget);
    await tester.tap(find.text('Profil'));
    await tester.pumpAndSettle();
    expect(find.text('1 séance terminée'), findsOneWidget);
  });
}
