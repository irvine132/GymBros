import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'main.dart';

class HyroxScreen extends StatefulWidget {
  final Api api;
  final DraftStore store;
  final String userId;
  const HyroxScreen({super.key, required this.api, required this.store, required this.userId});
  @override State<HyroxScreen> createState() => _HyroxScreenState();
}

class _Segment {
  String type;
  final name = TextEditingController(), distance = TextEditingController();
  final duration = TextEditingController(), reps = TextEditingController(), weight = TextEditingController();
  String unit = 'kg';
  _Segment(this.type);
  factory _Segment.from(Map item) => _Segment('${item['type']}')
    ..name.text = '${item['name'] ?? ''}'
    ..distance.text = '${item['distanceMeters'] ?? ''}'
    ..duration.text = '${item['durationSeconds'] ?? ''}'
    ..reps.text = '${item['reps'] ?? ''}'
    ..weight.text = '${item['weight'] ?? ''}'
    ..unit = '${item['unit'] ?? 'kg'}';
  Map<String,dynamic> get snapshot => {'type': type, 'name': name.text, 'distanceMeters': distance.text,
    'durationSeconds': duration.text, 'reps': reps.text, 'weight': weight.text, 'unit': unit};
  void dispose() { for (final c in [name, distance, duration, reps, weight]) { c.dispose(); } }
}

class _HyroxScreenState extends State<HyroxScreen> {
  final title = TextEditingController(), total = TextEditingController(), notes = TextEditingController();
  final segments = <_Segment>[];
  String clientId = const Uuid().v4();
  bool busy = false;
  String? error;
  Future<void> pendingSave = Future.value();

