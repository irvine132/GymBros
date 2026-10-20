import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'native_diagnostic_io.dart'
    if (dart.library.js_interop) 'native_diagnostic_web.dart' as native;
import 'template_screen.dart';
import 'wod_screen.dart';
import 'hyrox_screen.dart';
import 'offline_outbox.dart';

const apiBase = String.fromEnvironment('API_BASE', defaultValue: 'http://127.0.0.1:18081/api/v1');
const diagnosticBuild = String.fromEnvironment('DIAGNOSTIC_BUILD', defaultValue: 'unknown');
void main() => runApp(const GymApp());

const ink = Color(0xff192326), canvas = Color(0xfff4f5ef), lime = Color(0xffc7ee60);
ThemeData gymTheme() => ThemeData(
  useMaterial3: true,
  scaffoldBackgroundColor: canvas,
  colorScheme: ColorScheme.fromSeed(seedColor: lime, brightness: Brightness.light,
    primary: ink, onPrimary: Colors.white, surface: Colors.white),
  appBarTheme: const AppBarTheme(backgroundColor: canvas, foregroundColor: ink, centerTitle: false),
  textTheme: const TextTheme(headlineLarge: TextStyle(fontSize: 34, height: 1.05, fontWeight: FontWeight.w800, color: ink),
    titleLarge: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: ink),
    bodyMedium: TextStyle(fontSize: 15, height: 1.4, color: ink)),
  inputDecorationTheme: InputDecorationTheme(border: OutlineInputBorder(borderRadius: BorderRadius.circular(14))),
  filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size(48, 52))),
  outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(minimumSize: const Size(48, 52))),
);

String sportLabel(Object? sport) => sport == 'STRENGTH' ? 'Musculation' : sport == 'CROSSFIT' ? 'CrossFit' : sport == 'HYROX' ? 'Hyrox' : 'Séance';
bool isTechnicalPost(Map post) {
  final title = '${post['title']}', author = '${post['author']}';
  return (RegExp(r'^Public smoke [0-9a-f]{8}$').hasMatch(title) &&
      RegExp(r'^(alice|bob)[0-9a-f]{8}$').hasMatch(author)) ||
      (RegExp(r'^Demo squat [0-9a-f]{8}$').hasMatch(title) &&
      RegExp(r'^alice[0-9a-f]{8}$').hasMatch(author));
}
String dateLabel(Object? value) {
  final date = DateTime.tryParse('$value');
  if (date == null) return 'Date indisponible';
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}
String exerciseSummary(Map post) {
  if (post['sport'] == 'HYROX') {
    final segments = post['segments'] as List? ?? [];
    final labels = segments.map((entry) {
      final segment = entry as Map;
      return segment['type'] == 'RUN' ? 'Course ${segment['distanceMeters']} m · ${segment['durationSeconds']} s'
        : '${segment['name']} · ${segment['durationSeconds']} s${segment['reps'] == null ? '' : ' · ${segment['reps']} reps'}${segment['weight'] == null ? '' : ' · ${segment['weight']} ${segment['unit']}'}';
    }).join('  •  ');
    return 'Temps total ${post['totalSeconds']} s · $labels';
  }
  if (post['sport'] == 'CROSSFIT') {
    final result = post['result'] as Map? ?? {};
    final score = post['format'] == 'FOR_TIME' ? '${result['timeSeconds']} s'
      : '${result['rounds']} tours + ${result['reps']} reps';
    return '${post['format']} · cap ${post['timeCapSeconds']} s · $score · ${result['scaled'] == true ? 'Scaled' : 'RX'} · ${(post['movements'] as List? ?? []).join(', ')}';
  }
  final exercises = post['exercises'];
  if (exercises is! List || exercises.isEmpty) return '${post['exerciseCount'] ?? 0} exercice(s)';
  return exercises.map((item) {
    final exercise = item as Map;
    final sets = exercise['sets'] as List? ?? [];
    return '${exercise['name']} · ${sets.length} série${sets.length > 1 ? 's' : ''}';
  }).join('  •  ');
}

Widget gymCard({required Widget child, EdgeInsets? padding}) => Card(
  elevation: 0, color: Colors.white, clipBehavior: Clip.antiAlias,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
  child: Padding(padding: padding ?? const EdgeInsets.all(20), child: child),
);

// Exact class names only: never expose class names supplied by third-party code.
const _javaErrorClasses = <String, String>{
  'java.lang.RuntimeException': 'RuntimeException',
  'java.lang.IllegalArgumentException': 'IllegalArgumentException',
  'java.lang.IllegalStateException': 'IllegalStateException',
  'java.lang.NullPointerException': 'NullPointerException',
  'java.lang.ClassCastException': 'ClassCastException',
  'java.lang.NumberFormatException': 'NumberFormatException',
  'java.lang.SecurityException': 'SecurityException',
  'java.lang.UnsatisfiedLinkError': 'UnsatisfiedLinkError',
  'java.lang.NoSuchMethodError': 'NoSuchMethodError',
  'java.lang.ExceptionInInitializerError': 'ExceptionInInitializerError',
  'java.io.IOException': 'IOException',
  'java.io.InvalidClassException': 'InvalidClassException',
  'java.io.StreamCorruptedException': 'StreamCorruptedException',
  'java.io.EOFException': 'EOFException',
};

String classifyJavaCauseChain(Iterable<String> names) =>
    names.take(3).map((name) => _javaErrorClasses[name] ?? 'Unknown').join('>');

// Never include exception messages, stack traces, preference values, or API bodies.
String startupDiagnostic(String phase, Object error) {
  final kind = switch (error) {
    TimeoutException() => 'TimeoutException',
    MissingPluginException() => 'MissingPluginException',
    PlatformException() => 'PlatformException',
    StateError() => 'StateError',
    FormatException() => 'FormatException',
    _ => 'Other',
  };
  final operation = switch (phase) {
    'prefs.open' => 'OPEN',
    'prefs.read.token' || 'prefs.read.userId' => 'READ',
    'prefs.remove.token' || 'prefs.remove.userId' => 'REMOVE',
    'api.me' => 'NETWORK',
    _ => 'OTHER',
  };
  final safePhase = operation == 'OTHER' ? 'unknown' : phase;
  final nativeCode = error is PlatformException
      ? ' · native:${native.nativeDiagnostic(error, classifyJavaCauseChain)}' : '';
  return 'Gym Bro $diagnosticBuild · $safePhase · $kind · D-$operation-${error is TimeoutException ? 'TIMEOUT' : 'ERROR'}$nativeCode';
}

class ApiUnauthorized implements Exception {
  @override String toString() => 'Session expirée. Reconnectez-vous.';
}

class ApiHttpFailure implements Exception {
  final int status;
  const ApiHttpFailure(this.status);
  @override String toString() => 'Opération refusée. Réessayez.';
}

class DraftStore {
  final SharedPreferences prefs;
  DraftStore(this.prefs);
  static Future<DraftStore> open() async => DraftStore(await SharedPreferences.getInstance());
  Map<String, dynamic>? _readDraft(String key) {
    final value = prefs.getString(key);
    if (value == null) return null;
    final decoded = jsonDecode(value) as Map<String,dynamic>;
    if (!decoded.containsKey('snapshotVersion')) return decoded; // Existing drafts.
    if (decoded['snapshotVersion'] != 1 || decoded['data'] is! Map) throw StateError('Unsupported draft version');
    return Map<String,dynamic>.from(decoded['data'] as Map);
  }
  Future<void> _saveDraft(String key, Map<String,dynamic> data) async {
    if (!await prefs.setString(key, jsonEncode({'snapshotVersion': 1, 'data': data}))) throw StateError('Draft not saved');
  }
  Map<String, dynamic>? read(String user) {
    return _readDraft('draft:$user');
  }
  Future<void> save(String user, Map<String, dynamic> data) async {
    await _saveDraft('draft:$user', data);
  }
  Future<void> clear(String user) async {
    if (!await prefs.remove('draft:$user')) throw StateError('Draft not cleared');
  }
  Map<String, dynamic>? readWod(String user) {
    return _readDraft('wod:$user');
  }
  Future<void> saveWod(String user, Map<String,dynamic> data) async {
    await _saveDraft('wod:$user', data);
  }
  Future<void> clearWod(String user) async {
    if (!await prefs.remove('wod:$user')) throw StateError('WOD draft not cleared');
  }
  Map<String, dynamic>? readHyrox(String user) {
    return _readDraft('hyrox:$user');
  }
  Future<void> saveHyrox(String user, Map<String,dynamic> data) async {
    await _saveDraft('hyrox:$user', data);
  }
  Future<void> clearHyrox(String user) async {
    if (!await prefs.remove('hyrox:$user')) throw StateError('Hyrox draft not cleared');
  }
}

