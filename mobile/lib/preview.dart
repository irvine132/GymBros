import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart';

// Aperçu local des VRAIS widgets, avec données fictives explicitement signalées.
// Entrypoint séparé : jamais utilisé par l'APK de test ni l'application standard.
class PreviewApi extends Api {
  Map? workout;
  bool published = false;
  @override Future<dynamic> call(String method, String path, [Object? body]) async {
    if (path == '/feed') { return published ? [
      {'id': 'demo-post', 'title': workout?['title'] ?? 'Force du lundi', 'author': 'demo_athlete',
       'sport': 'STRENGTH', 'date': '2026-10-19', 'exerciseCount': (workout?['exercises'] as List?)?.length ?? 1,
       'exercises': workout?['exercises'] ?? [{'name': 'Squat', 'sets': [{'reps': 5, 'weight': 80, 'unit': 'kg'}]}]},
    ] : []; }
    if (path == '/sessions' && method == 'GET') { return workout == null ? [] : [
      {'id': 'demo-session', 'title': workout!['title'], 'status': 'COMPLETED', 'started_at': '2026-10-19'}]; }
    if (path == '/sessions' && method == 'POST') { workout = body as Map; return {'id': 'demo-session', 'status': 'DRAFT'}; }
    if (path == '/sessions/demo-session' && method == 'PUT') { workout = body as Map; return {}; }
    if (path == '/sessions/demo-session/complete' || path == '/sessions/demo-session') {
      return {'id': 'demo-session', 'title': workout?['title'] ?? 'Force du lundi', 'status': 'COMPLETED',
        'workout': workout, 'published': published};
    }
    if (path == '/sessions/demo-session/posts') { published = true; return {'id': 'demo-post'}; }
    if (path == '/posts/demo-post') return (await call('GET', '/feed') as List).first;
    if (path == '/me/summary') return {'handle': 'demo_athlete', 'sessions': workout == null ? 0 : 1, 'publications': published ? 1 : 0};
    if (path == '/exercises') { return [
      {'name': 'Squat', 'category': 'Jambes', 'unit': 'kg'},
      {'name': 'Soulevé de terre', 'category': 'Jambes', 'unit': 'kg'},
      {'name': 'Développé couché', 'category': 'Haut du corps', 'unit': 'kg'},
      {'name': 'Tractions', 'category': 'Dos', 'unit': 'kg'},
    ]; }
    throw StateError('Route absente en aperçu');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = DraftStore(await SharedPreferences.getInstance());
  runApp(MaterialApp(title: 'Gym Bro — aperçu fictif', theme: gymTheme(),
    builder: (context, child) => Banner(message: 'DÉMO', location: BannerLocation.topEnd, child: child!),
    home: HomeScreen(api: PreviewApi(), store: store, userId: 'preview-fixture', onLogout: () async {})));
}
