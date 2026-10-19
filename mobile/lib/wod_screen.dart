import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'main.dart';

class WodScreen extends StatefulWidget {
  final Api api;
  final DraftStore store;
  final String userId;
  const WodScreen({super.key, required this.api, required this.store, required this.userId});
  @override State<WodScreen> createState() => _WodScreenState();
}

class _WodScreenState extends State<WodScreen> {
  final title = TextEditingController(), movements = TextEditingController(), cap = TextEditingController(text: '12');
  final rounds = TextEditingController(), reps = TextEditingController(), time = TextEditingController();
  String clientId = const Uuid().v4(), format = 'AMRAP';
  bool scaled = false, busy = false;
  String? error;
  Future<void> pendingSave = Future.value();

  @override void initState() {
    super.initState();
    final saved = widget.store.readWod(widget.userId);
    if (saved != null) {
      clientId = '${saved['clientId']}'; title.text = '${saved['title'] ?? ''}';
      format = '${saved['format'] ?? 'AMRAP'}';
      cap.text = '${(saved['timeCapSeconds'] as num? ?? 720) / 60}'.replaceAll(RegExp(r'\.0$'), '');
      movements.text = (saved['movements'] as List? ?? []).join('\n');
      final result = saved['result'] as Map? ?? {};
      rounds.text = '${result['rounds'] ?? ''}'; reps.text = '${result['reps'] ?? ''}';
      time.text = '${result['timeSeconds'] ?? ''}'; scaled = result['scaled'] == true;
    }
  }
  Map<String,dynamic> get snapshot => {
    'clientId': clientId, 'title': title.text, 'format': format,
    'timeCapSeconds': (num.tryParse(cap.text.replaceAll(',', '.')) ?? 0) * 60,
    'movements': movements.text.split('\n').map((m) => m.trim()).where((m) => m.isNotEmpty).toList(),
    'result': {'rounds': rounds.text, 'reps': reps.text, 'timeSeconds': time.text, 'scaled': scaled},
  };
  Future<void> save() async {
    final data = snapshot;
    try {
      pendingSave = pendingSave.catchError((Object _) {}).then((_) => widget.store.saveWod(widget.userId, data));
      await pendingSave;
    } catch (_) { if (mounted) setState(() => error = 'Brouillon non enregistré. Vérifiez l’espace puis réessayez.'); }
  }
  Future<void> finish() async {
    setState(() { busy = true; error = null; });
    try {
      await save();
      if (error != null) return;
      final capMinutes = num.tryParse(cap.text.replaceAll(',', '.'));
      final seconds = capMinutes == null ? null : capMinutes * 60;
      final moves = movements.text.split('\n').map((m) => m.trim()).where((m) => m.isNotEmpty).toList();
      final r = int.tryParse(rounds.text), n = int.tryParse(reps.text), t = int.tryParse(time.text);
      if (title.text.trim().isEmpty || title.text.trim().length > 100 || moves.isEmpty || moves.length > 20 ||
          moves.any((m) => m.length > 80) || seconds == null || seconds < 60 || seconds > 7200 || seconds != seconds.roundToDouble()) {
        throw const FormatException('Titre, mouvements (un par ligne, 80 caractères max) et time cap de 1 à 120 minutes requis.');
      }
      if (format == 'FOR_TIME' ? t == null || t < 1 || t > seconds || rounds.text.isNotEmpty || reps.text.isNotEmpty :
          r == null || r < 0 || r > 1000 || n == null || n < 0 || n > 1000 || (r == 0 && n == 0) || time.text.isNotEmpty) {
        throw const FormatException('Score invalide : tours et reps (AMRAP/EMOM) ou temps en secondes inférieur au time cap (For Time).');
      }
      final body = {'clientId': clientId, 'title': title.text.trim(), 'format': format,
        'timeCapSeconds': seconds.toInt(), 'movements': moves,
        'result': format == 'FOR_TIME' ? {'timeSeconds': t, 'scaled': scaled} : {'rounds': r, 'reps': n, 'scaled': scaled}};
      final session = await widget.api.call('POST', '/wods', body) as Map;
      if (session['status'] == 'DRAFT') await widget.api.call('PUT', '/wods/${session['id']}', body);
      final done = await widget.api.call('POST', '/sessions/${session['id']}/complete') as Map;
      await widget.store.clearWod(widget.userId);
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => CompletedScreen(api: widget.api, session: done)));
      if (mounted) Navigator.pop(context);
    } on FormatException catch (e) { if (mounted) setState(() => error = e.message); }
      catch (_) { if (mounted) setState(() => error = 'WOD non terminé. Vérifiez votre connexion et réessayez ; le brouillon est conservé.'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override void dispose() {
    for (final controller in [title, movements, cap, rounds, reps, time]) { controller.dispose(); }
    super.dispose();
  }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('WOD CrossFit')),
    body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 500), child: ListView(
      padding: const EdgeInsets.all(20), children: [
        Text('Ton WOD. Ton rythme.', style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 8), const Text('Brouillon privé sur cet appareil. Un mouvement par ligne ; choisis ton format puis note ton résultat.'),
        const SizedBox(height: 18), TextField(key: const Key('wod-title'), controller: title, maxLength: 100,
          onChanged: (_) => save(), decoration: const InputDecoration(labelText: 'Nom du WOD')),
        DropdownButtonFormField<String>(initialValue: format, isExpanded: true, decoration: const InputDecoration(labelText: 'Format'),
          items: const [DropdownMenuItem(value: 'AMRAP', child: Text('AMRAP · maximum de tours')),
            DropdownMenuItem(value: 'EMOM', child: Text('EMOM · chaque minute')),
            DropdownMenuItem(value: 'FOR_TIME', child: Text('For Time · contre la montre'))],
          onChanged: (value) { setState(() { format = value!; rounds.clear(); reps.clear(); time.clear(); }); save(); }),
        const SizedBox(height: 14), TextField(key: const Key('wod-movements'), controller: movements,
          minLines: 2, maxLines: 6, onChanged: (_) => save(), decoration: const InputDecoration(labelText: 'Mouvements · un par ligne')),
        const SizedBox(height: 14), TextField(controller: cap, keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => save(), decoration: const InputDecoration(labelText: 'Time cap (minutes)')),
        const SizedBox(height: 14), if (format == 'FOR_TIME') TextField(key: const Key('wod-time'), controller: time,
          keyboardType: TextInputType.number, onChanged: (_) => save(), decoration: const InputDecoration(labelText: 'Temps réalisé (secondes)'))
        else Row(children: [Expanded(child: TextField(key: const Key('wod-rounds'), controller: rounds,
          keyboardType: TextInputType.number, onChanged: (_) => save(), decoration: const InputDecoration(labelText: 'Tours'))),
          const SizedBox(width: 12), Expanded(child: TextField(key: const Key('wod-reps'), controller: reps,
          keyboardType: TextInputType.number, onChanged: (_) => save(), decoration: const InputDecoration(labelText: 'Reps en plus')))]),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Scaled · mouvement adapté'), value: scaled,
          onChanged: (value) { setState(() => scaled = value); save(); }),
        if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
        TextButton(onPressed: busy ? null : () async { await save(); if (context.mounted && error == null) Navigator.pop(context); },
          child: const Text('Quitter et reprendre plus tard')),
        FilledButton(onPressed: busy ? null : finish, child: const Text('Terminer en privé')),
      ],
    ))),
  );
}
