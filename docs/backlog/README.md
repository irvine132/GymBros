# Backlog documentaire — Forge

Source de vérité : `PRODUCT_SPEC_AGENT.md` v1.0 ; architecture et décisions dans `docs/`. **Aucune carte ci-dessous n'est une carte Kanban exécutable** : c'est le plan produit, et seule Slice A est autorisée à être développée sur la carte actuelle. Chaque ligne est un lot S (~0,5–1 j) ou M (~1–2 j) ; si un lot excède 2 jours, le re-découper avant travail. Critère de fini commun : code/document ciblé, contrôle serveur de droits, migration additive si schéma, tests mentionnés verts, commande de reproduction, doc/contrat API actualisé, auto-revue et aucun secret. `A` = Slice A actuelle, `B–E` = suite MVP non démarrée, `P1/P2` = post-MVP sans Go. Dépendances `—` = aucune.

Format des acceptations : Given (état initial), When (action), Then (résultat vérifiable). `API` = serveur REST et migration ; `UI` = Flutter ; `IT` = intégration backend ; `WT` = widget ; `E2E` = parcours réel local. Les tests ne sont pas présumés exécutés.

## EPIC 00 — Socle (P0)

| ID / lot | Valeur et livrable | Dép. | Priorité / taille / slice | Given → When → Then ; tests | Modules pressentis |
|---|---|---|---|---|---|
| BOOT-01 Audit/ADR | Choix fondés, spec archivée, risques | — | P0 S A | Dépôt vide → inspecter outils/contraintes → état et ADR vérifiables ; revue documentaire | docs |
| BOOT-02 Structure | Démarrage mobile/API reproductible et config exemple sans secret | BOOT-01 | P0 M A | Checkout propre avec SDK → lancer apps → écran/feed et API saine ; smoke local | mobile, server, README |
| BOOT-03 CI minimale | Échec détecté avant publication | BOOT-02 | P0 M A | Commit fautif → pipeline → test/lint échouent ; CI smoke | .github/workflows |
| BOOT-04 DB | Schéma versionné, seed deux comptes uniquement en dev | BOOT-02 | P0 M A | Base vierge → migration+seed local → deux comptes et redémarrage sans duplication ; IT | server/platform, db |
| BOOT-05 Diagnostic | Erreurs traçables sans secret | BOOT-02 | P0 S E | Erreur API → logs structurés → corrélation sans jeton/email ; IT | server/platform |

## EPIC 01 — Identity et profils (P0)

| ID / lot | Valeur et livrable | Dép. | Priorité / taille / slice | Given → When → Then ; tests | Modules |
|---|---|---|---|---|---|
| ID-01a Inscription | Compte autonome, pseudo/email uniques, mot de passe haché | BOOT-04 | P0 M A | Email/pseudo valides → s'inscrire → identité persistée ; doublon/invalide refusé ; IT/WT | server/identity, mobile/auth |
| ID-01b Connexion | Session révocable, déconnexion locale/serveur | ID-01a | P0 M A | Compte créé → login/logout puis API privée → accès refusé après logout ; IT/WT | server/identity, mobile/auth |
| ID-01c Récupération | Réinitialisation sans fuite de compte | ID-01b | P0 M E | Compte connu/inconnu → demander lien puis valider jeton expirant → réponses indistinctes et ancien secret révoqué ; IT | server/identity, mobile/auth |
| ID-02 Profil | Identité publique et unités/locale | ID-01a | P0 S E | Connecté → éditer pseudo, unités, disciplines → validations et unicité ; IT/WT | server/identity, mobile/profile |
| ID-03 Privacité compte | Compte privé et demandes contrôlées | ID-02, SOC-01a | P0 M B | Compte privé → inconnu sollicite follow → contenu masqué jusqu'à acceptation ; IT | server/identity, social |
| ID-04 Blocage | Plus d'exposition croisée | ID-01b, SOC-02 | P0 S A | A bloque B → B ouvre ID du post/feed → non visible ; IT/WT | server/safety, mobile/profile |
| ID-05a Export | Portabilité sans tierces données | ID-01b, TR-06 | P0 M E | A demande export → archive produite → seules données A ; IT | server/identity, training |
| ID-05b Suppression | Données effacées/anonymisées selon rétention | ID-05a | P0 M E | A confirme suppression → endpoints/session → plus d'accès ni fuite de post ; IT migration/rétention | server/identity, publishing |

## EPIC 02 — Catalogue et séances (P0)

