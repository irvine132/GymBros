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
  testWidgets('reactions and comments are confirmed by server, paged, and deletable by author', (tester) async {
    final api = InteractionApi();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: PostInteractionPanel(
      api: api, postId: 'p1', userId: 'u1', initial: const {'likeCount': 0, 'commentCount': 0, 'likedByMe': false},
      onChanged: () {})))));
    await tester.pumpAndSettle();
    expect(find.textContaining('0 j’aime'), findsOneWidget);
    await tester.tap(find.text('J’aime'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 j’aime'), findsOneWidget);
    expect(api.calls, contains('POST /posts/p1/likes'));
    await tester.enterText(find.byKey(const Key('comment-text')), 'Bravo !');
    await tester.tap(find.text('Publier le commentaire'));
    await tester.pumpAndSettle();
    expect(find.text('Bravo !'), findsOneWidget);
    expect(api.calls, contains('POST /posts/p1/comments'));
    await tester.tap(find.text('Supprimer'));
    await tester.pumpAndSettle();
    expect(find.text('Bravo !'), findsNothing);
    expect(api.calls, contains('DELETE /posts/p1/comments/c1'));
  });
  testWidgets('lost comment response keeps text and reuses id on retry; failed like stays unchanged', (tester) async {
    final api = InteractionApi()..failLike = true..failCommentOnce = true;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: PostInteractionPanel(
      api: api, postId: 'p1', userId: 'u1', initial: const {'likeCount': 0, 'commentCount': 0, 'likedByMe': false},
      onChanged: () {})))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('J’aime'));
    await tester.pumpAndSettle();
    expect(find.textContaining('0 j’aime'), findsOneWidget);
    expect(find.textContaining('Réaction non confirmée'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('comment-text')), 'Bravo !');
    await tester.tap(find.text('Publier le commentaire'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Envoi non confirmé'), findsOneWidget);
    expect(api.clientIds.length, 1);
    await tester.tap(find.text('Publier le commentaire'));
    await tester.pumpAndSettle();
    expect(api.clientIds.length, 2);
    expect(api.clientIds.last, api.clientIds.first);
    expect(find.text('Bravo !'), findsOneWidget);
  });
}

class InteractionApi extends Api {
  final calls = <String>[];
  final clientIds = <String>[];
  bool failLike = false, failCommentOnce = false;
  bool liked = false, commented = false;
  @override Future<dynamic> call(String method, String path, [Object? body]) async {
    calls.add('$method $path');
    if (path == '/posts/p1/likes') {
      if (failLike) throw StateError('offline');
      liked = method == 'POST';
      return {'likeCount': liked ? 1 : 0, 'commentCount': commented ? 1 : 0, 'likedByMe': liked};
    }
    if (path == '/posts/p1/comments' && method == 'POST') {
      clientIds.add((body as Map)['clientId'] as String);
      commented = true;
      if (failCommentOnce) { failCommentOnce = false; throw StateError('response lost'); }
      return {'id':'c1','authorId':'u1','author':'alice','text':'Bravo !','date':'2026-10-20'};
    }
    if (path == '/posts/p1/comments' && method == 'GET') {
      return {'items': commented ? [
        {'id':'c1','authorId':'u1','author':'alice','text':'Bravo !','date':'2026-10-20'}
      ] : [], 'nextCursor': null};
    }
    if (path == '/posts/p1/comments/c1' && method == 'DELETE') { commented = false; return {'deleted':true}; }
    if (path == '/posts/p1') {
      return {'likeCount': liked ? 1 : 0, 'commentCount': commented ? 1 : 0, 'likedByMe': liked};
    }
    throw StateError('Unexpected $method $path');
  }
}
