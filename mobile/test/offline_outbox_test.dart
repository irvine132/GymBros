import 'package:flutter_test/flutter_test.dart';
import 'package:gym_bro/main.dart';
import 'package:gym_bro/offline_outbox.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OutboxApi extends Api {
  bool online = false;
  bool unauthorized = false;
  bool loseResponse = false;
  bool loseCompleteResponse = false;
  bool rejectValidation = false;
  Map<String, dynamic>? remote;
  int created = 0;
  int completed = 0;
  @override
  Future<dynamic> call(String method, String path, [Object? body]) async {
    if (unauthorized) throw ApiUnauthorized();
    if (!online) throw StateError('offline');
    if (rejectValidation) throw const ApiHttpFailure(400);
    if (method == 'POST' && ['/sessions', '/wods', '/hyrox'].contains(path)) {
      if (remote == null) {
        created++;
        remote = {'id': 'one', 'clientId': (body as Map)['clientId'], 'status': 'DRAFT',
          'resultSchemaVersion': 1, 'workout': body};
      }
      if (loseResponse) { loseResponse = false; throw StateError('response lost'); }
      return remote;
    }
    if (method == 'POST' && path == '/sessions/one/complete-expected') {
      completed++;
      remote!['status'] = 'COMPLETED';
      if (loseCompleteResponse) { loseCompleteResponse = false; throw StateError('completion response lost'); }
      return remote;
    }
    throw StateError('Unexpected $method $path');
  }
}

void main() {
  final body = <String, dynamic>{'clientId': 'stable-id', 'title': 'Test',
    'exercises': [{'name': 'Squat', 'sets': [{'reps': 5, 'weight': 60, 'unit': 'kg'}]}]};
  test('old unversioned drafts remain readable; new drafts are owner-scoped and versioned', () async {
    SharedPreferences.setMockInitialValues({'draft:a': '{"clientId":"legacy","title":"Old"}',
      'wod:a': '{"clientId":"legacy-wod"}', 'hyrox:a': '{"clientId":"legacy-hyrox"}'});
    final prefs = await SharedPreferences.getInstance();
    final store = DraftStore(prefs);
    expect(store.read('a')?['clientId'], 'legacy');
    expect(store.readWod('a')?['clientId'], 'legacy-wod');
    expect(store.readHyrox('a')?['clientId'], 'legacy-hyrox');
    await store.save('a', body);
    expect(prefs.getString('draft:a'), contains('"snapshotVersion":1'));
    expect(DraftStore(prefs).read('a'), body);
    expect(DraftStore(prefs).read('b'), isNull);
  });

  test('offline finish persists owner-scoped queued item through reopen; retry after lost response is unique', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final api = OutboxApi();
    final outbox = OfflineOutbox(prefs, api, 'a');
    await outbox.enqueue('strength', body);
    expect(outbox.read('strength')?['state'], 'queued');
    expect(OfflineOutbox(prefs, api, 'b').read('strength'), isNull);
    expect(OfflineOutbox(prefs, api, 'a').read('strength')?['body'], body);
    await outbox.sync('strength');
    expect(outbox.read('strength')?['state'], 'error');
    api.online = true;
    api.loseResponse = true;
    await outbox.sync('strength');
    expect(outbox.read('strength')?['state'], 'error');
    await OfflineOutbox(prefs, api, 'a').sync('strength');
    expect(outbox.read('strength')?['state'], 'synced');
    expect(api.created, 1);
    expect(api.completed, 1);
  });

  test('401 and remote concurrent edit retain local payload; no PUT or completion', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final api = OutboxApi()..unauthorized = true;
    final outbox = OfflineOutbox(prefs, api, 'a');
    await outbox.enqueue('strength', body);
    await outbox.sync('strength');
    expect(outbox.read('strength')?['state'], 'error');
    expect(outbox.read('strength')?['body'], body);
    api.unauthorized = false;
    api.online = true;
    api.remote = {'id': 'one', 'clientId': 'stable-id', 'status': 'DRAFT',
      'resultSchemaVersion': 1, 'workout': {...body, 'title': 'changed on another device'}};
    await outbox.sync('strength');
    expect(outbox.read('strength')?['state'], 'error');
    expect(outbox.read('strength')?['error'], 'conflict');
    expect(api.completed, 0);
  });
  test('all three disciplines remain private after offline finish and sync once after reopen', () async {
    for (final kind in OfflineOutbox.kinds) {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final api = OutboxApi();
      final payload = {...body, 'clientId': '$kind-stable'};
      await OfflineOutbox(prefs, api, 'athlete').enqueue(kind, payload);
      final reopened = OfflineOutbox(prefs, api, 'athlete');
      expect(reopened.read(kind)?['body'], payload);
      api.online = true;
      await reopened.syncAll();
      await reopened.syncAll();
      expect(reopened.read(kind)?['state'], 'synced');
      expect(api.created, 1);
      expect(api.completed, 1);
    }
  });
  test('same clientId changed content cannot replace queued snapshot', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final outbox = OfflineOutbox(prefs, OutboxApi(), 'athlete');
    await outbox.enqueue('strength', body);
    await expectLater(outbox.enqueue('strength', {...body, 'title': 'edited'}), throwsStateError);
    expect(outbox.read('strength')?['body'], body);
  });
  test('remote conflict requires explicit fork with new clientId and leaves original untouched', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final api = OutboxApi()..online = true;
    final outbox = OfflineOutbox(prefs, api, 'a');
    await outbox.enqueue('strength', body);
    api.remote = {'id': 'one', 'clientId': body['clientId'], 'status': 'DRAFT',
      'workout': {...body, 'title': 'edited elsewhere'}};
    await outbox.sync('strength');
    expect(outbox.read('strength')?['error'], 'conflict');
    await expectLater(outbox.forkConflict('strength', body['clientId'] as String), throwsArgumentError);
    await outbox.forkConflict('strength', 'new-id');
    expect(outbox.read('strength')?['body']['clientId'], 'new-id');
    expect(outbox.read('strength')?['priorClientId'], body['clientId']);
    expect(api.remote?['workout']['title'], 'edited elsewhere');
  });
  test('400 retains local payload until explicit correction', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final api = OutboxApi()..online = true..rejectValidation = true;
    final outbox = OfflineOutbox(prefs, api, 'a');
    await outbox.enqueue('strength', body);
    await outbox.sync('strength');
    expect(outbox.read('strength')?['error'], 'validation');
    expect(outbox.read('strength')?['body'], body);
    await outbox.reopenRejected('strength');
    expect(outbox.read('strength'), isNull);
  });
  test('lost completion acknowledgement retries stable id without local publication', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final api = OutboxApi()..online = true..loseCompleteResponse = true;
    final outbox = OfflineOutbox(prefs, api, 'a');
    await outbox.enqueue('strength', body);
    await outbox.sync('strength');
    expect(outbox.read('strength')?['state'], 'error');
    expect(api.remote?['status'], 'COMPLETED');
    await OfflineOutbox(prefs, api, 'a').sync('strength');
    expect(outbox.read('strength')?['state'], 'synced');
    expect(api.created, 1);
    expect(api.completed, 2);
  });
}