class Api {
  final http.Client Function() clientFactory;
  final Duration timeout;
  Api({http.Client Function()? clientFactory, this.timeout = const Duration(seconds: 12)})
      : clientFactory = clientFactory ?? http.Client.new;
  String? token;
  Future<dynamic> call(String method, String path, [Object? body]) async {
    final uri = Uri.parse('$apiBase$path');
    final headers = <String, String>{'Content-Type': 'application/json', if (token != null) 'Authorization': 'Bearer $token'};
    final request = http.Request(method, uri)..headers.addAll(headers);
    if (body != null) request.body = jsonEncode(body);
    final client = clientFactory();
    late http.Response response;
    try {
      response = await http.Response.fromStream(await client.send(request).timeout(timeout)).timeout(timeout);
    } on TimeoutException {
      throw StateError('Réseau indisponible ou délai dépassé. Vérifiez votre connexion puis Réessayer.');
    } on SocketException {
      throw StateError('Réseau indisponible. Vérifiez votre connexion puis Réessayer.');
    } on http.ClientException {
      throw StateError('Réseau indisponible. Vérifiez votre connexion puis Réessayer.');
    } finally {
      client.close();
    }
    if (response.statusCode == 401) throw ApiUnauthorized();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiHttpFailure(response.statusCode);
    }
    return response.body.isEmpty ? null : jsonDecode(response.body);
  }
}

class GymApp extends StatefulWidget {
  final Future<SharedPreferences> Function() openPreferences;
  final String? Function(SharedPreferences, String) readPreference;
  final Future<bool> Function(SharedPreferences, String) removePreference;
  final Api? api;
  const GymApp({super.key, this.openPreferences = SharedPreferences.getInstance,
    this.readPreference = _readPreference, this.removePreference = _removePreference, this.api});
  static String? _readPreference(SharedPreferences prefs, String key) => prefs.getString(key);
  static Future<bool> _removePreference(SharedPreferences prefs, String key) => prefs.remove(key);
  @override State<GymApp> createState() => _GymAppState();
}
class _GymAppState extends State<GymApp> {
  late final Api api = widget.api ?? Api();
  DraftStore? store;
  String? userId;
  bool loading = true;
  String? restoreError;
  String? restoreDiagnostic;
  int restoreAttempt = 0;
  @override void initState() { super.initState(); _restore(); }
  Future<void> _restore() async {
    final attempt = ++restoreAttempt;
    var phase = 'prefs.open';
    try {
      // The plugin can fail or never reply on a device; do not strand startup.
      final prefs = await widget.openPreferences().timeout(const Duration(seconds: 8));
      if (!mounted || attempt != restoreAttempt) return;
      store = DraftStore(prefs);
      phase = 'prefs.read.token';
      api.token = widget.readPreference(prefs, 'token');
      phase = 'prefs.read.userId';
      final id = widget.readPreference(prefs, 'userId');
      if (api.token != null && id != null) {
        phase = 'api.me';
        try {
          await api.call('GET', '/me').timeout(const Duration(seconds: 25));
          if (!mounted || attempt != restoreAttempt) return;
          userId = id;
        } on ApiUnauthorized {
          if (!mounted || attempt != restoreAttempt) return;
          api.token = null;
          phase = 'prefs.remove.token';
          await widget.removePreference(prefs, 'token').timeout(const Duration(seconds: 8));
          phase = 'prefs.remove.userId';
          await widget.removePreference(prefs, 'userId').timeout(const Duration(seconds: 8));
        } catch (error) {
          // Only the network failure belongs here. Storage errors retain their phase.
          if (phase != 'api.me') rethrow;
          if (attempt == restoreAttempt) {
            restoreError = 'Réseau indisponible. Vérifiez votre connexion puis Réessayer.';
            restoreDiagnostic = startupDiagnostic(phase, error);
          }
        }
      }
    } catch (error) {
      // A transient storage failure must never clear credentials or drafts.
      if (attempt == restoreAttempt) {
        restoreError = 'Stockage local indisponible. Vos données sont conservées. Réessayer.';
        restoreDiagnostic = startupDiagnostic(phase, error);
      }
    } finally {
      if (mounted && attempt == restoreAttempt) setState(() => loading = false);
    }
  }
  Future<void> signedIn(Map<String, dynamic> auth) async {
    final prefs = store!.prefs;
    api.token = auth['token'] as String;
    userId = auth['userId'] as String;
    await prefs.setString('token', api.token!);
    await prefs.setString('userId', userId!);
    setState(() {});
  }
  Future<void> logout() async {
    try { await api.call('POST', '/auth/logout'); } finally {
      api.token = null; userId = null;
      await store!.prefs.remove('token'); await store!.prefs.remove('userId');
      if (mounted) setState(() {});
    }
  }
  @override Widget build(BuildContext context) => MaterialApp(
    title: 'Gym Bro', theme: gymTheme(),
    home: loading ? const Scaffold(body: Center(child: CircularProgressIndicator()))
      : restoreError != null ? Scaffold(body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(restoreError!), SelectableText(restoreDiagnostic!),
          TextButton(onPressed: () => Clipboard.setData(ClipboardData(text: restoreDiagnostic!)), child: const Text('Copier le diagnostic')),
          TextButton(onPressed: () { setState(() { loading = true; restoreError = null; restoreDiagnostic = null; }); _restore(); }, child: const Text('Réessayer')),
        ])))
      : userId == null ? AuthScreen(api: api, onSuccess: signedIn)
      : HomeScreen(api: api, userId: userId!, store: store!, onLogout: logout),
  );
}

class AuthScreen extends StatefulWidget {
  final Api api;
  final Future<void> Function(Map<String, dynamic>) onSuccess;
  const AuthScreen({super.key, required this.api, required this.onSuccess});
  @override State<AuthScreen> createState() => _AuthScreenState();
}
class _AuthScreenState extends State<AuthScreen> {
  final handle = TextEditingController(), email = TextEditingController(), password = TextEditingController();
  bool register = false, busy = false;
  String? error;
  String? handleError, emailError, passwordError;
  bool validated = false;

  void validateFields() {
    final name = handle.text.trim(), address = email.text.trim();
    handleError = register ? (name.isEmpty ? 'Pseudo requis.'
        : RegExp(r'^[a-z0-9_]{3,32}$').hasMatch(name) ? null
        : 'Pseudo : 3 à 32 lettres minuscules, chiffres ou _.') : null;
    emailError = address.isEmpty ? 'Email requis.'
        : address.length > 254 || !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(address)
            ? 'Saisissez une adresse email valide.' : null;
    passwordError = password.text.isEmpty ? 'Mot de passe requis.'
        : (register && password.text.length < 12) || password.text.length > 128
            ? 'Mot de passe : 12 à 128 caractères.' : null;
  }

