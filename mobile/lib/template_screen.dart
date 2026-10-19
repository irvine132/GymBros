import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'main.dart';

class TemplateScreen extends StatefulWidget {
  final Api api;
  final DraftStore store;
  final String userId;
  final Map template;
  const TemplateScreen({super.key, required this.api, required this.store, required this.userId, required this.template});
  @override State<TemplateScreen> createState() => _TemplateScreenState();
}
class _TemplateSet {
  final reps = TextEditingController(), weight = TextEditingController();
  String unit = 'kg';
  _TemplateSet(Map data) {
    reps.text = '${data['reps'] ?? ''}'; weight.text = '${data['weight'] ?? ''}';
    unit = '${data['unit'] ?? 'kg'}';
  }
  void dispose() { reps.dispose(); weight.dispose(); }
}
class _TemplateExercise {
  final name = TextEditingController();
  final sets = <_TemplateSet>[];
  _TemplateExercise(Map data) {
    name.text = '${data['name'] ?? ''}';
    for (final item in (data['sets'] as List? ?? [])) { sets.add(_TemplateSet(item as Map)); }
  }
  void dispose() { name.dispose(); for (final set in sets) { set.dispose(); } }
}
class _TemplateScreenState extends State<TemplateScreen> {
  final title = TextEditingController();
  final exercises = <_TemplateExercise>[];
  final startId = const Uuid().v4();
  bool busy = false;
  String? error;
  @override void initState() {
    super.initState(); title.text = '${widget.template['title']}';
    for (final item in (widget.template['exercises'] as List? ?? [])) { exercises.add(_TemplateExercise(item as Map)); }
  }
  @override void dispose() { title.dispose(); for (final item in exercises) { item.dispose(); } super.dispose(); }
  Map<String,dynamic> checkedDefinition() {
    final name = title.text.trim();
    if (name.isEmpty || name.length > 100 || exercises.isEmpty || exercises.length > 20) {
      throw const FormatException('Titre requis (100 caractères max.) et au moins un exercice.');
    }
    final result = <Map<String,dynamic>>[];
    for (final item in exercises) {
      final exerciseName = item.name.text.trim();
      if (exerciseName.isEmpty || exerciseName.length > 80 || item.sets.isEmpty || item.sets.length > 30) {
        throw const FormatException('Chaque exercice exige un nom (80 caractères max.) et une série.');
      }
      final sets = <Map<String,dynamic>>[];
      for (final set in item.sets) {
        final reps = int.tryParse(set.reps.text.trim()), weight = num.tryParse(set.weight.text.trim().replaceAll(',', '.'));
        if (reps == null || reps < 1 || reps > 1000 || weight == null || weight < 0 || weight > 10000 || (weight * 100).roundToDouble() != weight * 100) {
          throw const FormatException('Série : 1–1000 répétitions et charge 0–10000 (deux décimales max.).');
        }
        sets.add({'reps': reps, 'weight': weight, 'unit': set.unit});
      }
      result.add({'name': exerciseName, 'sets': sets});
    }
    return {'title': name, 'exercises': result};
  }
  Future<bool> saveTemplate() async {
    setState(() { busy = true; error = null; });
    try {
      await widget.api.call('PUT', '/templates/${widget.template['id']}', checkedDefinition());
      return true;
    } on FormatException catch (e) { if (mounted) setState(() => error = e.message); }
      catch (_) { if (mounted) setState(() => error = 'Modèle non enregistré. Réessayez.'); }
    finally { if (mounted) setState(() => busy = false); }
    return false;
  }
  Future<void> start() async {
    if (widget.store.read(widget.userId) != null) {
      setState(() => error = 'Un brouillon est déjà sur cet appareil. Termine-le avant d’en lancer un autre.');
      return;
    }
    if (!await saveTemplate() || !mounted) return;
    setState(() => busy = true);
    try {
      final session = await widget.api.call('POST', '/templates/${widget.template['id']}/sessions', {'clientId': startId}) as Map;
      final workout = session['workout'] as Map;
      final entries = workout['exercises'] as List;
      await widget.store.save(widget.userId, {'clientId': session['clientId'], 'title': session['title'],
        'unit': entries.isNotEmpty && (entries.first['sets'] as List).isNotEmpty ? entries.first['sets'][0]['unit'] : 'kg',
        'exercises': entries});
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => WorkoutScreen(api: widget.api, store: widget.store, userId: widget.userId)));
      if (mounted) Navigator.pop(context);
    } catch (_) { if (mounted) setState(() => error = 'Séance non lancée ou sauvegarde locale impossible. Réessayez ; vérifiez aussi Mes séances.'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Mon modèle de séance')),
    body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 500), child: ListView(padding: const EdgeInsets.all(20), children: [
      Text('À toi de jouer.', style: Theme.of(context).textTheme.headlineLarge),
      const SizedBox(height: 8), const Text('Les valeurs copiées sont des cibles à adapter, pas tes performances. Le modèle et la séance restent privés tant que tu ne publies pas.'),
      if (widget.template['sourceAuthor'] != null) Text('Inspiré de @${widget.template['sourceAuthor']}'),
      if (widget.template['sourceUnavailable'] == true) const Text('Source non disponible'),
      const SizedBox(height: 16), TextField(controller: title, maxLength: 100, decoration: const InputDecoration(labelText: 'Nom de mon modèle')),
      for (var i = 0; i < exercises.length; i++) gymCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Mouvement ${i + 1}', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        TextField(controller: exercises[i].name, maxLength: 80, decoration: const InputDecoration(labelText: 'Exercice')),
        for (var j = 0; j < exercises[i].sets.length; j++) Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Série ${j + 1}'),
          const SizedBox(height: 12),
          Row(children: [Expanded(child: TextField(key: Key('template-reps-$i-$j'), controller: exercises[i].sets[j].reps,
            keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Répétitions'))),
            const SizedBox(width: 8), Expanded(child: TextField(controller: exercises[i].sets[j].weight,
              keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Charge')))]),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(initialValue: exercises[i].sets[j].unit, decoration: const InputDecoration(labelText: 'Unité'),
            items: ['kg','lb'].map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
            onChanged: (value) => setState(() => exercises[i].sets[j].unit = value!)),
          const SizedBox(height: 16),
        ]),
        OutlinedButton.icon(onPressed: exercises[i].sets.length >= 30 ? null : () => setState(() => exercises[i].sets.add(_TemplateSet({'unit':'kg'}))),
          icon: const Icon(Icons.add), label: const Text('Ajouter une série')),
      ])),
      if (exercises.length < 20) OutlinedButton.icon(onPressed: () => setState(() => exercises.add(_TemplateExercise({'name':'', 'sets':[{'unit':'kg'}]}))),
        icon: const Icon(Icons.add), label: const Text('Ajouter un exercice')),
      if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
      OutlinedButton(onPressed: busy ? null : saveTemplate, child: const Text('Enregistrer le modèle')),
      FilledButton(onPressed: busy ? null : start, child: const Text('Démarrer ma séance')),
    ]))),
  );
}