| ID / lot | Valeur et livrable | Dép. | Priorité / taille / slice | Given → When → Then ; tests | Modules |
|---|---|---|---|---|---|
| TR-01 Catalogue | Noms stables et catégorisés | BOOT-04 | P0 S A | Seed → lister exercices → noms et unités disponibles, noms sauvegardés en snapshot ; IT | server/training, mobile/train |
| TR-02 Draft STRENGTH | Séries/reps/charge/unité validées, owner unique | ID-01b, TR-01 | P0 M A | A crée/édite draft → B lit/édite par ID → 404, aucune mutation ; IT IDOR | server/training |
| TR-03 Reprise mobile | Saisie rapide et stockage local atomique | TR-02 | P0 M A | Saisie en cours → fermer/revenir → même brouillon sans perte ; WT/intégration locale | mobile/train |
| TR-06 Fin/historique | Session complétée immuable et privée | TR-03 | P0 M A | A complète deux fois même ID client → une session, visible uniquement à A ; IT/E2E | server/training, mobile/history |
| TR-07a Outbox | Retries offline multi-commandes sans doublon | TR-06 | P0 M D | Réseau perdu → enqueue/reconnect → opération appliquée une fois ; tests reconnexion | mobile/sync, server/training |
| TR-07b Conflits | Résolution explicite entre appareils | TR-07a | P0 M D | Deux éditions concurrentes → sync → conflit présenté, ni écrasement silencieux ; IT/WT | mobile/sync, server/training |
| TR-04 WOD | AMRAP/EMOM/For Time versionné | TR-06 | P0 M D | WOD saisi → terminer → résumé/temps cohérents ; IT/WT | server/training, mobile/train |
| TR-05 Hybride | Segments run/station et distances/temps | TR-06 | P0 M D | Segments saisis → terminer → ordre et unités conservés ; IT/WT | server/training, mobile/train |

## EPIC 03 — Templates et copie (P0, Slice C)

| ID / lot | Valeur et livrable | Dép. | Priorité / taille / slice | Given → When → Then ; tests | Modules |
|---|---|---|---|---|---|
| TMP-01 Template | CRUD versionné pour soi | TR-06 | P0 M C | A crée/édite modèle → version précédente → inchangée ; IT | server/training, mobile/train |
| TMP-02 Exécuter | Démarrage depuis snapshot | TMP-01 | P0 S C | Template existant → démarrer → brouillon indépendant ; IT/WT | server/training, mobile/train |
| TMP-03 Copier | Attribution, pas d'accès à l'original privé | TMP-01, SOC-04 | P0 M C | B copie post autorisé → édite copie → séance A inchangée ; refus post masqué ; IT/E2E | server/training, publishing |
| TMP-04 Adapter | Charge et séries personnelles | TMP-03 | P0 S C | Copie → ajuster poids/reps → propre résultat différent, provenance conservée ; WT/IT | mobile/train, server/training |

## EPIC 04 — Publication/social (P0)

| ID / lot | Valeur et livrable | Dép. | Priorité / taille / slice | Given → When → Then ; tests | Modules |
|---|---|---|---|---|---|
| SOC-02 Publication | Opt-in séparé, projection publique non sensible, idempotence | TR-06 | P0 M A | Séance finie privée → choisir publier + retry → un seul post, historique intact ; IT/WT | server/publishing, mobile/publish |
| SOC-03a Feed public | Landing zéro follow, ordre et pagination simple | SOC-02, ID-04 | P0 M A | A publie → B ouvre feed → post public visible, aucun post privé/bloqué ; IT/WT | server/publishing, mobile/feed |
| SOC-04 Détail | Lecture autorisée, résumé sportif expurgé | SOC-03a | P0 S A | B ouvre carte → détail → pas de localisation/horaire de début/email ; ID inconnu/privé 404 ; IT/WT | server/publishing, mobile/feed |
| SOC-01a Follow public | Suivre/ne plus suivre | ID-02, ID-04 | P0 M B | B suit A puis quitte → contenu autorisé apparaît/disparaît du fil suivi ; IT/WT | server/social, mobile/profile |
| SOC-01b Demandes | Acceptation/refus sur comptes privés | SOC-01a, ID-03 | P0 M B | Profil privé → demande puis refus → aucune exposition ; IT | server/social, mobile/profile |
| SOC-03b Feed suivi | Chronologique inverse et curseur sans fuite | SOC-01a, SOC-01b | P0 M B | Plusieurs pages → défiler → pas de doublon, privé filtré avant page ; IT/E2E | server/publishing, mobile/feed |
| SOC-05a Likes | Like/unlike idempotent | SOC-04, ID-04 | P0 S E | B double-tape puis retry → un like ; blocage → refus ; IT/WT | server/publishing, mobile/feed |
| SOC-05b Commentaires | Texte borné, autorisations | SOC-05a | P0 M E | B commente post visible → commentaire unique, post masqué refusé ; IT/WT | server/publishing, mobile/feed |
| SOC-06 Retrait | Masquer post sans supprimer séance | SOC-02 | P0 S E | A retire post → B ne le lit plus, A garde historique ; IT/WT | server/publishing, mobile/history |