  String authError(Object failure) {
    if (failure is ApiUnauthorized) return 'Identifiants incorrects.';
    if (failure is ApiHttpFailure) {
      if (register && failure.status == 409) {
        return 'Inscription impossible avec ces informations. Essayez un autre pseudo ou email.';
      }
      if (register && failure.status == 400) return 'Inscription refusée. Vérifiez les champs et réessayez.';
      return 'Opération indisponible. Vérifiez les champs puis réessayez.';
    }
    return 'Réseau ou service indisponible. Vérifiez votre connexion puis réessayez.';
  }

  Future<void> submit() async {
    if (busy) return;
    setState(() { validated = true; error = null; validateFields(); });
    if (handleError != null || emailError != null || passwordError != null) return;
    setState(() { busy = true; error = null; });
    try {
      final data = await widget.api.call('POST', register ? '/auth/register' : '/auth/login', {
        if (register) 'handle': handle.text.trim(), 'email': email.text.trim(), 'password': password.text,
      });
      await widget.onSuccess(Map<String, dynamic>.from(data as Map));
    } catch (e) { if (mounted) setState(() => error = authError(e)); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override void dispose() { handle.dispose(); email.dispose(); password.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(register ? 'Inscription' : 'Connexion')),
    body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: ListView(padding: const EdgeInsets.all(24), children: [
      const Text('Gym Bro', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
      const SizedBox(height: 24),
      if (register) TextField(key: const Key('handle'), controller: handle,
        onChanged: (_) { if (validated) setState(validateFields); },
        decoration: InputDecoration(labelText: 'Pseudo', errorText: handleError)),
      TextField(key: const Key('email'), controller: email,
        onChanged: (_) { if (validated) setState(validateFields); },
        decoration: InputDecoration(labelText: 'Email', errorText: emailError), keyboardType: TextInputType.emailAddress),
      TextField(key: const Key('password'), controller: password, obscureText: true,
        onChanged: (_) { if (validated) setState(validateFields); },
        decoration: InputDecoration(labelText: 'Mot de passe (12 caractères minimum)', errorText: passwordError)),
      if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
      const SizedBox(height: 24),
      FilledButton(onPressed: busy ? null : submit, child: Text(register ? 'Créer mon compte' : 'Connexion')),
      TextButton(onPressed: busy ? null : () => setState(() {
        register = !register; error = null; validated = false;
        handleError = emailError = passwordError = null;
      }), child: Text(register ? 'Déjà inscrit ? Connexion' : 'Créer un compte')),
    ]))),
  );
}

