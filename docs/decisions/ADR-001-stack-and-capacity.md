# ADR-001 — Stack cible et capacité du poste

Statut : adopté pour la tranche A (2026-10-17). Source : spécification v1.0 §7, audit du worktree `dev/slice-a` (dépôt initial vide).

## Décision

Conserver Flutter Android/iOS comme client produit (web uniquement comme cible de preview/test du **même** code Flutter), Java 21 / Spring Boot 3 et PostgreSQL / Flyway, sans substitution par une maquette web. Slice A utilise un état Flutter local `StatefulWidget`, `shared_preferences` pour brouillon individuel, API REST `/api/v1`, migration additive et aucun service cloud. Le serveur est un monolithe en classes encore compactes, **pas** une modularité complètement extraite. Auth : BCrypt pour les mots de passe ; jeton aléatoire de 256 bits présenté en Bearer, seulement son SHA-256 conservé en DB, expiration sept jours et révocation. Cette auth et les autorisations exigent revue indépendante avant validation du slice, et ne sont pas prêtes pour une exposition publique.

## Audit historique et alternative rejetée

- L'archive Flutter 3.47.7 déjà présente en `/dev/shm/flutter_3.47.7.tar.xz` est lisible par `tar -tf` et le lanceur rapporte une version, mais `flutter doctor -v` refuse l'installation incomplète : `packages/flutter_tools` absent. Une partie du SDK occupe ~2,5 Go en mémoire partagée et l'archive ~1,5 Go. L'extraction/re-téléchargement complet en RAM a précédé un arrêt signal 9 (cause non établie). Aucun second essai en RAM sans capacité démontrée et accord opérationnel.
- `/` ne dispose que de ~1,9 Go, `/dev/shm` ~2,0 Go, RAM disponible ~2,2 Go, swap 4 Go déjà utilisé, Java/Gradle/Maven et `psql` introuvables dans le PATH ; Docker API refuse l'accès. Aucun build Flutter/Java/PostgreSQL vérifiable ici en l'état. Le CLI Dart seul ne valide pas un client Flutter.
- Une page web ou un backend Python/SQLite serait localement plus simple mais **ne livrerait pas** la stack mobile/backend retenue ni les tests et migrations demandés ; cette alternative est rejetée pour cette tranche, sauf décision produit explicite ultérieure. Un téléchargement/extraction SDK aveugle consommerait mémoire et disque sans garantie ; rejeté.

## Environnement désormais disponible et limites

Les lignes d'audit ci-dessus décrivent le blocage **du 16 octobre**, maintenant levé par une préparation locale autorisée séparée : Flutter 3.47.7, Java 21.0.12.1, Maven 3.8.7 et PostgreSQL 17.11 local sur 127.0.0.1:15433. `env.sh` et `db-env.sh` dans `/srv/hermes-dev/toolchains/gym-bro/` fournissent les chemins et variables, sans être versionnés ni affichés. `mvn verify`, `flutter test`, `flutter analyze` et build web ont été exécutés sur Slice A ; voir `docs/verification.md`. Android n'est pas validé : SDK 35 partagé, Flutter attend SDK 36 et BuildTools supplémentaires ; iOS non validé sur Linux. Pas de suppression de données ni de déploiement. Main/merge/production interdits.
