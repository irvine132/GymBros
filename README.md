# GymBros / Forge — état de la tranche A

Le dépôt canonique part d'un commit vide. Ce worktree isolé `dev/slice-a` contient **le cadrage seulement** : copie de la spécification, architecture, deux ADR et backlog documentaire. Il ne contient pas encore d'application utilisable, d'API, de migration, de test ni de CI. Ne pas interpréter ces documents comme une livraison fonctionnelle ou une autorisation de déploiement.

- Spécification : `PRODUCT_SPEC_AGENT.md`
- Architecture, scope et parcours de validation : `docs/architecture.md`
- Arbitrages techniques et contraintes d'environnement : `docs/decisions/`
- Backlog MVP et suite : `docs/backlog/README.md`

## Vérifications réalisées ici

`git status --short --branch` et `git rev-parse HEAD` ont confirmé le worktree `dev/slice-a` issu du commit initial `d76c1702b1c38ef11468d63680b956d8789fa8cb`. Les deux exemplaires de la spécification ont le même SHA-256 (`35e759bcd4175a9c01911a2468c87d9d56863ad4dcc1a54fbf548473bc302d48`). `tar -tf` a pu lire l'archive Flutter existante et `flutter --version` a rapporté Flutter 3.47.7 / Dart 3.13.5 ; **`flutter doctor -v` échoue** car le répertoire `packages/flutter_tools` manque. Pas de Java/Gradle/Maven/psql détecté et Docker API refuse la connexion. Disque racine libre ~1,9 Go, swap saturé ; ne pas relancer une extraction complète Flutter en RAM. Aucun test produit ou lancement local ne peut être déclaré réussi. Voir ADR-001 pour les prérequis de reprise.

## Plan de reprise (non exécuté)

Après disponibilité d'un environnement sain : implémenter client Flutter et API/DB Slice A selon `docs/architecture.md` et lots A du backlog ; écrire les tests ciblés RED/GREEN ; exécuter réellement `flutter doctor`, les tests widget, les migrations, les tests serveur et le flux E2E à deux comptes avec refus IDOR/privé ; fournir les commandes exactes vérifiées, CI et preuves. Puis auto-revoir, commit sur cette branche, push uniquement `dev/slice-a` si l'implémentation est démontrée, vérifier le SHA distant et demander revue indépendante auth/autorisations sur SHA exact. Aucun merge ou déploiement sans nouveau Go humain.