class HomeScreen extends StatefulWidget {
  final Api api; final String userId; final DraftStore store; final Future<void> Function() onLogout;
  const HomeScreen({super.key, required this.api, required this.userId, required this.store, required this.onLogout});
  @override State<HomeScreen> createState() => _HomeScreenState();
}
class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int tab = 0;
  List<dynamic> feed = [], history = [], templates = [];
  List<dynamic> followed = [], requests = [];
  Map<String, dynamic>? profile, settings;
  String? followCursor;
  bool subscriptions = false, hasMore = false;
  String? error;
  bool busy = false;
  late final OfflineOutbox outbox = OfflineOutbox(widget.store.prefs, widget.api, widget.userId);
  bool syncing = false;
  @override void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); syncPending(); }
  @override void dispose() { WidgetsBinding.instance.removeObserver(this); super.dispose(); }
  @override void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) syncPending();
  }
  Future<void> syncPending({bool retry = false}) async {
    if (syncing) return;
    syncing = true;
    try {
      for (final kind in OfflineOutbox.kinds) {
        final item = outbox.read(kind);
        if (item == null) continue;
        if (item['state'] != 'synced' && (retry || item['error'] == null)) await outbox.sync(kind);
        final updated = outbox.read(kind);
        if (updated?['state'] == 'synced') {
          final ids = {updated!['body']['clientId'], updated['priorClientId']};
          if (kind == 'strength' && ids.contains(widget.store.read(widget.userId)?['clientId'])) await widget.store.clear(widget.userId);
          if (kind == 'wod' && ids.contains(widget.store.readWod(widget.userId)?['clientId'])) await widget.store.clearWod(widget.userId);
          if (kind == 'hyrox' && ids.contains(widget.store.readHyrox(widget.userId)?['clientId'])) await widget.store.clearHyrox(widget.userId);
        }
      }
    } catch (_) { if (mounted) setState(() => error = 'Synchronisation locale indisponible. Réessayez.'); }
    finally { syncing = false; if (mounted) { setState(() {}); refresh(); } }
  }
  Future<void> resolveConflict(String kind) async {
    final confirmed = await showDialog<bool>(context: context, builder: (dialog) => AlertDialog(
      title: const Text('Créer une séance distincte ?'),
      content: const Text('La séance modifiée sur l’autre appareil ne sera pas écrasée. Une nouvelle séance privée sera créée avec la copie locale conservée ici.'),
      actions: [TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Créer une copie privée'))],
    ));
    if (confirmed != true) return;
    try { await outbox.forkConflict(kind, const Uuid().v4()); await syncPending(retry: true); }
    catch (_) { if (mounted) setState(() => error = 'Copie non créée. Les données locales sont conservées.'); }
  }
  Future<void> editRejected(String kind) async {
    try {
      final draft = kind == 'strength' ? widget.store.read(widget.userId) :
        kind == 'wod' ? widget.store.readWod(widget.userId) : widget.store.readHyrox(widget.userId);
      if (draft == null || draft['clientId'] != outbox.read(kind)?['body']['clientId']) {
        throw StateError('Local draft missing');
      }
      await outbox.reopenRejected(kind);
      if (!mounted) return;
      if (kind == 'strength') { await train(); }
      if (kind == 'wod') { await trainWod(); }
      if (kind == 'hyrox') { await trainHyrox(); }
    } catch (_) { if (mounted) setState(() => error = 'Brouillon conservé. Impossible de rouvrir cette séance.'); }
  }
  Future<void> openSynced(Map session) async {
    try {
      final latest = await widget.api.call('GET', '/sessions/${session['id']}') as Map;
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => CompletedScreen(api: widget.api, session: latest)));
      if (mounted) refresh();
    } catch (_) { if (mounted) setState(() => error = 'Résumé indisponible. Reconnectez-vous et réessayez.'); }
  }
  Future<void> refresh() async {
    setState(() { busy = true; error = null; feed = []; followed = []; followCursor = null; });
    try {
      final posts = await widget.api.call('GET', '/feed');
      final sessions = await widget.api.call('GET', '/sessions');
      if (mounted) setState(() { feed = posts as List; history = sessions as List; hasMore = feed.length == 20; });
      final summary = await widget.api.call('GET', '/me/summary');
      if (mounted) { setState(() => profile = Map<String, dynamic>.from(summary as Map)); }
      final own = await widget.api.call('GET', '/me');
      final inbox = await widget.api.call('GET', '/me/follow-requests');
      final page = await widget.api.call('GET', '/feed/following') as Map;
      if (mounted) { setState(() { settings = Map<String,dynamic>.from(own as Map); requests = inbox as List;
        followed = page['items'] as List; followCursor = page['nextCursor'] as String?; }); }
    } catch (e) { if (mounted) setState(() => error = 'Chargement impossible. Vérifiez votre connexion puis réessayez.'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> loadMore() async {
    if (busy || (subscriptions ? followCursor == null : !hasMore)) return;
    setState(() { busy = true; error = null; });
    try {
      if (subscriptions) {
        final page = await widget.api.call('GET', '/feed/following?cursor=$followCursor') as Map;
        if (mounted) setState(() { followed.addAll(page['items'] as List); followCursor = page['nextCursor'] as String?; });
      } else {
        final next = await widget.api.call('GET', '/feed?offset=${feed.length}') as List;
        if (mounted) setState(() { feed.addAll(next); hasMore = next.length == 20; });
      }
    } catch (_) { if (mounted) setState(() => error = 'Page indisponible. Réessayez.'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> loadTemplates() async {
    try {
      final items = await widget.api.call('GET', '/templates') as List;
      if (mounted) setState(() { templates = items; error = null; });
    } catch (_) { if (mounted) setState(() => error = 'Modèles indisponibles. Réessayez.'); }
  }
  Future<void> editTemplate(Map item) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => TemplateScreen(
      api: widget.api, store: widget.store, userId: widget.userId, template: item)));
    if (mounted) { await loadTemplates(); refresh(); }
  }
  Future<void> copyPost(String id) async {
    try {
      final item = await widget.api.call('POST', '/posts/$id/copy', {}) as Map;
      if (mounted) await editTemplate(item);
    } catch (_) { if (mounted) setState(() => error = 'Copie indisponible : accès retiré ou connexion interrompue. Réessayez.'); }
  }
  Future<void> openPost(String id) async {
    try {
      final post = await widget.api.call('GET', '/posts/$id') as Map;
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (context) => AlertDialog(
        title: Text('${post['title']}'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('@${post['author']} · ${sportLabel(post['sport'])} · ${dateLabel(post['date'])}'),
          if (isTechnicalPost(post)) const Text('Séance de test technique · compte jetable'),
          const SizedBox(height: 16), Text(exerciseSummary(post)),
          for (final exercise in (post['exercises'] as List? ?? [])) ...[
            const SizedBox(height: 12), Text('${exercise['name']}', style: const TextStyle(fontWeight: FontWeight.bold)),
            for (final set in (exercise['sets'] as List? ?? []))
              Text('${set['reps']} répétitions · ${set['weight']} ${set['unit']}'),
          ],
          if (post['sourceAuthor'] != null) Text('Inspiré de @${post['sourceAuthor']}'),
          if (post['sourceUnavailable'] == true) const Text('Source non disponible'),
        ])),
        actions: [
          if (post['sport'] == 'STRENGTH') TextButton(onPressed: () { Navigator.pop(context); copyPost(id); }, child: const Text('Copier et essayer')),
          if (post['authorId'] != null && post['authorId'] != widget.userId) ...[
            TextButton(onPressed: () async {
              Navigator.pop(context);
              await reportPost(id);
            }, child: const Text('Signaler')),
            TextButton(onPressed: () async {
              Navigator.pop(context);
              await blockAuthor('${post['authorId']}');
            }, child: const Text('Bloquer')),
          ],
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer')),
        ],
      ));
    } catch (e) { if (mounted) setState(() => error = '$e'); }
  }
  Future<void> reportPost(String id) async {
    var reason = '';
    try {
      final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
        title: const Text('Signaler la publication'),
        content: TextField(onChanged: (value) => reason = value, maxLength: 300, decoration: const InputDecoration(labelText: 'Motif')),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Envoyer'))],
      ));
      if (confirmed == true && reason.trim().isNotEmpty) {
        await widget.api.call('POST', '/posts/$id/reports', {'reason': reason.trim()});
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Signalement enregistré')));
      }
    } catch (e) { if (mounted) setState(() => error = '$e'); }

  }
  Future<void> blockAuthor(String authorId) async {
    try {
      final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
        title: const Text('Bloquer ce compte ?'), content: const Text('Ses publications disparaîtront de votre feed.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Bloquer'))],
      ));
      if (confirmed == true) { await widget.api.call('POST', '/users/$authorId/block', {}); await refresh(); }
    } catch (e) { if (mounted) setState(() => error = '$e'); }
  }
  Future<void> train() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => WorkoutScreen(api: widget.api, store: widget.store, userId: widget.userId)));
    refresh();
  }
  Future<void> trainWod() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => WodScreen(api: widget.api, store: widget.store, userId: widget.userId)));
    if (mounted) refresh();
  }
  Future<void> trainHyrox() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => HyroxScreen(api: widget.api, store: widget.store, userId: widget.userId)));
    if (mounted) refresh();
  }
  Future<void> searchAthlete() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => AthleteSearchScreen(api: widget.api, userId: widget.userId)));
    if (mounted) refresh();
  }
  Future<void> openAthlete(String id) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => AthleteScreen(api: widget.api, id: id, userId: widget.userId)));
    if (mounted) refresh();
  }
  Future<void> decideRequest(String id, bool accept) async {
    try { await widget.api.call('POST', '/follow-requests/$id/${accept ? 'accept' : 'reject'}', {}); await refresh(); }
    catch (_) { if (mounted) setState(() => error = 'Demande indisponible. Réessayez.'); }
  }
  Future<void> editProfile() async {
    final current = settings;
    if (current == null) return;
    final name = TextEditingController(text: current['displayName'] as String? ?? '');
    var privateAccount = current['private'] == true, unit = '${current['unit'] ?? 'kg'}';
    final submitted = await showDialog<Map<String,dynamic>>(context: context, builder: (dialog) => StatefulBuilder(builder: (dialog, update) => AlertDialog(
      title: const Text('Modifier mon profil'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, maxLength: 60, decoration: const InputDecoration(labelText: 'Nom public (facultatif)')),
        SwitchListTile(title: const Text('Compte privé'), value: privateAccount, onChanged: (v) => update(() => privateAccount = v)),
        DropdownButtonFormField<String>(initialValue: unit, decoration: const InputDecoration(labelText: 'Unité préférée'),
          items: ['kg','lb'].map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(), onChanged: (v) => update(() => unit = v!)),
        const Text('Un compte privé masque même les anciennes publications publiques aux inconnus.'),
      ])), actions: [TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(dialog, {'displayName': name.text.trim().isEmpty ? null : name.text.trim(), 'private': privateAccount, 'unit': unit}), child: const Text('Enregistrer'))],
    )));
    name.dispose();
    if (submitted == null) return;
    try { await widget.api.call('PUT', '/me/profile', submitted); await refresh(); }
    catch (_) { if (mounted) setState(() => error = 'Profil non enregistré. Réessayez.'); }
  }
  Future<void> openSession(Map session) async {
    try {
      final item = await widget.api.call('GET', '/sessions/${session['id']}') as Map;
      if (!mounted) return;
      if (item['status'] == 'DRAFT') {
        final kind = item['resultSchemaVersion'] == 3 ? 'hyrox' : item['resultSchemaVersion'] == 2 ? 'wod' : 'strength';
        if (outbox.read(kind)?['state'] != null && outbox.read(kind)?['state'] != 'synced') {
          setState(() => error = 'Une séance terminée localement attend sa synchronisation. Résolvez-la dans Mes séances avant de reprendre ce brouillon distant.');
          return;
        }
        if (item['resultSchemaVersion'] == 3) {
          final local = widget.store.readHyrox(widget.userId);
          if (local != null && local['clientId'] != item['clientId']) {
            setState(() => error = 'Une autre séance Hyrox est déjà en brouillon sur cet appareil. Terminez-la avant de reprendre celle-ci.');
            return;
          }
          final workout = item['workout'] as Map;
          await widget.store.saveHyrox(widget.userId, {
            'clientId': item['clientId'], 'title': item['title'], 'totalSeconds': workout['totalSeconds'],
            'segments': workout['segments'], 'notes': workout['notes'],
          });
          await trainHyrox();
          return;
        }
        if (item['resultSchemaVersion'] == 2) {
          final localWod = widget.store.readWod(widget.userId);
          if (localWod != null && localWod['clientId'] != item['clientId']) {
            setState(() => error = 'Un autre WOD est déjà en brouillon sur cet appareil. Terminez-le avant de reprendre cette séance du compte.');
            return;
          }
          final workout = item['workout'] as Map;
          await widget.store.saveWod(widget.userId, {
            'clientId': item['clientId'], 'title': item['title'], 'format': workout['format'],
            'timeCapSeconds': workout['timeCapSeconds'], 'movements': workout['movements'], 'result': workout['result'],
          });
          await trainWod();
          return;
        }
        final local = widget.store.read(widget.userId);
        if (local != null && local['clientId'] != item['clientId']) {
          setState(() => error = 'Un autre brouillon est déjà sur cet appareil. Terminez-le avant de reprendre cette séance du compte.');
          return;
        }
        final workout = item['workout'] as Map;
        final exercises = workout['exercises'] as List? ?? [];
        await widget.store.save(widget.userId, {'clientId': item['clientId'], 'title': item['title'],
          'unit': (exercises.isNotEmpty && (exercises.first['sets'] as List).isNotEmpty)
            ? exercises.first['sets'][0]['unit'] : 'kg', 'exercises': exercises});
        await train();
      } else {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => CompletedScreen(api: widget.api, session: item)));
        refresh();
      }
    } catch (_) { if (mounted) setState(() => error = 'Séance indisponible. Réessayez.'); }
  }
  Widget postCard(Map post) => gymCard(child: InkWell(
    onTap: () => openPost('${post['id']}'),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [CircleAvatar(backgroundColor: lime, foregroundColor: ink,
        child: Text('${post['author'] ?? '?'}'.substring(0, 1).toUpperCase())),
        const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          InkWell(onTap: post['authorId'] == null ? null : () => openAthlete('${post['authorId']}'),
            child: Text('@${post['author']} · Voir le profil', style: const TextStyle(fontWeight: FontWeight.w700, decoration: TextDecoration.underline))),
          Text('${sportLabel(post['sport'])} · ${dateLabel(post['date'])}'),
        ]))]),
      const SizedBox(height: 16), Text('${post['title']}', style: Theme.of(context).textTheme.titleLarge),
      if (isTechnicalPost(post)) const Text('Séance de test technique · compte jetable'),
      const SizedBox(height: 8), Text(exerciseSummary(post)),
      const SizedBox(height: 12), const Row(children: [Text('Voir la séance', style: TextStyle(fontWeight: FontWeight.w700)), SizedBox(width: 4), Icon(Icons.arrow_forward, size: 18)]),
    ]),
  ));
  Widget feedView() => ListView(padding: const EdgeInsets.all(16), children: [
    const Text('LE CLUB, SANS PRESSION', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.5)),
    const SizedBox(height: 8), Text('Bouge. Note. Partage.', style: Theme.of(context).textTheme.headlineLarge),
    const SizedBox(height: 10), const Text('Tes séances restent privées. Tu choisis si tu veux les partager avec la communauté.'),
    const SizedBox(height: 20), FilledButton.icon(onPressed: train, icon: const Icon(Icons.add), label: const Text('Commencer une séance')),
    const SizedBox(height: 22), Wrap(spacing: 8, children: [
      ChoiceChip(label: const Text('Découvrir'), selected: !subscriptions, onSelected: (_) => setState(() => subscriptions = false)),
      ChoiceChip(label: const Text('Abonnements'), selected: subscriptions, onSelected: (_) => setState(() => subscriptions = true)),
    ]),
    if (subscriptions && followed.isEmpty && !busy) gymCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Aucune publication de tes abonnements. Trouve un athlète à suivre ou attends sa prochaine séance.'),
      TextButton(onPressed: searchAthlete, child: const Text('Rechercher un athlète'))])),
    if (!subscriptions && feed.isEmpty && !busy) gymCard(child: const Text('Pas encore de séances publiques ici. Lance ta première séance ; elle restera privée jusqu’à ton choix de publier.')),
    if (!subscriptions) TextButton(onPressed: searchAthlete, child: const Text('Rechercher un athlète')),
    for (final entry in (subscriptions ? followed : feed)) postCard(entry as Map),
    if (subscriptions ? followCursor != null : hasMore) OutlinedButton(onPressed: busy ? null : loadMore, child: const Text('Voir plus de séances')),
  ]);
  Widget historyView() => ListView(padding: const EdgeInsets.all(16), children: [
    Text('Mes séances', style: Theme.of(context).textTheme.headlineLarge),
    for (final kind in OfflineOutbox.kinds) if (outbox.read(kind) case final item?)
      gymCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${item['body']['title']} · ${kind == 'strength' ? 'Musculation' : kind == 'wod' ? 'CrossFit' : 'Hyrox'}', style: Theme.of(context).textTheme.titleLarge),
        Text(item['state'] == 'synced' ? 'Synchronisée · privée (sauf publication volontaire)' :
          item['error'] == 'conflict' ? 'Conflit avec une autre modification : données locales conservées. Résolution nécessaire.' :
          item['error'] == 'auth' ? 'Session expirée : reconnectez-vous pour synchroniser.' :
          item['error'] == 'validation' ? 'Validation refusée : corrigez votre brouillon local.' :
          item['error'] == 'server' ? 'Erreur serveur : données locales conservées.' :
          'Terminée sur cet appareil · privée · en attente de synchronisation'),
        if (item['state'] != 'synced' && item['error'] != 'conflict' && item['error'] != 'validation')
          TextButton(onPressed: syncing ? null : () => syncPending(retry: true), child: const Text('Réessayer la synchronisation')),
        if (item['error'] == 'validation') TextButton(onPressed: () => editRejected(kind), child: const Text('Corriger mon brouillon')),
        if (item['error'] == 'conflict') TextButton(onPressed: syncing ? null : () => resolveConflict(kind),
          child: const Text('Créer une copie privée séparée')),
        if (item['state'] == 'synced' && item['session'] != null)
          TextButton(onPressed: () => openSynced(item['session'] as Map),
            child: const Text('Voir le résumé et choisir de publier')),
      ])),
    const SizedBox(height: 12), FilledButton.icon(onPressed: trainWod, icon: const Icon(Icons.timer_outlined),
      label: Text(widget.store.readWod(widget.userId) == null ? 'Créer un WOD CrossFit' : 'Reprendre mon WOD')),
    const SizedBox(height: 8), OutlinedButton.icon(onPressed: trainHyrox, icon: const Icon(Icons.route_outlined),
      label: Text(widget.store.readHyrox(widget.userId) == null ? 'Créer une séance Hyrox' : 'Reprendre ma séance Hyrox')),
    const SizedBox(height: 8), const Text('Tes modèles restent personnels. Adapte-les avant de démarrer une nouvelle séance.'),
    const SizedBox(height: 12), Text('Mes modèles', style: Theme.of(context).textTheme.titleLarge),
    if (templates.isEmpty) gymCard(child: const Text('Aucun modèle. Ouvre une séance visible du fil et choisis « Copier et essayer ».')),
    for (final item in templates) gymCard(child: ListTile(
      title: Text('${item['title']}'),
      subtitle: Text(item['sourceAuthor'] != null ? 'Inspiré de @${item['sourceAuthor']} · personnel'
        : item['sourceUnavailable'] == true ? 'Source non disponible · personnel' : 'Modèle personnel'),
      trailing: const Icon(Icons.chevron_right), onTap: () => editTemplate(item as Map))),
    TextButton(onPressed: loadTemplates, child: const Text('Actualiser mes modèles')),
    const SizedBox(height: 12), Text('Historique privé', style: Theme.of(context).textTheme.titleLarge),
    const SizedBox(height: 12),
    if (widget.store.read(widget.userId) != null) gymCard(child: ListTile(
      leading: const Icon(Icons.edit_note), title: const Text('Brouillon sur cet appareil'),
      subtitle: const Text('Privé · reprend là où tu en étais'), onTap: train)),
    if (widget.store.readWod(widget.userId) != null) gymCard(child: ListTile(
      leading: const Icon(Icons.timer_outlined), title: const Text('Brouillon WOD sur cet appareil'),
      subtitle: const Text('Privé · reprends tes mouvements et ton score'), onTap: trainWod)),
    if (widget.store.readHyrox(widget.userId) != null) gymCard(child: ListTile(
      leading: const Icon(Icons.route_outlined), title: const Text('Brouillon Hyrox sur cet appareil'),
      subtitle: const Text('Privé · reprends tes courses et tes stations'), onTap: trainHyrox)),
    if (history.isEmpty && !busy && OfflineOutbox.kinds.every((kind) => outbox.read(kind) == null)) gymCard(child: const Text('Aucune séance enregistrée sur ton compte. Commence par ton premier entraînement.')),
    for (final entry in history) gymCard(child: ListTile(
      title: Text('${entry['title']}'),
      subtitle: Text('${entry['status'] == 'DRAFT' ? 'En cours' : 'Terminée'} · ${dateLabel(entry['started_at'])} · ${entry['published'] == true ? 'publiée' : 'privée'}'),
      trailing: const Icon(Icons.chevron_right), onTap: () => openSession(entry as Map))),
  ]);
  Widget profileView() => ListView(padding: const EdgeInsets.all(16), children: [
    Text('Mon espace', style: Theme.of(context).textTheme.headlineLarge),
    const SizedBox(height: 16), gymCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      CircleAvatar(radius: 28, backgroundColor: lime, foregroundColor: ink,
        child: Text('${profile?['handle'] ?? '?'}'.substring(0, 1).toUpperCase())),
      const SizedBox(height: 12), Text('@${profile?['handle'] ?? '…'}', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8), const Text('Ton espace personnel. Pas de classement, juste tes efforts.'),
      if (settings != null) ...[const SizedBox(height: 8), Text('${settings!['private'] == true ? 'Compte privé' : 'Compte public'} · ${settings!['unit'] ?? 'kg'}'),
        if (settings!['displayName'] != null) Text('${settings!['displayName']}')],
    ])),
    OutlinedButton(onPressed: editProfile, child: const Text('Modifier mon profil')),
    if (requests.isNotEmpty) ...[Text('Demandes de suivi', style: Theme.of(context).textTheme.titleLarge),
      for (final item in requests) gymCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('@${item['handle']}'), Wrap(children: [TextButton(onPressed: () => decideRequest('${item['id']}', true), child: const Text('Accepter')),
          TextButton(onPressed: () => decideRequest('${item['id']}', false), child: const Text('Refuser'))])]))],
    gymCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${profile?['sessions'] ?? '…'} ${profile?['sessions'] == 1 ? 'séance terminée' : 'séances terminées'}', style: Theme.of(context).textTheme.titleLarge),
      Text('${profile?['publications'] ?? '…'} ${profile?['publications'] == 1 ? 'publication' : 'publications'} · calculées sur ton compte'),
    ])),
    gymCard(child: const Text('Unités disponibles en séance : kg ou lb. Change-les dans le formulaire avant de terminer.')),
    OutlinedButton.icon(onPressed: widget.onLogout, icon: const Icon(Icons.logout), label: const Text('Se déconnecter')),
  ]);
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('GYM BRO', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2)), actions: [IconButton(tooltip: 'Actualiser', onPressed: refresh, icon: const Icon(Icons.refresh))]),
    body: Column(children: [
      if (busy) const LinearProgressIndicator(),
      if (error != null) Padding(padding: const EdgeInsets.all(12), child: Row(children: [Expanded(child: Text(error!, style: const TextStyle(color: Colors.red))), TextButton(onPressed: refresh, child: const Text('Réessayer'))])),
      Expanded(child: switch (tab) { 0 => feedView(), 1 => historyView(), _ => profileView() }),
    ]),
    floatingActionButton: tab == 0 ? null : FloatingActionButton.extended(onPressed: train, icon: const Icon(Icons.fitness_center), label: Text(widget.store.read(widget.userId) == null ? 'Nouvelle séance' : 'Reprendre')),
    bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (i) { setState(() => tab = i); if (i == 1) loadTemplates(); }, destinations: const [NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Accueil'), NavigationDestination(icon: Icon(Icons.fitness_center_outlined), label: 'Entraînement'), NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profil')]),
  );
}

