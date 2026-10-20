import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'main.dart';

/// One durable, owner-scoped, private completion per discipline. Never queues a post.
class OfflineOutbox {
  final SharedPreferences prefs;
  final Api api;
  final String owner;
  // Bind at construction, not at retry time: this owner must never borrow a
  // bearer from another login on the shared API instance.
  final int _sessionVersion;
  OfflineOutbox(this.prefs, this.api, this.owner) : _sessionVersion = api.sessionVersion;
  bool get sessionActive => api.sessionVersion == _sessionVersion;

  String _key(String kind) => 'outbox:v1:$owner:$kind';
  static const kinds = ['strength', 'wod', 'hyrox'];
  static const _paths = {'strength': '/sessions', 'wod': '/wods', 'hyrox': '/hyrox'};

  Map<String, dynamic>? read(String kind) {
    if (!kinds.contains(kind)) throw ArgumentError.value(kind, 'kind');
    final text = prefs.getString(_key(kind));
    if (text == null) return null;
    final item = jsonDecode(text) as Map<String, dynamic>;
    if (item['version'] != 1) throw StateError('Outbox version unsupported');
    return item;
  }

  Future<void> _write(String kind, Map<String, dynamic> item) async {
    if (!await prefs.setString(_key(kind), jsonEncode(item))) {
      throw StateError('Outbox not saved');
    }
  }

  Future<void> enqueue(String kind, Map<String, dynamic> body) async {
    if (!kinds.contains(kind) || body['clientId'] is! String) throw ArgumentError('Invalid completion');
    final existing = read(kind);
    if (existing != null && existing['state'] != 'synced' &&
        existing['body']['clientId'] != body['clientId']) {
      throw StateError('Another completion is pending');
    }
    // A delivered completion must not be replaced by an edited snapshot.
    if (existing != null && existing['body']['clientId'] == body['clientId']) {
      if (jsonEncode(_normalized(existing['body'])) != jsonEncode(_normalized(body))) {
        throw StateError('Completion already queued with different content');
      }
      return;
    }
    await _write(kind, {'version': 1, 'state': 'queued', 'body': body});
  }
  /// Explicit fork on conflict: the original remote draft is never overwritten.
  Future<void> forkConflict(String kind, String newClientId) async {
    final item = read(kind);
    if (item == null || item['error'] != 'conflict' || newClientId.isEmpty) throw StateError('No conflict to resolve');
    final body = Map<String,dynamic>.from(item['body'] as Map);
    if (body['clientId'] == newClientId) throw ArgumentError('New id required');
    final previous = body['clientId'];
    body['clientId'] = newClientId;
    await _write(kind, {'version': 1, 'state': 'queued', 'body': body, 'priorClientId': previous});
  }
  Future<void> reopenRejected(String kind) async {
    if (read(kind)?['error'] != 'validation') throw StateError('No rejected completion');
    if (!await prefs.remove(_key(kind))) throw StateError('Cannot reopen local draft');
  }

  // Jackson includes null fields in stored JSON, while the client omits them.
  // Compare values rather than map insertion order or numeric representation.
  dynamic _normalized(dynamic value) {
    if (value is Map) { return {for (final key in value.keys.map((k) => '$k').toList()..sort())
      if (value[key] != null) key: _normalized(value[key])}; }
    if (value is List) return value.map(_normalized).toList();
    if (value is num) return value.toDouble();
    return value;
  }

  Future<Map<String, dynamic>?> sync(String kind) async {
    var item = read(kind);
    if (item == null || item['state'] == 'synced') return item;
    if (!sessionActive) return item;
    final body = Map<String, dynamic>.from(item['body'] as Map);
    item = {...item, 'state': 'syncing', 'error': null};
    await _write(kind, item);
    try {
      if (!sessionActive) throw ApiUnauthorized();
      final remote = await api.call('POST', _paths[kind]!, body) as Map;
      if (!sessionActive) throw ApiUnauthorized();
      if (remote['clientId'] != body['clientId'] ||
          jsonEncode(_normalized(remote['workout'])) != jsonEncode(_normalized(body))) {
        throw const _SyncConflict();
      }
      if (remote['status'] != 'DRAFT' && remote['status'] != 'COMPLETED') {
        throw const _SyncConflict();
      }
      if (!sessionActive) throw ApiUnauthorized();
      final done = await api.call('POST', '/sessions/${remote['id']}/complete-expected', body) as Map;
      if (!sessionActive) throw ApiUnauthorized();
      if (done['status'] != 'COMPLETED') throw const _SyncConflict();
      item = {...item, 'state': 'synced', 'session': done};
      await _write(kind, item);
      return item;
    } catch (e) {
      item = {...item!, 'state': 'error', 'error': e is _SyncConflict ? 'conflict' :
        e is ApiUnauthorized ? 'auth' : e is ApiHttpFailure && e.status == 409 ? 'conflict' :
        e is ApiHttpFailure && (e.status == 400 || e.status == 422) ? 'validation' :
        e is ApiHttpFailure ? 'server' : 'network'};
      await _write(kind, item);
      return item;
    }
  }

  Future<void> syncAll() async {
    for (final kind in kinds) {
      if (!sessionActive) break;
      final item = read(kind);
      if (item != null && item['state'] != 'synced' && item['error'] == null) {
        await sync(kind);
        if (read(kind)?['error'] == 'auth') break;
      }
    }
  }
}

class _SyncConflict implements Exception {
  const _SyncConflict();
}
