import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

const apiBase = String.fromEnvironment('API_BASE', defaultValue: 'http://127.0.0.1:18081/api/v1');
void main() => runApp(const GymApp());

class ApiUnauthorized implements Exception {
  @override String toString() => 'Session expirée. Reconnectez-vous.';
}

class DraftStore {
  final SharedPreferences prefs;
  DraftStore(this.prefs);
  static Future<DraftStore> open() async => DraftStore(await SharedPreferences.getInstance());
  Map<String, dynamic>? read(String user) {
    final value = prefs.getString('draft:$user');
    return value == null ? null : jsonDecode(value) as Map<String, dynamic>;
  }
  Future<void> save(String user, Map<String, dynamic> data) async {
    if (!await prefs.setString('draft:$user', jsonEncode(data))) throw StateError('Draft not saved');
  }
  Future<void> clear(String user) async {
    if (!await prefs.remove('draft:$user')) throw StateError('Draft not cleared');
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
      throw Exception('HTTP ${response.statusCode}: opération refusée');
    }
    return response.body.isEmpty ? null : jsonDecode(response.body);
  }
}

class GymApp extends StatefulWidget {
  const GymApp({super.key});
  @override State<GymApp> createState() => _GymAppState();
}
class _GymAppState extends State<GymApp> {
  final api = Api();
  DraftStore? store;
  String? userId;
  bool loading = true;
  String? restoreError;
  @override void initState() { super.initState(); _restore(); }
  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    api.token = prefs.getString('token');
    final id = prefs.getString('userId');
    if (api.token != null && id != null) {
      try { await api.call('GET', '/me'); userId = id; restoreError = null; }
      on ApiUnauthorized { api.token = null; await prefs.remove('token'); await prefs.remove('userId'); }
      catch (_) { restoreError = 'Réseau indisponible. Vérifiez votre connexion puis Réessayer.'; }
    }
    if (mounted) setState(() { store = DraftStore(prefs); loading = false; });
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
    title: 'Gym Bro', theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff355ad2))),
    home: loading ? const Scaffold(body: Center(child: CircularProgressIndicator()))
      : restoreError != null ? Scaffold(body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(restoreError!), TextButton(onPressed: () { setState(() { loading = true; restoreError = null; }); _restore(); }, child: const Text('Réessayer')),
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
  Future<void> submit() async {
    setState(() { busy = true; error = null; });
    try {
      final data = await widget.api.call('POST', register ? '/auth/register' : '/auth/login', {
        if (register) 'handle': handle.text.trim(), 'email': email.text.trim(), 'password': password.text,
      });
      await widget.onSuccess(Map<String, dynamic>.from(data as Map));
    } catch (e) { if (mounted) setState(() => error = '$e'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override void dispose() { handle.dispose(); email.dispose(); password.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(register ? 'Inscription' : 'Connexion')),
    body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: ListView(padding: const EdgeInsets.all(24), children: [
      const Text('Gym Bro', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
      const SizedBox(height: 24),
      if (register) TextField(key: const Key('handle'), controller: handle, decoration: const InputDecoration(labelText: 'Pseudo')),
      TextField(controller: email, decoration: const InputDecoration(labelText: 'Email'), keyboardType: TextInputType.emailAddress),
      TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Mot de passe (12 caractères minimum)')),
      if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
      const SizedBox(height: 24),
      FilledButton(onPressed: busy ? null : submit, child: Text(register ? 'Créer mon compte' : 'Connexion')),
      TextButton(onPressed: () => setState(() => register = !register), child: Text(register ? 'Déjà inscrit ? Connexion' : 'Créer un compte')),
    ]))),
  );
}

class HomeScreen extends StatefulWidget {
  final Api api; final String userId; final DraftStore store; final Future<void> Function() onLogout;
  const HomeScreen({super.key, required this.api, required this.userId, required this.store, required this.onLogout});
  @override State<HomeScreen> createState() => _HomeScreenState();
}
class _HomeScreenState extends State<HomeScreen> {
  int tab = 0;
  List<dynamic> feed = [], history = [];
  String? error;
  bool busy = false;
  @override void initState() { super.initState(); refresh(); }
  Future<void> refresh() async {
    setState(() { busy = true; error = null; });
    try {
      final posts = await widget.api.call('GET', '/feed');
      final sessions = await widget.api.call('GET', '/sessions');
      if (mounted) setState(() { feed = posts as List; history = sessions as List; });
    } catch (e) { if (mounted) setState(() => error = '$e'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> openPost(String id) async {
    try {
      final post = await widget.api.call('GET', '/posts/$id') as Map;
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (context) => AlertDialog(
        title: Text('${post['title']}'),
        content: Text('${post['author']} · ${post['sport']} · ${post['exerciseCount']} exercice(s) · ${post['date']}'),
        actions: [
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
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Gym Bro'), actions: [IconButton(tooltip: 'Actualiser', onPressed: refresh, icon: const Icon(Icons.refresh)), IconButton(tooltip: 'Déconnexion', onPressed: widget.onLogout, icon: const Icon(Icons.logout))]),
    body: Column(children: [
      if (busy) const LinearProgressIndicator(),
      if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
      Expanded(child: tab == 0 ? (feed.isEmpty ? const Center(child: Text('Aucune publication publique pour le moment.'))
        : ListView.builder(itemCount: feed.length, itemBuilder: (_, i) {
          final post = feed[i] as Map;
          return ListTile(title: Text('${post['title']}'), subtitle: Text('${post['author']} · ${post['sport']} · ${post['date']}'), onTap: () => openPost('${post['id']}'));
        })) : (history.isEmpty ? const Center(child: Text('Votre historique est vide.'))
        : ListView.builder(itemCount: history.length, itemBuilder: (_, i) {
          final session = history[i] as Map;
          return ListTile(title: Text('${session['title']}'), subtitle: Text('${session['status']} · privé par défaut'), onTap: () async {
            final item = await widget.api.call('GET', '/sessions/${session['id']}') as Map;
            if (!context.mounted) return;
            await Navigator.push(context, MaterialPageRoute(builder: (_) => CompletedScreen(api: widget.api, session: item)));
            refresh();
          });
        }))),
    ]),
    floatingActionButton: FloatingActionButton.extended(onPressed: train, icon: const Icon(Icons.fitness_center), label: Text(widget.store.read(widget.userId) == null ? 'Nouvelle séance' : 'Reprendre')),
    bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (i) => setState(() => tab = i), destinations: const [NavigationDestination(icon: Icon(Icons.dynamic_feed), label: 'Feed'), NavigationDestination(icon: Icon(Icons.history), label: 'Historique')]),
  );
}

class WorkoutScreen extends StatefulWidget {
  final Api api; final DraftStore store; final String userId;
  const WorkoutScreen({super.key, required this.api, required this.store, required this.userId});
  @override State<WorkoutScreen> createState() => _WorkoutScreenState();
}
class SetEntry {
  final reps = TextEditingController(), weight = TextEditingController();
  void dispose() { reps.dispose(); weight.dispose(); }
}
class _WorkoutScreenState extends State<WorkoutScreen> {
  final title = TextEditingController(), exercise = TextEditingController();
  final sets = <SetEntry>[SetEntry()];
  Future<void> pendingSave = Future.value();
  String unit = 'kg', clientId = const Uuid().v4();
  bool busy = false;
  String? error;
  @override void initState() {
    super.initState();
    final saved = widget.store.read(widget.userId);
    if (saved != null) {
      clientId = '${saved['clientId']}'; title.text = '${saved['title'] ?? ''}'; exercise.text = '${saved['exercise'] ?? ''}';
      unit = '${saved['unit'] ?? 'kg'}';
      final savedSets = saved['sets'] as List?;
      if (savedSets != null && savedSets.isNotEmpty) {
        sets.first.dispose(); sets.clear();
        for (final entry in savedSets) {
          final set = SetEntry(); set.reps.text = '${entry['reps'] ?? ''}'; set.weight.text = '${entry['weight'] ?? ''}'; sets.add(set);
        }
      }
    }
  }
  Map<String, dynamic> get draft => {'clientId': clientId, 'title': title.text, 'exercise': exercise.text, 'sets': sets.map((s) => {'reps': s.reps.text, 'weight': s.weight.text}).toList(), 'unit': unit};
  Future<void> save() async {
    final snapshot = draft;
    try {
      pendingSave = pendingSave.catchError((Object _) {}).then((_) => widget.store.save(widget.userId, snapshot));
      await pendingSave;
      if (mounted) setState(() => error = null);
    }
    catch (e) { if (mounted) setState(() => error = 'Sauvegarde locale impossible: $e'); }
  }
  Future<void> finish() async {
    setState(() { busy = true; error = null; });
    try {
      await save();
      if (error != null) throw StateError(error!);
      if (title.text.trim().isEmpty || exercise.text.trim().isEmpty) throw const FormatException('Titre et exercice requis');
      final results = <Map<String, dynamic>>[];
      for (final set in sets) {
        final n = int.tryParse(set.reps.text), w = num.tryParse(set.weight.text);
        if (n == null || n < 1 || w == null || w < 0) throw const FormatException('Répétitions et charge valides requises pour chaque série');
        results.add({'reps': n, 'weight': w, 'unit': unit});
      }
      final payload = {'clientId': clientId, 'title': title.text.trim(), 'exercises': [{'name': exercise.text.trim(), 'sets': results}]};
      final session = await widget.api.call('POST', '/sessions', payload) as Map;
      final id = session['id'];
      // A stable clientId makes a retry safe if the response was lost.
      if (session['status'] == 'DRAFT') await widget.api.call('PUT', '/sessions/$id', payload);
      final done = await widget.api.call('POST', '/sessions/$id/complete') as Map;
      await widget.store.clear(widget.userId);
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => CompletedScreen(api: widget.api, session: done)));
      if (mounted) Navigator.pop(context);
    } catch (e) { if (mounted) setState(() => error = '$e'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override void dispose() { title.dispose(); exercise.dispose(); for (final set in sets) { set.dispose(); } super.dispose(); }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Séance musculation')),
    body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 500), child: ListView(padding: const EdgeInsets.all(20), children: [
      const Text('Brouillon local — privé jusqu’à publication explicite.'),
      TextField(key: const Key('workout-title'), controller: title, onChanged: (_) => save(), decoration: const InputDecoration(labelText: 'Titre')),
      TextField(controller: exercise, onChanged: (_) => save(), decoration: const InputDecoration(labelText: 'Exercice')),
      for (var i = 0; i < sets.length; i++) ...[
        Text('Série ${i + 1}'),
        TextField(controller: sets[i].reps, onChanged: (_) => save(), keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Répétitions')),
        TextField(controller: sets[i].weight, onChanged: (_) => save(), keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Charge')),
      ],
      TextButton(onPressed: sets.length >= 30 ? null : () { setState(() => sets.add(SetEntry())); save(); }, child: const Text('Ajouter une série')),
      DropdownButton<String>(value: unit, items: ['kg', 'lb'].map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(), onChanged: (value) { setState(() => unit = value!); save(); }),
      if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
      OutlinedButton(onPressed: save, child: const Text('Sauvegarder localement')),
      FilledButton(onPressed: busy ? null : finish, child: const Text('Terminer en privé')),
    ]))),
  );
}

class CompletedScreen extends StatefulWidget {
  final Api api; final Map session;
  const CompletedScreen({super.key, required this.api, required this.session});
  @override State<CompletedScreen> createState() => _CompletedScreenState();
}
class _CompletedScreenState extends State<CompletedScreen> {
  String? error;
  bool busy = false, published = false;
  Future<void> publish() async {
    setState(() { busy = true; error = null; });
    try { await widget.api.call('POST', '/sessions/${widget.session['id']}/posts'); if (mounted) setState(() => published = true); }
    catch (e) { if (mounted) setState(() => error = '$e'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Séance terminée')),
    body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: ListView(padding: const EdgeInsets.all(24), children: [
      Text('${widget.session['title']}', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 12), const Text('Enregistrée dans votre historique privé. La publication est facultative.'),
      for (final exercise in (widget.session['workout']?['exercises'] as List? ?? [])) ...[
        const SizedBox(height: 12), Text('${exercise['name']}', style: Theme.of(context).textTheme.titleMedium),
        for (final set in (exercise['sets'] as List? ?? []))
          Text('${set['reps']} reps · ${set['weight']} ${set['unit']}'),
      ],
      if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
      if (published) const Text('Publication publique effectuée.'),
      FilledButton(onPressed: busy ? null : publish, child: const Text('Publier publiquement')),
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Garder privée / Retour au feed')),
    ]))),
  );
}