class AthleteSearchScreen extends StatefulWidget {
  final Api api; final String userId;
  const AthleteSearchScreen({super.key, required this.api, required this.userId});
  @override State<AthleteSearchScreen> createState() => _AthleteSearchState();
}
class _AthleteSearchState extends State<AthleteSearchScreen> {
  final query = TextEditingController();
  List<dynamic> results = [];
  String? error;
  bool busy = false, searched = false;
  Future<void> search() async {
    if (query.text.trim().length < 2) { setState(() => error = 'Saisissez au moins deux caractères.'); return; }
    setState(() { busy = true; error = null; results = []; searched = false; });
    try { final data = await widget.api.call('GET', '/users?query=${Uri.encodeQueryComponent(query.text.trim())}') as List;
      if (mounted) setState(() { results = data; searched = true; }); }
    catch (_) { if (mounted) setState(() => error = 'Recherche impossible. Réessayez.'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override void dispose() { query.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Trouver un athlète')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      TextField(key: const Key('athlete-query'), controller: query, decoration: const InputDecoration(labelText: 'Pseudo ou nom public'), onSubmitted: (_) => search()),
      const SizedBox(height: 12), FilledButton(onPressed: busy ? null : search, child: const Text('Rechercher')),
      if (busy) const LinearProgressIndicator(),
      if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
      if (searched && results.isEmpty) const Text('Aucun athlète trouvé.'),
      for (final entry in results) gymCard(child: ListTile(
        leading: const Icon(Icons.person_outline), title: Text('@${entry['handle']}'),
        subtitle: Text('${entry['displayName'] ?? (entry['private'] == true ? 'Compte privé' : 'Compte public')}'),
        trailing: const Icon(Icons.chevron_right), onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => AthleteScreen(api: widget.api, id: '${entry['id']}', userId: widget.userId)));
          if (mounted) search();
        })),
    ]));
}

