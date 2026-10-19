import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart';

// Aperçu local des VRAIS widgets, avec données fictives explicitement signalées.
// Entrypoint séparé : jamais utilisé par l'APK de test ni l'application standard.
class PreviewApi extends Api {
  Map? workout, template;
  bool published = false, following = false, completed = false;
  @override Future<dynamic> call(String method, String path, [Object? body]) async {
    if (path == '/feed') { return [
      if (published) {'id': 'demo-post', 'title': workout?['title'] ?? 'Force du lundi', 'author': 'demo_athlete',
        'sport': workout?['format'] == null ? 'STRENGTH' : 'CROSSFIT', 'date': '2026-10-19',
        if (workout?['format'] != null) ...{'format':workout!['format'], 'timeCapSeconds':workout!['timeCapSeconds'],
          'movements':workout!['movements'], 'result':workout!['result']},
        if (workout?['format'] == null) 'exerciseCount': (workout?['exercises'] as List?)?.length ?? 1,
        if (template != null) 'sourceAuthor':'bravo_demo',
       if (workout?['format'] == null) 'exercises': workout?['exercises'] ?? [{'name': 'Squat', 'sets': [{'reps': 5, 'weight': 80, 'unit': 'kg'}]}]},
      {'id':'demo-source','authorId':'demo-bravo','author':'bravo_demo','title':'Squat du matin · démo à copier',
       'sport':'STRENGTH','date':'2026-10-19','exerciseCount':1,
       'exercises':[{'name':'Squat','sets':[{'reps':5,'weight':80,'unit':'kg'}]}]},
    ]; }
    if (path == '/sessions' && method == 'GET') { return workout == null ? [] : [
      {'id': 'demo-session', 'title': workout!['title'], 'status': completed ? 'COMPLETED' : 'DRAFT', 'started_at': '2026-10-19'}]; }
    if ((path == '/sessions' || path == '/wods') && method == 'POST') {
      if (!completed) workout = body as Map;
      return {'id': 'demo-session', 'status': completed ? 'COMPLETED' : 'DRAFT'};
    }
    if (path == '/sessions/demo-session' && method == 'PUT') { workout = body as Map; return {}; }
    if (path == '/wods/demo-session' && method == 'PUT') { workout = body as Map; return {}; }
    if (path == '/sessions/demo-session/complete' || path == '/sessions/demo-session') {
      if (path.endsWith('/complete')) completed = true;
      return {'id': 'demo-session', 'title': workout?['title'] ?? 'Force du lundi', 'status': completed ? 'COMPLETED' : 'DRAFT',
        'workout': workout, 'resultSchemaVersion': workout?['format'] == null ? 1 : 2, 'published': published};
    }
    if (path == '/sessions/demo-session/posts') { published = true; return {'id': 'demo-post'}; }
    if (path == '/posts/demo-post') return (await call('GET', '/feed') as List).first;
    if (path == '/posts/demo-source') return (await call('GET', '/feed') as List).last;
    if (path == '/templates') return template == null ? <dynamic>[] : [template];
    if (path == '/posts/demo-source/copy') {
      template ??= {'id':'demo-template','title':'Squat du matin · démo à copier',
        'exercises':[{'name':'Squat','sets':[{'reps':5,'weight':80,'unit':'kg'}]}],
        'sourcePostId':'demo-source','sourceAuthor':'bravo_demo','version':1};
      return template;
    }
    if (path == '/templates/demo-template' && method == 'PUT') {
      template = {'id':'demo-template',...body as Map,'sourcePostId':'demo-source','sourceAuthor':'bravo_demo','version':2};
      return template;
    }
    if (path == '/templates/demo-template/sessions') {
      workout = {'clientId':(body as Map)['clientId'],'title':template!['title'],'exercises':template!['exercises']};
      return {'id':'demo-session','clientId':workout!['clientId'],'title':workout!['title'],
        'status':'DRAFT','workout':workout,'sourcePostId':'demo-source','sourceAuthor':'bravo_demo'};
    }
    if (path == '/me/summary') return {'handle': 'demo_athlete', 'sessions': completed ? 1 : 0, 'publications': published ? 1 : 0};
    if (path == '/me') return {'id':'preview-fixture','handle':'demo_athlete','private':false,'unit':'kg'};
    if (path == '/me/follow-requests') return <dynamic>[];
    if (path == '/feed/following') { return {'items': following ? [
      {'id':'demo-social-post','authorId':'demo-bravo','author':'bravo_demo','title':'Squat du matin · démo',
       'sport':'STRENGTH','date':'2026-10-19','exercises':[{'name':'Squat','sets':[{'reps':5,'weight':80,'unit':'kg'}]}]}
    ] : <dynamic>[], 'nextCursor':null}; }
    if (path.startsWith('/users?query=')) { return [{'id':'demo-bravo','handle':'bravo_demo','displayName':'Bravo (démo)',
      'private':false,'relation':following ? 'ACCEPTED' : 'NONE'}]; }
    if (path == '/users/demo-bravo') { return {'id':'demo-bravo','handle':'bravo_demo','displayName':'Bravo (démo)',
      'private':false,'relation':following ? 'ACCEPTED' : 'NONE'}; }
    if (path == '/users/demo-bravo/posts') return {'items':(await call('GET','/feed/following') as Map)['items'], 'nextCursor':null};
    if (path == '/users/demo-bravo/follow') { following = method == 'POST'; return {'status': following ? 'ACCEPTED' : 'NONE'}; }
    if (path == '/posts/demo-social-post') return ((await call('GET','/feed/following') as Map)['items'] as List).first;
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