## EPIC 05 — Découverte (P0, Slice E)

| ID / lot | Valeur et livrable | Dép. | Priorité / taille / slice | Given → When → Then ; tests | Modules |
|---|---|---|---|---|---|
| DIS-01 Recherche profils | Trouver pseudo public sans exposer email | ID-02, ID-04 | P0 M E | Requête → chercher → profils publics visibles uniquement ; IT/WT | server/discovery, mobile/explore |
| DIS-02 Découvrir | Public opt-in paginé sans ranking | SOC-03a | P0 M E | Feed disponible → défiler → page stable, bloqués absents ; IT/WT | server/discovery, mobile/feed |
| DIS-03 États UI | Chargement/vide/erreur et suggestions | DIS-01, DIS-02 | P0 S E | Réponse vide ou erreur → ouvrir → état explicite et retry ; WT | mobile/feed, explore |

## EPIC 06 — Sécurité et bêta (P0)

| ID / lot | Valeur et livrable | Dép. | Priorité / taille / slice | Given → When → Then ; tests | Modules |
|---|---|---|---|---|---|
| SAFE-01 Signalement | Remontée de contenu visible anti-doublon | SOC-04, ID-04 | P0 S A | B voit post → signale deux fois → un signalement, aucun accès admin public ; IT/WT | server/safety, mobile/feed |
| SAFE-02 Modération | Revue/audit à accès restreint | SAFE-01 | P0 M E | Modérateur habilité → traite signalement → action tracée ; utilisateur normal refusé ; IT | server/safety |
| QA-01 Parcours | Test social→copie→train→publication | TMP-04, SOC-03b | P0 M C | Deux comptes prêts → B copie puis publie → A original préservé ; E2E | mobile, server |
| QA-02 Privacy/offline | Matrice IDOR, blocage et sync | TR-07b, ID-04 | P0 M D | A/B, offline et retry → endpoints et local → aucune fuite/doublon ; IT/E2E | mobile, server |
| QA-03 Mesures | Événements agrégés anonymes | BOOT-05 | P0 S E | Entraînement terminé → mesurer → pas de charges/PII dans logs ; IT | server/platform, mobile |
| QA-04 Bêta | Checklist stores/juridique, consentement, rate limits | SAFE-02, ID-05b, ID-01c, QA-02 | P0 M E | Checklist ouverte → audit → blocants corrigés avant pilote ; revue manuelle | docs, server/platform |

## EPIC 07 — Post-MVP (hors Go, aucune implémentation)

| ID / lot | Valeur et livrable | Dép. | Priorité / taille / slice | Given → When → Then ; tests | Modules |
|---|---|---|---|---|---|
| P1-01 Notifications | Retour d'engagement opt-in | QA-04 | P1 M P1 | Opt-in → événement → notification seulement autorisée ; intégration | mobile, server |
| P1-02 Photos | Média facultatif modéré | SAFE-02 | P1 M P1 | Upload valide → contrôle → aucun accès privé ; intégration sécurité | publishing, mobile |
| P1-03 Clubs | Groupe sans fuite d'audience | QA-04 | P1 M P1 | Groupe privé → étranger lit ID → refus ; IT | server/clubs, mobile |
| P1-04 Défis | Règles sportives explicites | P1-03 | P1 M P1 | Participant éligible → résultat → classement cohérent ; IT | server/clubs, mobile |
| P1-05 Programmes | Cycles créateur versionnés | TMP-01 | P1 M P1 | Créateur révise → participant existant → snapshot conservé ; IT | server/programs, mobile |
| P1-06 Liens externes | Partage sans PII | SOC-04 | P1 S P1 | Lien partagé → étranger → seul post public ; IT | publishing, mobile |
| P2-01 Communauté | Rejoindre cycle | P1-05 | P2 M P2 | Membre rejoint → reçoit version assignée ; IT | programs |
| P2-02 Coach | Outils créateur avec permissions | P2-01 | P2 M P2 | Non-coach → édition → refus ; IT | identity, programs |
| P2-03 Paiement | Transaction sécurisée hors périmètre | P2-02 | P2 M P2 | Abonnement → paiement → accès selon état authentique ; sandbox sécurité | billing |
| P2-04 Intégrations | Import consenti et idempotent | QA-04 | P2 M P2 | Import rejoué → une séance, provenance tracée ; IT | integrations |

Les fonctions sportives avancées, licence de marque « Hyrox », politique de modération/suppression et conformité légale nécessitent cadrage et Go dédiés. La prochaine unité après Slice A validée est SOC-01a + ID-03/SOC-01b (Slice B), pas une extension implicite de la carte actuelle.