class AthleteScreen extends StatefulWidget {
  final Api api; final String id, userId;
  const AthleteScreen({super.key, required this.api, required this.id, required this.userId});
  @override State<AthleteScreen> createState() => _AthleteState();
}
class _AthleteState extends State<AthleteScreen> {
  Map? profile;
  List<dynamic> posts = [];
  String? cursor, error;
  bool busy = false, hidden = false;
  @override void initState() { super.initState(); refresh(); }
  Future<void> refresh() async {
    setState(() { busy = true; error = null; profile = null; posts = []; cursor = null; hidden = false; });
    try {
      final data = await widget.api.call('GET', '/users/${widget.id}') as Map;
      if (mounted) setState(() => profile = data);
      await loadPosts(reset: true);
    } catch (e) {
      if (mounted) setState(() { if (e is ApiHttpFailure && e.status == 404) { hidden = true; posts = []; } else { error = 'Profil indisponible. Réessayez.'; } });
    } finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> loadPosts({bool reset = false}) async {
    try {
      final data = await widget.api.call('GET', '/users/${widget.id}/posts${reset || cursor == null ? '' : '?cursor=$cursor'}') as Map;
      if (mounted) setState(() { posts = reset ? data['items'] as List : [...posts, ...data['items'] as List]; cursor = data['nextCursor'] as String?; hidden = false; });
    } on ApiHttpFailure catch (e) {
      if (e.status == 404) { if (mounted) setState(() { posts = []; hidden = true; cursor = null; }); }
      else { if (mounted) setState(() => error = 'Séances indisponibles. Réessayez.'); }
    } catch (_) { if (mounted) setState(() => error = 'Séances indisponibles. Réessayez.'); }
  }
  Future<void> toggle() async {
    setState(() { busy = true; error = null; });
    try { await widget.api.call(profile?['relation'] == 'NONE' ? 'POST' : 'DELETE', '/users/${widget.id}/follow', profile?['relation'] == 'NONE' ? {} : null); await refresh(); }
    catch (_) { if (mounted) setState(() => error = 'Suivi indisponible. Réessayez.'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Profil athlète')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      if (busy) const LinearProgressIndicator(),
      if (error != null) TextButton(onPressed: refresh, child: Text(error!)),
      if (profile != null) ...[
        gymCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(backgroundColor: lime, foregroundColor: ink, child: Text('${profile!['handle']}'.substring(0,1).toUpperCase())),
          const SizedBox(height: 12), Text('@${profile!['handle']}', style: Theme.of(context).textTheme.titleLarge),
          if (profile!['displayName'] != null) Text('${profile!['displayName']}'),
          Text(profile!['private'] == true ? 'Compte privé' : 'Compte public'),
        ])),
        if (widget.id != widget.userId) FilledButton(onPressed: busy ? null : toggle,
          child: Text(switch (profile!['relation']) { 'PENDING' => 'Annuler la demande', 'ACCEPTED' => 'Ne plus suivre', _ => profile!['private'] == true ? 'Demander à suivre' : 'Suivre' })),
        if (profile!['relation'] == 'PENDING') const Text('Demande envoyée · en attente de réponse.'),
        if (hidden) const Text('Les séances de ce compte privé ne sont pas accessibles.'),
        if (!hidden && posts.isEmpty && !busy) const Text('Aucune séance partagée accessible.'),
        for (final entry in posts) gymCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${entry['title']}', style: Theme.of(context).textTheme.titleLarge),
          Text('${dateLabel(entry['date'])} · ${exerciseSummary(entry as Map)}'),
        ])),
        if (cursor != null) OutlinedButton(onPressed: busy ? null : () => loadPosts(), child: const Text('Voir plus de séances')),
      ],
    ]));
}

