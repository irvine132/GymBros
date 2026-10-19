import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gym_bro/main.dart';

class SocialApi extends Api {
  final calls = <String>[];
  var followed = false;
  @override Future<dynamic> call(String method, String path, [Object? body]) async {
    calls.add('$method $path');
    if (path == '/feed') return <dynamic>[];
    if (path == '/feed/following') return {'items': followed ? [{'id':'p1','authorId':'u2','author':'bravo','title':'Squat matin','sport':'STRENGTH','date':'2026-10-19','exercises':<dynamic>[]}] : <dynamic>[], 'nextCursor': null};
    if (path == '/sessions') return <dynamic>[];
    if (path == '/me/summary') return {'handle':'alice','sessions':0,'publications':0};
    if (path == '/me') return {'id':'u1','handle':'alice','displayName':'Alice','private':false,'unit':'kg'};
    if (path == '/me/follow-requests') return <dynamic>[];
    if (path.startsWith('/users?query=')) return [{'id':'u2','handle':'bravo','displayName':'Bravo','private':true,'relation':followed?'PENDING':'NONE'}];
    if (path == '/users/u2') return {'id':'u2','handle':'bravo','displayName':'Bravo','private':true,'relation':followed?'PENDING':'NONE'};
    if (path == '/users/u2/posts') return {'items':<dynamic>[], 'nextCursor':null};
    if (path == '/users/u2/follow' && method == 'POST') { followed=true; return {'status':'PENDING'}; }
    if (path == '/users/u2/follow' && method == 'DELETE') { followed=false; return {'status':'NONE'}; }
    if (path == '/me/profile' && method == 'PUT') return {'id':'u1','handle':'alice','displayName':'Alice','private':true,'unit':'lb'};
    throw StateError('Unexpected $method $path');
  }
}
void main() {
  testWidgets('search athlete, request follow and see honest empty subscriptions', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final api=SocialApi();
    await tester.pumpWidget(MaterialApp(home: HomeScreen(api:api,userId:'u1',store:await DraftStore.open(),onLogout:() async {})));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abonnements'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Aucune publication'),findsOneWidget);
    await tester.tap(find.text('Rechercher un athlète'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('athlete-query')), 'bravo');
    await tester.tap(find.text('Rechercher'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('@bravo'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Compte privé'), findsWidgets);
    await tester.tap(find.text('Demander à suivre'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Demande envoyée'), findsWidgets);
    expect(api.calls,contains('POST /users/u2/follow'));
  });
}
