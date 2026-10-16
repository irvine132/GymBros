# GymBros / Forge — état de la tranche A

Le dépôt canonique part d'un commit vide. Ce worktree isolé `dev/slice-a` contient **le cadrage seulement** : copie de la spécification, architecture, deux ADR et backlog documentaire. Il ne contient pas encore d'application utilisable, d'API, de migration, de test ni de CI. Ne pas interpréter ces documents comme une livraison fonctionnelle ou une autorisation de déploiement.

- Spécification : `PRODUCT_SPEC_AGENT.md`
- Architecture, scope et parcours de validation : `docs/architecture.md`
- Arbitrages techniques et contraintes d'environnement : `docs/decisions/`
- Inventaire complémentaire des outils mutualisables et limites : `docs/shared-tools-audit.md`
- Tentative contrôlée de préparation locale, contrôles d'intégrité et obstacle d'approbation : `docs/local-tool-preparation.md`
- Backlog MVP et suite : `docs/backlog/README.md`

## Vérifications réalisées ici

`git status --short --branch` et `git rev-parse HEAD` ont confirmé le worktree `dev/slice-a` issu du commit initial `d76c1702b1c38ef11468d63680b956d8789fa8cb`. Les deux exemplaires de la spécification ont le même SHA-256 (`35e759bcd4175a9c01911a2468c87d9d56863ad4dcc1a54fbf548473bc302d48`). L'archive Flutter existante est conforme au SHA-256 de la liste officielle et passe `xz -t`, mais **`flutter doctor -v` échoue** car le répertoire `packages/flutter_tools` manque. JDK 17 et Android SDK sont accessibles en lecture seule ; pas de Java 21/Gradle/Maven/PostgreSQL local identifié et Docker API refuse la connexion. Au dernier contrôle, disque racine libre ~3,7 Go, `/dev/shm` ~2,0 Go, swap saturé. Les tentatives d'extraction bornée, y compris vers le répertoire Gym Bro, ont été refusées avant exécution par la politique du terminal headless ; voir `docs/local-tool-preparation.md`. Aucun test produit ou lancement local ne peut être déclaré réussi.

## Plan de reprise (non exécuté)

Après disponibilité d'un environnement sain : implémenter client Flutter et API/DB Slice A selon `docs/architecture.md` et lots A du backlog ; écrire les tests ciblés RED/GREEN ; exécuter réellement `flutter doctor`, les tests widget, les migrations, les tests serveur et le flux E2E à deux comptes avec refus IDOR/privé ; fournir les commandes exactes vérifiées, CI et preuves. Puis auto-revoir, commit sur cette branche, push uniquement `dev/slice-a` si l'implémentation est démontrée, vérifier le SHA distant et demander revue indépendante auth/autorisations sur SHA exact. Aucun merge ou déploiement sans nouveau Go humain.
