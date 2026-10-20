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
  testWidgets('V2 activity-first feed shows real metrics and actions at phone size', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = MvpApi(posts: [{
      'id': 'p1', 'author': 'alice', 'authorId': 'u1', 'title': 'Squat & développé',
      'sport': 'STRENGTH', 'date': '2026-10-19', 'likeCount': 3, 'commentCount': 2,
      'exercises': [{'name': 'Squat', 'sets': [{'reps': 5, 'weight': 80, 'unit': 'kg'}]}],
    }]);
    await tester.pumpWidget(MaterialApp(theme: gymTheme(), home: HomeScreen(
      api: api, store: await DraftStore.open(), userId: 'alice', onLogout: () async {})));
    await tester.pumpAndSettle();
    expect(find.text('Bouge. Note. Partage.'), findsNothing);
    expect(find.text('Squat & développé'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Squat & développé')).dy, lessThan(330));
    expect(find.text('1 série'), findsOneWidget);
    expect(find.text('400 kg'), findsOneWidget);
    expect(find.text('3 j’aime'), findsOneWidget);
    expect(find.text('2 commentaires'), findsOneWidget);
    expect(find.text('80 kg · 5 reps'), findsOneWidget);
    expect(find.text('Copier'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('CrossFit and Hyrox metrics are projected without fabricated strength duration', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final api = MvpApi(posts: [
      {'id':'w', 'author':'b', 'title':'WOD', 'sport':'CROSSFIT', 'date':'2026-10-19',
        'format':'AMRAP', 'timeCapSeconds':720, 'result':{'rounds':5,'reps':7,'scaled':false}, 'movements':['Burpees']},
      {'id':'h', 'author':'c', 'title':'Hyrox', 'sport':'HYROX', 'date':'2026-10-19',
        'totalSeconds':2400, 'segments':[{'type':'RUN','distanceMeters':1000,'durationSeconds':400},
          {'type':'STATION','name':'SkiErg','durationSeconds':300,'reps':50}]},
    ]);
    await tester.pumpWidget(MaterialApp(theme: gymTheme(), home: HomeScreen(
      api: api, store: await DraftStore.open(), userId: 'alice', onLogout: () async {})));
    await tester.pumpAndSettle();
    expect(find.text('12 min'), findsOneWidget);
    expect(find.text('5 + 7'), findsOneWidget);
    expect(find.text('40 min'), findsOneWidget);
    expect(find.text('1 km'), findsWidgets);
    expect(find.text('Copier'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('feed remains navigable at 390px with enlarged text and missing metrics', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = MvpApi(posts: [{'id':'p2', 'author':'averylongathletehandle',
      'title':'Une séance sans métriques publiées', 'sport':'STRENGTH', 'date':'2026-10-19'}]);
    await tester.pumpWidget(MaterialApp(theme: gymTheme(),
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(
        textScaler: const TextScaler.linear(1.5)), child: child!),
      home: HomeScreen(api: api, store: await DraftStore.open(), userId: 'alice', onLogout: () async {})));
    await tester.pumpAndSettle();
    expect(find.text('Une séance sans métriques publiées'), findsOneWidget);
    expect(find.text('0 j’aime'), findsNothing);
    expect(find.text('J’aime'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Entraînement'));
    await tester.pumpAndSettle();
    expect(find.text('Mes séances'), findsOneWidget);
    await tester.tap(find.text('Profil'));
    await tester.pumpAndSettle();
    expect(find.text('Mon espace'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
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
