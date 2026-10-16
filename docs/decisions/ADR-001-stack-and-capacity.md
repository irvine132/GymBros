# ADR-001 — Stack cible et capacité du poste

Statut : proposé, **non implémenté**. Date : 2026-10-16. Source : spécification v1.0 §7, audit du worktree `dev/slice-a` (dépôt vide).

## Décision

Conserver Flutter Android/iOS (feature-first, état local et tests widget), Java 21 / Spring Boot 3 monolithe modulaire et PostgreSQL / Flyway comme **cible**, sans substitution web ou backend de circonstance. Choisir gestion d'état Flutter légère (`ChangeNotifier` ou Riverpod seulement si dépendance justifiée) lors de l'implémentation ; API REST `/api/v1` ; migrations additives ; aucun service cloud ni coût. Les contrats publics ne doivent pas supposer un fournisseur d'identité tiers. Pour Slice A, session serveur révocable et mot de passe haché avec bibliothèque éprouvée ; le mécanisme détaillé et son modèle de menace doivent être revus indépendamment avant exposition.

## Audit et alternatives

- L'archive Flutter 3.47.7 déjà présente en `/dev/shm/flutter_3.47.7.tar.xz` est lisible par `tar -tf` et le lanceur rapporte une version, mais `flutter doctor -v` refuse l'installation incomplète : `packages/flutter_tools` absent. Une partie du SDK occupe ~2,5 Go en mémoire partagée et l'archive ~1,5 Go. L'extraction/re-téléchargement complet en RAM a précédé un arrêt signal 9 (cause non établie). Aucun second essai en RAM sans capacité démontrée et accord opérationnel.
- `/` ne dispose que de ~1,9 Go, `/dev/shm` ~2,0 Go, RAM disponible ~2,2 Go, swap 4 Go déjà utilisé, Java/Gradle/Maven et `psql` introuvables dans le PATH ; Docker API refuse l'accès. Aucun build Flutter/Java/PostgreSQL vérifiable ici en l'état. Le CLI Dart seul ne valide pas un client Flutter.
- Une page web ou un backend Python/SQLite serait localement plus simple mais **ne livrerait pas** la stack mobile/backend retenue ni les tests et migrations demandés ; cette alternative est rejetée pour cette tranche, sauf décision produit explicite ultérieure. Un téléchargement/extraction SDK aveugle consommerait mémoire et disque sans garantie ; rejeté.

## Conséquences et reprise

Préparer cadrage/backlog sans prétendre à une Slice A fonctionnelle. Lever le blocage avec un environnement local/build isolé disposant d'un Flutter SDK complet et vérifié par `flutter doctor -v`, Java 21, outil de build et PostgreSQL (ou Docker accessible), plus marge de disque/RAM pour caches/tests. **Aucun nettoyage global ou suppression d'artefacts préexistants n'est autorisé implicitement** ; la reprise peut exploiter les artefacts partiels après vérification de leur intégrité et de la capacité, ou un runner disposant déjà de la stack. Une fois prêt : implémenter/tester parcours à deux comptes et IDOR, commit sur `dev/slice-a`, push seulement sur cette branche explicitement autorisée, vérifier SHA distant, puis revue indépendante auth/autorisations sur SHA exact. Main/merge/production restent interdits.