class WorkoutScreen extends StatefulWidget {
  final Api api; final DraftStore store; final String userId;
  const WorkoutScreen({super.key, required this.api, required this.store, required this.userId});
  @override State<WorkoutScreen> createState() => _WorkoutScreenState();
}
class SetEntry {
  final reps = TextEditingController(), weight = TextEditingController();
  bool checked = false;
  String unit = 'kg';
  void dispose() { reps.dispose(); weight.dispose(); }
}
class ExerciseEntry {
  final name = TextEditingController();
  final sets = <SetEntry>[SetEntry()];
  void dispose() { name.dispose(); for (final set in sets) { set.dispose(); } }
}
class _WorkoutScreenState extends State<WorkoutScreen> {
  final title = TextEditingController(), exercise = TextEditingController();
  final sets = <SetEntry>[SetEntry()];
  final moreExercises = <ExerciseEntry>[];
  List<Map<String, dynamic>> catalogue = [];
  Future<void> pendingSave = Future.value();
  String unit = 'kg', clientId = const Uuid().v4();
  bool busy = false;
  String? error;
  @override void initState() {
    super.initState();
    loadCatalogue();
    final saved = widget.store.read(widget.userId);
    if (saved != null) {
      clientId = '${saved['clientId']}'; title.text = '${saved['title'] ?? ''}'; exercise.text = '${saved['exercise'] ?? ''}';
      unit = '${saved['unit'] ?? 'kg'}';
      final savedExercises = saved['exercises'] as List?;
      if (savedExercises != null && savedExercises.isNotEmpty) exercise.text = '${savedExercises.first['name'] ?? ''}';
      final savedSets = savedExercises != null && savedExercises.isNotEmpty ? savedExercises.first['sets'] as List? : saved['sets'] as List?;
      if (savedSets != null && savedSets.isNotEmpty) {
        sets.first.dispose(); sets.clear();
        for (final entry in savedSets) {
          final set = SetEntry(); set.reps.text = '${entry['reps'] ?? ''}'; set.weight.text = '${entry['weight'] ?? ''}'; set.checked = entry['checked'] == true;
          set.unit = '${entry['unit'] ?? unit}'; sets.add(set);
        }
      }
      for (final item in savedExercises?.skip(1) ?? []) {
        final additional = ExerciseEntry()..name.text = '${item['name'] ?? ''}';
        additional.sets.first.dispose(); additional.sets.clear();
        for (final entry in (item['sets'] as List? ?? [])) {
          final set = SetEntry()..checked = entry['checked'] == true;
          set.unit = '${entry['unit'] ?? unit}';
          set.reps.text = '${entry['reps'] ?? ''}'; set.weight.text = '${entry['weight'] ?? ''}';
          additional.sets.add(set);
        }
        if (additional.sets.isEmpty) additional.sets.add(SetEntry());
        moreExercises.add(additional);
      }
    }
  }
  Future<void> loadCatalogue() async {
    try {
      final data = await widget.api.call('GET', '/exercises') as List;
      if (mounted) setState(() => catalogue = data.map((item) => Map<String, dynamic>.from(item as Map)).toList());
    } catch (_) { if (mounted) setState(() => error = 'Catalogue indisponible. Réessayez.'); }
  }
  Map<String, dynamic> snapshotExercise(String name, List<SetEntry> entries) => {'name': name,
    'sets': entries.map((s) => {'reps': s.reps.text, 'weight': s.weight.text, 'checked': s.checked, 'unit': s.unit}).toList()};
  Map<String, dynamic> get draft => {'clientId': clientId, 'title': title.text, 'unit': unit,
    'exercises': [snapshotExercise(exercise.text, sets), for (final item in moreExercises) snapshotExercise(item.name.text, item.sets)]};
  Future<void> save() async {
    final snapshot = draft;
    try {
      pendingSave = pendingSave.catchError((Object _) {}).then((_) => widget.store.save(widget.userId, snapshot));
      await pendingSave;
      if (mounted) setState(() => error = null);
    }
    catch (_) { if (mounted) setState(() => error = 'Sauvegarde locale impossible. Vérifiez l’espace disponible puis réessayez.'); }
  }
  Future<void> finish() async {
    setState(() { busy = true; error = null; });
    try {
      await save();
      if (error != null) throw StateError(error!);
      if (title.text.trim().isEmpty || title.text.trim().length > 100) throw const FormatException('Titre requis (100 caractères maximum).');
      final entries = [(exercise.text, sets), for (final item in moreExercises) (item.name.text, item.sets)];
      final exercises = <Map<String, dynamic>>[];
      for (final (name, series) in entries) {
        if (name.trim().isEmpty || name.trim().length > 80) throw const FormatException('Choisissez un exercice (80 caractères maximum).');
        final results = <Map<String, dynamic>>[];
        for (final set in series) {
          final n = int.tryParse(set.reps.text), w = num.tryParse(set.weight.text.replaceAll(',', '.'));
          if (n == null || n < 1 || n > 1000 || w == null || w < 0 || w > 10000 || (w * 100).roundToDouble() != w * 100) {
            throw const FormatException('Série : 1 à 1000 répétitions, charge de 0 à 10000 avec deux décimales maximum.');
          }
          results.add({'reps': n, 'weight': w, 'unit': set.unit});
        }
        exercises.add({'name': name.trim(), 'sets': results});
      }
      final payload = {'clientId': clientId, 'title': title.text.trim(), 'exercises': exercises};
      final outbox = OfflineOutbox(widget.store.prefs, widget.api, widget.userId);
      await outbox.enqueue('strength', payload);
      final result = await outbox.sync('strength');
      if (result?['state'] != 'synced') {
        if (mounted) Navigator.pop(context);
        return;
      }
      final done = result!['session'] as Map;
      await widget.store.clear(widget.userId);
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => CompletedScreen(api: widget.api, session: done)));
      if (mounted) Navigator.pop(context);
    } on FormatException catch (e) { if (mounted) setState(() => error = e.message); }
      catch (_) { if (mounted) setState(() => error = 'Séance conservée sur cet appareil. Terminez la synchronisation précédente avant de modifier cette séance.'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override void dispose() { title.dispose(); exercise.dispose(); for (final set in sets) { set.dispose(); } for (final item in moreExercises) { item.dispose(); } super.dispose(); }
  Widget setFields(SetEntry set, int index) => gymCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text('Série ${index + 1}', style: Theme.of(context).textTheme.titleLarge),
    const SizedBox(height: 12), Row(children: [
      Expanded(child: TextField(controller: set.reps, onChanged: (_) => save(), keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Répétitions'))),
      const SizedBox(width: 10), Expanded(child: TextField(controller: set.weight, onChanged: (_) => save(),
        keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: 'Charge (${set.unit})'))),
    ]),
    CheckboxListTile(contentPadding: EdgeInsets.zero, value: set.checked, title: const Text('Série validée'),
      onChanged: (value) { setState(() => set.checked = value ?? false); save(); }),
  ]));
  Widget exerciseFields(TextEditingController name, List<SetEntry> series, int index) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Text('0${index + 1} / Mouvement', style: Theme.of(context).textTheme.titleLarge),
    const SizedBox(height: 10), TextField(key: index == 0 ? const Key('exercise-name') : Key('exercise-$index'),
      controller: name, onChanged: (_) => save(), decoration: const InputDecoration(labelText: 'Exercice')),
    if (catalogue.isNotEmpty) SizedBox(height: 58, child: ListView(scrollDirection: Axis.horizontal, children: [
      for (final item in catalogue) Padding(padding: const EdgeInsets.only(right: 8), child: ActionChip(
        label: Text('${item['name']}'), onPressed: () { name.text = '${item['name']}'; setState(() {}); save(); })),
    ])),
    for (var i = 0; i < series.length; i++) setFields(series[i], i),
    OutlinedButton.icon(onPressed: series.length >= 30 ? null : () { setState(() => series.add(SetEntry()..unit = unit)); save(); },
      icon: const Icon(Icons.add), label: const Text('Ajouter une série')),
    const SizedBox(height: 20),
  ]);
  @override Widget build(BuildContext context) {
    final pending = OfflineOutbox(widget.store.prefs, widget.api, widget.userId).read('strength');
    if (pending != null && pending['state'] != 'synced') { return Scaffold(appBar: AppBar(title: const Text('Séance musculation')),
      body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Séance terminée en privé sur cet appareil. ${pending['error'] == 'conflict' ? 'Conflit : vos données sont conservées.' : 'Synchronisation en attente : revenez à Mes séances pour réessayer.'}'))));
    }
    return Scaffold(appBar: AppBar(title: const Text('Séance musculation')),
    body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 500), child: ListView(padding: const EdgeInsets.all(20), children: [
      Text('À ton rythme.', style: Theme.of(context).textTheme.headlineLarge),
      const SizedBox(height: 8), const Text('Chaque série se coche en un geste. Quitte l’écran quand tu veux : le brouillon reste sur cet appareil, privé.'),
      const SizedBox(height: 22), TextField(key: const Key('workout-title'), controller: title, onChanged: (_) => save(), decoration: const InputDecoration(labelText: 'Nom de ta séance')),
      const SizedBox(height: 12), DropdownButtonFormField<String>(initialValue: unit, decoration: const InputDecoration(labelText: 'Unité des charges'),
        items: ['kg', 'lb'].map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(), onChanged: (value) { setState(() {
          unit = value!; for (final set in sets) { set.unit = unit; }
          for (final entry in moreExercises) { for (final set in entry.sets) { set.unit = unit; } }
        }); save(); }),
      const SizedBox(height: 24), exerciseFields(exercise, sets, 0),
      for (var i = 0; i < moreExercises.length; i++) exerciseFields(moreExercises[i].name, moreExercises[i].sets, i + 1),
      OutlinedButton.icon(onPressed: moreExercises.length >= 19 ? null : () { setState(() => moreExercises.add(ExerciseEntry()..sets.first.unit = unit)); save(); },
        icon: const Icon(Icons.add), label: const Text('Ajouter un exercice')),
      if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
      if (error == 'Catalogue indisponible. Réessayez.') TextButton(onPressed: loadCatalogue, child: const Text('Réessayer le catalogue')),
      TextButton(onPressed: () async { await save(); if (context.mounted && error == null) Navigator.pop(context); }, child: const Text('Quitter et reprendre plus tard')),
      FilledButton(onPressed: busy ? null : finish, child: const Text('Terminer en privé')),
    ]))),
  );
  }
}