  @override void initState() {
    super.initState();
    final saved = widget.store.readHyrox(widget.userId);
    if (saved != null) {
      clientId = '${saved['clientId']}'; title.text = '${saved['title'] ?? ''}';
      total.text = '${saved['totalSeconds'] ?? ''}'; notes.text = '${saved['notes'] ?? ''}';
      for (final item in saved['segments'] as List? ?? []) { segments.add(_Segment.from(item as Map)); }
    }
    if (segments.isEmpty) segments.addAll([_Segment('RUN'), _Segment('STATION')]);
  }
  Future<void> save() async {
    final data = {'clientId': clientId, 'title': title.text, 'totalSeconds': total.text,
      'notes': notes.text, 'segments': segments.map((s) => s.snapshot).toList()};
    try {
      pendingSave = pendingSave.catchError((Object _) {}).then((_) => widget.store.saveHyrox(widget.userId, data));
      await pendingSave;
    } catch (_) { if (mounted) setState(() => error = 'Brouillon non enregistré. Vérifiez l’espace puis réessayez.'); }
  }
  int requireInt(String value, int min, int max, String field) {
    final n = int.tryParse(value);
    if (n == null || n < min || n > max) throw FormatException('$field : valeur de $min à $max requise.');
    return n;
  }
  Map<String,dynamic> validate() {
    if (title.text.trim().isEmpty || title.text.trim().length > 100) throw const FormatException('Nom de séance requis (100 caractères maximum).');
    if (notes.text.length > 1000) throw const FormatException('Notes : 1000 caractères maximum.');
    if (segments.length < 2 || segments.length > 20 || !segments.any((s) => s.type == 'RUN') || !segments.any((s) => s.type == 'STATION')) {
      throw const FormatException('Ajoutez au moins une course et une station (20 segments maximum).');
    }
    final totalSeconds = requireInt(total.text, 1, 86400, 'Temps total (secondes)');
    var sum = 0;
    final result = <Map<String,dynamic>>[];
    for (final s in segments) {
      final duration = requireInt(s.duration.text, 1, 86400, 'Durée du segment (secondes)');
      sum += duration;
      if (s.type == 'RUN') {
        result.add({'type': 'RUN', 'distanceMeters': requireInt(s.distance.text, 1, 50000, 'Distance (m)'), 'durationSeconds': duration});
      } else {
        if (s.name.text.trim().isEmpty || s.name.text.trim().length > 80) throw const FormatException('Nom de station requis (80 caractères maximum).');
        final station = <String,dynamic>{'type': 'STATION', 'name': s.name.text.trim(), 'durationSeconds': duration};
        if (s.reps.text.isNotEmpty) station['reps'] = requireInt(s.reps.text, 1, 10000, 'Répétitions');
        if (s.weight.text.isNotEmpty) {
          final weight = num.tryParse(s.weight.text.replaceAll(',', '.'));
          if (weight == null || weight < 0 || weight > 10000 || (weight * 100).roundToDouble() != weight * 100) {
            throw const FormatException('Charge : de 0 à 10000, deux décimales maximum.');
          }
          station.addAll({'weight': weight, 'unit': s.unit});
        }
        result.add(station);
      }
    }
    if (sum > totalSeconds) throw const FormatException('Le temps total doit inclure toutes les durées des segments.');
    return {'clientId': clientId, 'title': title.text.trim(), 'segments': result,
      'totalSeconds': totalSeconds, 'notes': notes.text};
  }
  Future<void> finish() async {
    setState(() { busy = true; error = null; });
    try {
      await save();
      if (error != null) return;
      final body = validate();
      final session = await widget.api.call('POST', '/hyrox', body) as Map;
      if (session['status'] == 'DRAFT') await widget.api.call('PUT', '/hyrox/${session['id']}', body);
      final done = await widget.api.call('POST', '/sessions/${session['id']}/complete') as Map;
      await widget.store.clearHyrox(widget.userId);
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => CompletedScreen(api: widget.api, session: done)));
      if (mounted) Navigator.pop(context);
    } on FormatException catch (e) { if (mounted) setState(() => error = e.message); }
      catch (_) { if (mounted) setState(() => error = 'Séance non terminée. Vérifiez votre connexion et réessayez ; le brouillon est conservé.'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override void dispose() {
    for (final c in [title, total, notes]) { c.dispose(); }
    for (final s in segments) { s.dispose(); }
    super.dispose();
  }
  Widget segmentFields(_Segment s, int index) => gymCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [Expanded(child: Text('${index + 1}. ${s.type == 'RUN' ? 'Course' : 'Station'}', style: Theme.of(context).textTheme.titleLarge)),
      if (segments.length > 2) IconButton(tooltip: 'Retirer le segment ${index + 1}', icon: const Icon(Icons.close), onPressed: () { setState(() => segments.removeAt(index)); s.dispose(); save(); })]),
    const SizedBox(height: 10),
    if (s.type == 'RUN') TextField(key: Key('hyrox-run-distance-$index'), controller: s.distance, onChanged: (_) => save(),
      keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Distance courue (m)')),
    if (s.type == 'STATION') ...[
      TextField(key: Key('hyrox-station-name-$index'), controller: s.name, maxLength: 80, onChanged: (_) => save(),
        decoration: const InputDecoration(labelText: 'Nom de la station (ex. SkiErg)')),
      TextField(controller: s.reps, onChanged: (_) => save(), keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Répétitions (si pertinentes)')),
      const SizedBox(height: 8), Row(children: [Expanded(child: TextField(controller: s.weight, onChanged: (_) => save(),
        keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Charge (si pertinente)'))),
        const SizedBox(width: 8), DropdownButton<String>(value: s.unit, items: ['kg', 'lb'].map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
          onChanged: (u) { setState(() => s.unit = u!); save(); })]),
    ],
    const SizedBox(height: 10), TextField(key: Key('hyrox-${s.type == 'RUN' ? 'run' : 'station'}-duration-$index'),
      controller: s.duration, onChanged: (_) => save(), keyboardType: TextInputType.number,
      decoration: const InputDecoration(labelText: 'Durée du segment (secondes)')),
  ]));
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Séance Hyrox')),
    body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 500), child: ListView(
      padding: const EdgeInsets.all(20), children: [
        Text('Course et stations.', style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 8), const Text('Ajoute les segments dans l’ordre. Ton brouillon reste privé sur cet appareil ; aucune géolocalisation ni chrono automatique.'),
        const SizedBox(height: 18), TextField(key: const Key('hyrox-title'), controller: title, maxLength: 100,
          onChanged: (_) => save(), decoration: const InputDecoration(labelText: 'Nom de séance')),
        for (var i = 0; i < segments.length; i++) segmentFields(segments[i], i),
        Wrap(spacing: 8, children: [
          OutlinedButton.icon(onPressed: segments.length >= 20 ? null : () { setState(() => segments.add(_Segment('RUN'))); save(); },
            icon: const Icon(Icons.add), label: const Text('Ajouter une course')),
          OutlinedButton.icon(onPressed: segments.length >= 20 ? null : () { setState(() => segments.add(_Segment('STATION'))); save(); },
            icon: const Icon(Icons.add), label: const Text('Ajouter une station')),
        ]),
        const SizedBox(height: 12), TextField(key: const Key('hyrox-total'), controller: total, onChanged: (_) => save(),
          keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Temps total (secondes)')),
        const SizedBox(height: 12), TextField(controller: notes, maxLength: 1000, minLines: 2, maxLines: 4,
          onChanged: (_) => save(), decoration: const InputDecoration(labelText: 'Notes privées (jamais publiées)')),
        if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
        TextButton(onPressed: busy ? null : () async { await save(); if (context.mounted && error == null) Navigator.pop(context); },
          child: const Text('Quitter et reprendre plus tard')),
        FilledButton(onPressed: busy ? null : finish, child: const Text('Terminer en privé')),
      ],
    ))),
  );
}
