# Vérification Slice A — 17 octobre 2026

Périmètre : worktree `dev/slice-a`, base locale PostgreSQL dédiée `gym_bro` sur 127.0.0.1:15433 ; aucun service cloud, store, main/merge ou migration destructive. Les identifiants démo sont générés aléatoirement et stockés seulement dans `.local/` (gitignored, répertoire 0700, fichiers 0600), jamais dans les preuves.

## Commandes et résultats observés

- RED serveur : `mvn -q test` avant code → échec `Unable to find a @SpringBootConfiguration` (test `SliceAIntegrationTest` déjà créé). Après implémentation, `source /srv/hermes-dev/toolchains/gym-bro/env.sh; source /srv/hermes-dev/toolchains/gym-bro/db-env.sh; cd server; mvn -q verify` → exit 0, 1 test d'intégration PASS ; Flyway V1 appliquée puis V2 additive appliquée sur données existantes, `Successfully validated 2 migrations`. JDK 21.0.12.1, Spring Boot 3.5.7, PostgreSQL 17.11.
- RED Flutter : `flutter test test/slice_a_test.dart` avant changement → `GymApp` et `DraftStore` absents. GREEN : `cd mobile; flutter test` → exit 0, 4 tests PASS (auth shell, reprise isolée, séance privée/publication/détail, signalement/blocage). `flutter analyze` → exit 0, `No issues found`. `flutter build web --release --dart-define=API_BASE=http://127.0.0.1:18081/api/v1` → exit 0, `✓ Built build/web`.
- API réelle, pas mock : `java -jar server/target/gym-bro-api-0.1.0.jar` → démarrage sur port 18081 ; `curl /api/v1/me` sans jeton → 401. `python3 scripts/demo_seed.py` → PASS inscription A/B, refus lecture session A par B (404), fin privée, publication, détail B, anti-doublon ; après V2, `GYM_BRO_DEMO_FILENAME=demo-accounts-v2.json python3 scripts/demo_seed.py` → PASS sur serveur relancé. `curl http://127.0.0.1:18082/` → 200 ; CORS preflight depuis cette origine → 200 avec `Access-Control-Allow-Origin` exact.
- Navigateur réel sur le build Flutter web : feed du compte B authentifié affiche les publications A ; ouvrir le détail affiche le résumé et boutons Signaler/Bloquer. Capture du feed `gym-bro-slice-a-feed.png` SHA-256 `cd9327770df73d587e682920902949973ef10a5d582de7707676425b1fa6d4e9`, détail `gym-bro-slice-a-detail.png` SHA-256 `181850a06fa6827e7146bdfa2f8dc2ef88346a084bf70aac620c19d5ac9e0b5d`, login `gym-bro-slice-a-login.png` SHA-256 `320babace735c6ecb92402c98da1e50ead33725173c9306f7b8e883281a74eba`. Images hors Git, jointes au handoff. Déconnexion navigateur vérifiée : clés `flutter.token`/`flutter.userId` absentes. Onglet navigateur de test fermé ; preview locale/API conservées pour consultation.
- CI GitHub Actions run [39017986279](https://github.com/irvine132/GymBros/actions/runs/39017986279) sur SHA `b2a26934ef3c2d6fe263beed578edd19d622c9a8` : `completed/success` (jobs `server` et `mobile`), obtenu de l'API GitHub publique après le push autorisé. Ce SHA de code est suivi d'une correction **documentaire seulement** pour matérialiser les 53 IDs de backlog ; vérifier séparément la CI du SHA final si elle s'exécute.

## Matrice des critères de la tranche

| Critère | Preuve | État |
|---|---|---|
| Compte/login/logout | IT 2 comptes + widget auth + déconnexion navigateur | PASS local |
| Feed landing/vide et post/détail entre A/B | IT, script seed, widget, captures browser | PASS local |
| Saisie muscu exercice/séries/reps/charge/kg-lb, reprise minimale | widget 2 séries et `DraftStore` rouvert ; validation serveur | PASS limitée à 1 exercice côté UI |
| Fin privée par défaut, publication opt-in distincte, historique conservé | IT avant/après publication ; widget ; contrainte UNIQUE DB | PASS local |
| IDOR/visibilité, champs publics non sensibles, anti-doublon | IT GET/PUT/complete/post refusés, blocage avant feed, snapshot public, retry | PASS sur chemins testés |
| Blocage et signalement | IT + widget, filtrage feed/détail, report idempotent | PASS minimal local |
| Migration, seed, lancement, docs | Flyway V1/V2, scripts et API 18081/web 18082 vérifiés | PASS local |
| Android/iOS et CI distante | SDK Android 35 seulement, iOS non construit ; CI code SHA b2a2693 success, SHA documentaire final à vérifier | MOBILE NON VALIDÉ |

## Limites bloquantes pour bêta/release

Client mobile Flutter réel mais **aucun APK/IPA validé**. Stockage `shared_preferences` non chiffré, session Bearer côté client stockée dans les préférences, brouillon local sans outbox/conflit/garantie d'atomicité forte ; une seule structure exercice UI. Pas de récupération de compte, rate limiting, pagination par curseur, modération admin, retrait/gestion audience de post, export/suppression, conformité ni monitoring. Les tests ne constituent pas un audit sécurité indépendant. La preview est locale (`http://127.0.0.1:18082/`) et ne doit pas être exposée en production. Prochain lot sous nouveau Go : Slice B follow/audience privée/feed suivi, puis C/D/E selon backlog ; ne pas démarrer ici.
