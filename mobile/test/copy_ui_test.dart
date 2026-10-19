import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gym_bro/main.dart';

class CopyApi extends Api {
  final calls = <String>[];
  Map<String,dynamic>? edited;
  @override Future<dynamic> call(String method, String path, [Object? body]) async {
    calls.add('$method $path');
    if (path == '/feed') return [{'id':'p1','authorId':'u2','author':'source','title':'Squat original','sport':'STRENGTH','date':'2026-10-19','exercises':[{'name':'Squat','sets':[{'reps':5,'weight':60,'unit':'kg'}]}]}];
    if (path == '/feed/following') return {'items':<dynamic>[], 'nextCursor':null};
    if (path == '/sessions' || path == '/templates' || path == '/me/follow-requests') return <dynamic>[];
    if (path == '/me/summary') return {'handle':'copier','sessions':0,'publications':0};
    if (path == '/me') return {'id':'u1','handle':'copier','private':false,'unit':'kg'};
    if (path == '/posts/p1') return {'id':'p1','authorId':'u2','author':'source','title':'Squat original','sport':'STRENGTH','date':'2026-10-19','exercises':[{'name':'Squat','sets':[{'reps':5,'weight':60,'unit':'kg'}]}]};
    if (path == '/posts/p1/copy') return {'id':'t1','title':'Squat original','exercises':[{'name':'Squat','sets':[{'reps':5,'weight':60,'unit':'kg'}]}], 'sourcePostId':'p1','sourceAuthor':'source','version':1};
    if (path == '/templates/t1' && method == 'PUT') { edited=Map<String,dynamic>.from(body as Map); return {'id':'t1',...edited!,'version':2,'sourceAuthor':'source'}; }
    if (path == '/templates/t1/sessions') return {'id':'s1','clientId':(body as Map)['clientId'],'title':'Squat original','status':'DRAFT','workout':{'exercises':edited!['exercises']}};
    if (path == '/exercises') return <dynamic>[];
    throw StateError('Unexpected $method $path');
  }
}
void main() {
  testWidgets('copy a visible post, adapt and start a private draft', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final api=CopyApi();
    await tester.pumpWidget(MaterialApp(home: HomeScreen(api:api,userId:'u1',store:await DraftStore.open(),onLogout:() async {})));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Voir la séance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Voir la séance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copier et essayer'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Inspiré de @source'),findsWidgets);
    await tester.enterText(find.byKey(const Key('template-reps-0-0')), '8');
    final scroll = find.descendant(of: find.byType(ListView).last, matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.text('Enregistrer le modèle'), 300, scrollable: scroll);
    await tester.tap(find.text('Enregistrer le modèle'));
    await tester.pumpAndSettle();
    expect(api.edited!['exercises'][0]['sets'][0]['reps'],8);
    await tester.scrollUntilVisible(find.text('Démarrer ma séance'), 180, scrollable: scroll);
    await tester.tap(find.text('Démarrer ma séance'));
    await tester.pumpAndSettle();
    expect(api.calls,contains('POST /templates/t1/sessions'));
    expect(find.text('Séance musculation'),findsOneWidget);
  });
}
