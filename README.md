# Gym Bro — Slice A (branche `dev/slice-a`)

Client Flutter mobile Android/iOS dans `mobile/` ; le build web est une **preview du même client**, pas un remplacement du mobile. API Spring Boot 3 / Java 21 dans `server/`, PostgreSQL 17 local et migrations Flyway additives. Cette tranche prototype permet inscription/connexion/déconnexion, feed public en landing, brouillon local de séance musculation (un exercice, plusieurs séries, reps, charge kg/lb), fin privée, publication publique facultative, historique privé, détail, blocage et signalement côté API. Rien n'est déployé. Ne pas exposer publiquement ce prototype.

## Démarrage local vérifié (environnement Gym Bro préparé)

Dans le worktree, terminal 1 :

    source /srv/hermes-dev/toolchains/gym-bro/env.sh
    source /srv/hermes-dev/toolchains/gym-bro/db-env.sh
    cd server && mvn spring-boot:run

Ces scripts sont hors Git et chargent les variables DB sans les afficher ; utiliser une base locale dédiée avec `GYM_BRO_DB_HOST/PORT/NAME/USER/PASSWORD` sur un autre poste. API `http://127.0.0.1:18081/api/v1`. Flyway applique V1 puis V2 (aucune suppression de table). Ne pas utiliser une DB de production.

Terminal 2, deux comptes démo jetables, identifiants générés localement et non imprimés :

    python3 scripts/demo_seed.py

Lire les credentials dans `.local/demo-accounts.json` (mode 0600, gitignored) depuis votre éditeur local. Le script rejoue réellement inscription, fin privée, refus IDOR, publication et feed à deux comptes. Ne pas réutiliser les comptes dans une autre base.

Terminal 3, preview du build Flutter vérifiée (après `flutter build web` ci-dessous) :

    source /srv/hermes-dev/toolchains/gym-bro/env.sh
    cd mobile
    flutter build web --release --dart-define=API_BASE=http://127.0.0.1:18081/api/v1
    python3 -m http.server 18082 --bind 127.0.0.1 --directory build/web

Preview web locale : `http://127.0.0.1:18082/`. Pour un émulateur Android **après** installation SDK 36/licences/build tools et vérification du build : utiliser `--dart-define=API_BASE=http://10.0.2.2:18081/api/v1` avec bind API approprié limité au réseau de l'émulateur ; le binaire Android n'a **pas** été validé ici. Le manifest debug autorise HTTP pour test local, pas release. iOS exige macOS/Xcode et HTTPS pour distribution. Pas d'URL de production/config sensible dans Git.

## Vérifications réellement exercées

    source /srv/hermes-dev/toolchains/gym-bro/env.sh
    source /srv/hermes-dev/toolchains/gym-bro/db-env.sh
    cd server && mvn verify
    cd ../mobile && flutter analyze && flutter test
    flutter build web --release --dart-define=API_BASE=http://127.0.0.1:18081/api/v1

Voir `docs/verification.md` (commandes, résultats et limites) et `docs/api.md` (contrat actuel). `PRODUCT_SPEC_AGENT.md` est la copie intégrale de la spec. Architecture et ADR dans `docs/`, backlog détaillé documentaire uniquement dans `docs/backlog/`. Ancien diagnostic d'environnement désormais résolu dans `docs/shared-tools-audit.md` et `docs/local-tool-preparation.md` ; le statut actuel est dans l'ADR-001.

## Hors Slice A / avant bêta

Aucun follow ou feed Abonnements, audience abonnés/privée de post, copie/template, CrossFit/Hyrox, catalogue d'exercices, clubs, paiement, marketplace, IA. Restent MVP : récupération de compte, profil/paramètres privés, follow, pagination par curseur, robustesse offline/outbox/conflits, stockage local chiffré, modération admin, retrait des posts, export/suppression/rétention, rate limits, logs/observabilité, conformité, tests Android/iOS et revue sécurité indépendante. La CI du dépôt est proposée dans `.github/workflows/slice-a.yml` ; son résultat distant doit être vérifié après push. Aucun merge, main push, déploiement ou publication store sans Go humain.