class CompletedScreen extends StatefulWidget {
  final Api api; final Map session;
  const CompletedScreen({super.key, required this.api, required this.session});
  @override State<CompletedScreen> createState() => _CompletedScreenState();
}
class _CompletedScreenState extends State<CompletedScreen> {
  String? error;
  bool busy = false, published = false;
  @override void initState() { super.initState(); published = widget.session['published'] == true; }
  Future<void> publish(String audience) async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Partager cette séance ?'),
      content: Text('Son titre, ${widget.session['resultSchemaVersion'] == 3 ? 'les courses, stations, distances, durées, charges et ton temps total (jamais tes notes privées)' : widget.session['resultSchemaVersion'] == 2 ? 'son format, ses mouvements et ton résultat' : 'tes exercices, séries, répétitions et charges'} seront visibles ${audience == 'PUBLIC' ? 'publiquement (sauf si ton compte est privé)' : 'uniquement par tes abonnés acceptés'}. Pas ton email ni l’heure précise.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Rester privé')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirmer la publication'))],
    ));
    if (confirmed != true || !mounted) return;
    setState(() { busy = true; error = null; });
    try { await widget.api.call('POST', '/sessions/${widget.session['id']}/posts', {'audience': audience}); if (mounted) setState(() => published = true); }
    catch (_) { if (mounted) setState(() => error = 'Publication impossible. Votre séance reste privée ; réessayez.'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Séance terminée')),
    body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: ListView(padding: const EdgeInsets.all(24), children: [
      const Icon(Icons.check_circle, color: ink, size: 52),
      const SizedBox(height: 12), Text('Bien joué !', style: Theme.of(context).textTheme.headlineLarge),
      const SizedBox(height: 12), Text('${widget.session['title']}', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12), Text(published ? 'Séance partagée avec l’audience choisie.' : 'Enregistrée dans votre historique privé. La publication est facultative.'),
      if (widget.session['resultSchemaVersion'] == 2) gymCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${widget.session['workout']['format']} · ${widget.session['workout']['timeCapSeconds']} s de time cap', style: Theme.of(context).textTheme.titleLarge),
        Text((widget.session['workout']['movements'] as List).join(' · ')),
        Text(exerciseSummary({...widget.session['workout'], 'sport': 'CROSSFIT'})),
      ])),
      if (widget.session['resultSchemaVersion'] == 3) gymCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Hyrox · ${widget.session['workout']['totalSeconds']} s', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8), Text(exerciseSummary({...widget.session['workout'], 'sport': 'HYROX'})),
        if ('${widget.session['workout']['notes'] ?? ''}'.isNotEmpty) const Text('Tes notes restent privées.'),
      ])),
      for (final exercise in (widget.session['workout']?['exercises'] as List? ?? [])) ...[
        const SizedBox(height: 12), gymCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${exercise['name']}', style: Theme.of(context).textTheme.titleLarge),
          for (final set in (exercise['sets'] as List? ?? []))
            Text('${set['reps']} répétitions · ${set['weight']} ${set['unit']}'),
        ])),
      ],
      if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
      if (published) const Text('Publication effectuée.'),
      if (!published) FilledButton(onPressed: busy ? null : () => publish('PUBLIC'), child: const Text('Publier publiquement')),
      if (!published) OutlinedButton(onPressed: busy ? null : () => publish('FOLLOWERS'), child: const Text('Publier pour mes abonnés')),
      TextButton(onPressed: () => Navigator.pop(context), child: Text(published ? 'Retour à l’accueil' : 'Garder privée / Retour à l’accueil')),
    ]))),
  );
}
