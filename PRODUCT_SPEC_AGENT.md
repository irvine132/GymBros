# PRODUCT SPEC — Réseau social d'entraînement (nom de travail : Forge)
Version 1.0 — 16 octobre 2026 · Statut : cahier des charges de départ, décisions à confirmer

> **Instruction à l'agent de codage :** traite ce document comme la source de vérité produit initiale. Commence par inspecter le dépôt et ses conventions. Crée un backlog découpé en epics et cartes indépendamment livrables, avec dépendances, critères d'acceptation et tests. Ne déploie pas en production et n'effectue aucune opération destructive sans validation. Les choix signalés « proposition » sont modifiables ; inscris les arbitrages dans un ADR. Priorise une tranche verticale fonctionnelle avant d'étendre le produit.

## 1. Vision et principe directeur
Créer le réseau social de référence des pratiquants de musculation, CrossFit et Hyrox : le « Strava du fitness de force et hybride ». Application **social-first** : l'écran initial est le fil d'activité, pas le carnet d'entraînement. Les amis et gym bros, coachs et créateurs publient leurs séances réelles ; d'autres peuvent réagir, consulter la performance, copier la séance, l'adapter à leur niveau, la réaliser puis partager leur résultat. Les utilisateurs doivent aussi pouvoir utiliser l'application sans réseau social et tout enregistrer en privé.

### Personas
- Athlète régulier : suit ses amis, note ses charges, records et séances, partage sélectivement.
- Pratiquant hybride : combine musculation, WOD, running et entraînements Hyrox ; suit temps et benchmarks.
- Coach/créateur : publie séances et programmes, fédère sa communauté ; monétisation future.
- Groupe d'amis / box / salle : défis et séances communes ; communauté future.

### Boucle de valeur
Découvrir activité → ouvrir détail → sauvegarder/copier le modèle → adapter → exécuter → publier optionnellement → nouvelles interactions. L'application doit produire de la valeur avec zéro abonné (carnet utilisable).

### Positionnement
Strava : réseau multisport très mature ; Hevy : suivi de musculation et composantes sociales déjà développées. Ne jamais supposer que « copier une séance » est inédit. Différenciateurs visés : entraînement hybride natif, programme rejoint par une communauté, défis adaptés au format, lien direct entre contenu social et séance exécutable. Programmes communautaires et marketplace **hors MVP**.

## 2. Principes non négociables
1. Social-first et usage simple en solo ; la publication n'est jamais obligatoire.
2. Private-by-default pour informations sensibles (horaire précis, établissement et localisation) ; visibilité explicite de chaque activité.
3. Une **séance exécutée** est distincte d'un **modèle réutilisable**, d'un **programme** et d'une **publication**.
4. L'original d'une séance copiée n'est jamais modifié ; snapshot/version pour conserver l'historique.
5. Application utilisable en salle sans connexion réseau durant une séance ; synchronisation robuste et anti-doublon.
6. UX rapide : valider une série en un geste, jamais perdre une séance en cours.
7. Concevoir internationalisable : clés de traduction, unités kg/lb et km/mi, fuseaux horaires, données en UTC.
8. Accessibilité mobile, sécurité de base, modération, suppression et export des données dès la bêta.
9. Ne pas réutiliser logos, noms de marque ou contenus tiers sans autorisation ; nom « Forge » provisoire.

## 3. Navigation et 5 écrans
### E1. Accueil / Feed — landing après connexion
- Deux onglets : Abonnements (MVP, chronologique inverse) ; Découvrir (V1 simple, sans ranking algorithmique avancé).
- Carte activité : auteur/avatar, sport et titre, date relative, visibilité, durée, résumé sportif normalisé, record(s), média photo facultatif, likes/commentaires, « Copier/Essayer » si activité réutilisable.
- Taper carte → détail activité, exercices/performances, auteur, interactions ; états vide/chargement/erreur/pagination.
- Respecter privacy et blocages côté API, pas seulement dans le client.
### E2. Explorer
- Recherche de profils par pseudo/nom public ; filtres de discipline (musculation/CrossFit/Hyrox) ; suggestions simples (comptes publics récents ou sélection éditoriale).
- V1.1 : recherche de séances publiques par discipline/format, programmes créateurs et filtres niveau/matériel.
### E3. Train
- Action principale centrale : démarrer une séance vide, démarrer depuis un template, reprendre en cours, ou copier depuis une activité.
- Musculation : exercices, séries (reps/weight, échauffement, repos facultatif) ; CrossFit : format AMRAP/EMOM/For Time, rounds, temps, mouvements ; Hyrox : segments (run/station), distances, durées, charges si pertinentes.
- Sauvegarde locale, possibilité pause/reprise, écran d'édition simple ; fin → résumé → publication optionnelle.
- Gérer au minimum les unités et permettre d'ajuster charges/répétitions avant exécution.
### E4. Clubs
- Structure de navigation prévue ; **pas de vraie fonctionnalité Clubs au premier jalon MVP**. Afficher placeholder explicite ou feature flag.
- Phase suivante : groupes publics/privés, memberships, défis à règles précises, modération, puis salles.
### E5. Profil
- Photo facultative, pseudo unique, bio, disciplines préférées, compte public/privé, abonnements/abonnés, activité publiée et activité privée pour soi.
- Historique des séances distinct du feed ; records personnels simples ; accès aux paramètres de confidentialité, blocages, export et suppression.

## 4. Périmètre MVP et versions
### MVP — indispensable
- Auth email + mot de passe ou méthode du fournisseur existant ; inscription, connexion, déconnexion, récupération de compte.
- Profils et préférences de confidentialité, public/privé ; suivi/désabonnement, demandes d'abonnement si privé, blocage.
- Catalogue initial d'exercices et mouvements de base, catégorisé et extensible.
- Création/exécution/enregistrement des trois types de séances ; durée, effort et structure pertinente par sport.
- Gestion des templates simples (créer, cloner, éditer pour soi) et copie depuis une publication publique autorisée.
- Historique privé, activité terminée ; publication opt-in, visibilité public/abonnés/privé ; fil Abonnements chronologique.
- Likes, commentaires simples ; page activité ; recherche de profils et fil Découvrir simple.
- Stockage local d'une séance en cours et resynchronisation idempotente.
- Signalement de contenus/utilisateurs, blocage, outils minimaux de modération, suppression de compte et gestion des données.
- Journalisation, surveillance des erreurs, tests, CI, migrations, seed de données de démonstration.
### Post-MVP P1 (après validation d'usage)
- Notifications push, photos avec modération, fil Découvrir recommandé, stats avancées, création de programmes multi-semaines.
- Clubs et groupes, défis standards, benchmarks, séances collaboratives, partage externe avec deep links.
### Post-MVP P2
- Programmes communautaires « rejoindre un cycle », coach profiles, marketplace, subscriptions, intégrations montres et imports autorisés, API partenaire, vidéo.
### Explicitement exclu du MVP
- Paiement, microservices, Pulsar/event streaming, classement mondial non vérifié, géolocalisation temps réel, DM, IA coaching, génération algorithmique lourde, streaming vidéo.

## 5. Parcours utilisateurs prioritaires (Gherkin simplifié)
### US-FEED-01 Consulter son feed
Étant connecté, quand j'ouvre l'app, je vois les publications autorisées des comptes suivis, triées de la plus récente à la plus ancienne, paginées ; je vois un état vide si aucune. Les activités privées, bloquées ou hors autorisation n'apparaissent jamais.
### US-FOLLOW-01 Suivre quelqu'un
Depuis un profil public, je suis/ne suis plus cet utilisateur ; son contenu autorisé apparaît/disparaît de mon feed. Pour un compte privé, je fais une demande acceptée/refusée. Les blocages prévalent.
### US-TRAIN-01 Lancer et sauvegarder
Je sélectionne la discipline puis crée ma séance. Je peux saisir au moins un résultat valide, quitter l'écran, revenir et terminer sans perte, y compris hors ligne. Rejouer la synchronisation ne crée pas de doublon.
### US-TRAIN-02 Copier une séance
Depuis une activité autorisée, je peux créer une copie indépendante des exercices et objectifs, modifier mes propres charges/temps/répétitions, puis l'exécuter. Les résultats de l'auteur d'origine restent inchangés et la provenance est conservée.
### US-POST-01 Publier une activité
À la fin, ma séance reste privée tant que je ne choisis pas explicitement de publier. Je peux définir la visibilité et retirer une publication sans supprimer mon historique sportif.
### US-INTERACT-01 Réagir et commenter
Sur un post autorisé, je peux liker/unliker et commenter ; un double appui/retry ne crée pas de like en double ; un utilisateur bloqué ne peut pas interagir.
### US-PRIVACY-01 Gérer ses données
Je peux rendre mon compte privé, changer la visibilité d'un post, bloquer/signaler, demander export et suppression ; les accès côté serveur respectent les règles.
### US-HYBRID-01 Réaliser un WOD/Hyrox
Je peux saisir des résultats propres au format (temps total, rounds/reps ou segments distance/temps), les revoir dans mon historique et partager un résumé compréhensible dans le feed.

## 6. Modèle de domaine et invariants
Entités proposées (UUID ; created_at/updated_at ; optimistic locking si mutations concurrentes) :
- User(id, handle unique case-insensitive, display_name, bio, avatar_key, preferred_disciplines, account_visibility, units, locale, timezone)
- Follow(follower_id, followee_id, status=PENDING/ACCEPTED; unique pair), Block(blocker_id, blocked_id; unique pair)
- Exercise(id, canonical_name, category, equipment, metric_type, sport_tags), ExerciseTranslation éventuelle
- WorkoutTemplate(id, owner_id, sport, title, definition JSON versionnée, source_activity_id nullable, visibility, version)
- WorkoutSession(id, owner_id, client_generated_id unique per owner, sport, started_at, ended_at, status, draft JSON versionnée, template_id nullable)
- WorkoutResult(id, session_id, result_schema_version, result JSON versionné, summary JSON dérivé) ou résultats embarqués avec indexes ciblés ; arbitrer et documenter
- ActivityPost(id, author_id, session_id nullable, title, caption, audience=PRIVATE/FOLLOWERS/PUBLIC, published_at, deleted_at)
- Like(user_id, post_id, unique pair), Comment(id, post_id, author_id, body, timestamps, deleted_at)
- Report(id, reporter_id, target_type, target_id, reason, status), ModerationAction ; audit
- Program et Club : prévoir frontières de module, ne pas implémenter le métier en MVP.

**Séparer immuabilité et versions :** une session complétée est un historique, la publication en est une représentation qui peut être masquée ; la copie crée un nouveau template avec attribution éventuelle. Ne jamais injecter le résultat d'autrui dans les performances propres d'un utilisateur. Ne pas exposer l'emplacement exact ni l'horodatage de début précis dans les endpoints publics par défaut.

### Résultats minimum par type
- STRENGTH : ordered exercises → sets {kind, reps, weight, unit, duration?, distance?, completed}; estimations de 1RM seulement après MVP.
- CROSSFIT : format {AMRAP|EMOM|FOR_TIME|OTHER}, time_cap?, rounds?, reps?, elapsed_seconds?, movements, notes, scaled/rx.
- HYROX : ordered segments {kind: RUN|STATION, station_type?, distance_m?, duration_seconds?, weight_kg?, repetitions?}, elapsed_seconds?, notes.
- Valeurs validées (positives ou nulles selon sémantique), unités normalisées serveur ; schémas versionnés ; snapshot du nom d'exercice pour préserver historique même si catalogue évolue.

## 7. Architecture recommandée (proposition technique)
- Flutter Android/iOS, architecture feature-first, Riverpod ou Bloc **à choisir selon dépôt existant** ; stockage local SQLite/Drift ou équivalent pour drafts et outbox.
- Backend Java 21 + Spring Boot 3, monolithe modulaire, API REST JSON versionnée `/api/v1`, auth sécurisée (JWT/OIDC ou fournisseur existant), validation Jakarta, migrations Flyway.
- PostgreSQL avec indexes relationnels, JSONB seulement pour formes polymorphes ; stockage objet S3-compatible pour photos (reporté, avatar éventuellement).
- Pagination par curseur pour feed ; requêtes filtrées par visibilité sur serveur ; pas de fanout distribué avant nécessité mesurée.
- Tests Java JUnit/Testcontainers, tests Flutter et golden/widget critiques, CI lint/test/build. OpenAPI généré/contractuel.
- Aucun service tiers imposé sans lire le dépôt et décider du coût, de la sécurité et de la maintenabilité.

### Modules backend suggérés
identity, social-graph, catalog, training, publishing, discovery, safety-moderation, platform.

### API candidate (à finaliser par contrat OpenAPI)
- POST /auth/register ; POST /auth/login (ou endpoints OIDC existants)
- GET/PATCH /users/me ; GET /users/{handle} ; GET /users/search?q=
- POST/DELETE /users/{id}/follow ; POST /users/{id}/follow/accept ; POST /users/{id}/block
- GET /exercises?discipline= ; GET/POST /workouts/templates ; GET/PATCH /workouts/templates/{id}
- POST /sessions ; PATCH /sessions/{id} ; POST /sessions/{id}/complete ; GET /sessions?mine=true
- POST /posts ; GET /posts/{id} ; PATCH /posts/{id} ; DELETE /posts/{id}
- GET /feed/following?cursor= ; GET /feed/discover?cursor=
- POST/DELETE /posts/{id}/like ; GET/POST /posts/{id}/comments
- POST /reports ; GET /me/export ; DELETE /me (prévoir processus asynchrone et conformité).
Tous les endpoints doivent définir authentification, autorisations, validation, erreurs standardisées, pagination, limites/rate limits et règles de visibilité.

## 8. Non-fonctionnel et conformité
- Confidentialité RGPD : minimisation, droit d'accès/export/suppression, rétention définie, consentement médias si nécessaire, mentions légales et politique de confidentialité avant public.
- Sécurité : protection contre IDOR/BOLA, validation serveur, rate limit inscription/commentaires, restrictions upload, gestion secrets, contrôles d'autorisation par ressource.
- Modération : signalement, blocage, suppression et contrôle admin/audit minimaux ; CGU à préparer.
- Performance : temps de réponse p95 à définir et mesurer ; éviter N+1 feed, pagination curseur, index suivis/post date.
- Observabilité : logs corrélés, erreurs client et API, métriques, alerting raisonnable ; aucune donnée sensible dans logs.
- Offline : machine d'état draft/queued/syncing/synced/error, idempotency key et résolution explicite des conflits.
- Qualité : jeux de tests pour confidentialité, suppression, synchro et formats sportifs ; migrations réversibles si possible ; fixtures de démonstration.

## 9. Découpage initial du backlog (epics et cartes)
Format de ticket attendu : ID / titre / valeur / dépendances / livrables / acceptation en Given-When-Then / tests / estimation relative (S,M,L) / priorité P0-P2. Garder des tickets de 0,5 à 2 jours idéaux, fractionner tout ticket L avant implémentation.

### EPIC 00 — Initialisation & standards (P0)
- BOOT-01 Auditer repo, contraintes et décisions techniques ; produire ADR et liste de risques [P0]
- BOOT-02 Mettre en place mono-repo ou conventions des repos existants et README de développement [P0]
- BOOT-03 Installer CI lint, tests, build mobile + backend [P0]
- BOOT-04 Compose local PostgreSQL/API, migrations Flyway, seed de dev [P0]
- BOOT-05 Observabilité erreurs et configuration secrets par environnement [P0]
### EPIC 01 — Identity, privacy, profiles (P0)
- ID-01 Inscription/authentification et sessions [P0]
- ID-02 Profil modifiable, pseudo unique, disciplines, unités [P0]
- ID-03 Visibilité compte public/privé et demandes d'abonnement [P0]
- ID-04 Blocage utilisateurs et politiques d'accès [P0]
- ID-05 Export/suppression compte et audit minimal [P0]
### EPIC 02 — Catalogue & moteur de séance (P0)
- TR-01 Catalogue exercices seedé, recherche et filtre [P0]
- TR-02 Modèle versionné STRENGTH, CRUD de draft [P0]
- TR-03 Écran exécution muscu : séries, poids, reps, pause/reprise [P0]
- TR-04 Modèle CROSSFIT + saisie AMRAP/EMOM/For Time [P0]
- TR-05 Modèle HYROX + segments et chronométrage [P0]
- TR-06 Compléter, historique, résumé normalisé [P0]
- TR-07 Draft offline + outbox et synchro idempotente [P0]
### EPIC 03 — Templates et copie (P0)
- TMP-01 Créer/modifier un template personnel [P0]
- TMP-02 Démarrer une séance depuis un template [P0]
- TMP-03 Copier séance publiée autorisée vers nouveau template avec attribution [P0]
- TMP-04 Adapter charges, séries et temps avant de lancer [P0]
### EPIC 04 — Graph social / publication (P0)
- SOC-01 Follow/unfollow et demandes privées [P0]
- SOC-02 Publier depuis une session ; opt-in et audience [P0]
- SOC-03 Feed abonnements paginé et filtré autorisations [P0]
- SOC-04 Détail de publication et résumé de séance [P0]
- SOC-05 Likes idempotents et commentaires [P0]
- SOC-06 Supprimer/masquer publication sans supprimer la session [P0]
### EPIC 05 — Découverte & profils publics (P0)
- DIS-01 Recherche profils et page profil public [P0]
- DIS-02 Fil Découvrir simple, paginé, opt-in public [P0]
- DIS-03 États vides, onboarding follow et suggestions [P0]
### EPIC 06 — Confiance, QA & bêta (P0)
- SAFE-01 Signaler post/commentaire/utilisateur [P0]
- SAFE-02 Outils de modération et revue admin minimaux [P0]
- QA-01 Tests bout en bout flux social→copie→session→publication [P0]
- QA-02 Tests authorization, privacy, blocage, offline, duplication [P0]
- QA-03 Instrumentation événements produit (sans données sensibles) [P0]
- QA-04 Publication bêta fermée, documentation et checklist stores [P0]
### EPIC 07 — Suite P1/P2 (ne pas lancer sans accord)
- P1-01 Notifications ; P1-02 Photos ; P1-03 Clubs ; P1-04 Défis ; P1-05 Programmes multi-semaines ; P1-06 Liens externes.
- P2-01 Programmes communautaires ; P2-02 Coach/creator tools ; P2-03 Paiement et marketplace ; P2-04 Imports/intégrations.

## 10. Ordre d'exécution obligatoire — vertical slices
1. **Slice A (premier incrément démontrable) :** environnement + connexion → créer séance muscu minimale → terminer → publier en public → voir sa publication dans un feed et ouvrir détail. Utiliser une seed de deux comptes ; P0 safety dès qu'exposition à un autre compte.
2. **Slice B :** suivre autre compte → feed abonnements avec pagination et confidentialité.
3. **Slice C :** copier depuis feed → adapter → lancer → finir → publier avec attribution.
4. **Slice D :** CrossFit/Hyrox formats + offline robustesse.
5. **Slice E :** recherche, modération, suppressions, tests de sécurité, instrumentation, bêta fermée.
L'ordre des epics peut être entrelacé au profit des slices ; jamais développer toute la couche backend avant de pouvoir faire un flux utilisateur réel.

## 11. Définition de terminé (DoD)
- Critères d'acceptation démontrés ; tests automatisés utiles (unitaire, intégration et widget selon fonctionnalité) verts.
- Contrôle de droits et visibilité côté serveur couvert par tests ; aucune fuite de données privées.
- Schéma/migration inclus, API documentée, logs utiles sans données sensibles, UX états vide/erreur/chargement.
- Documentation mise à jour ; code linté, build CI ; PR de taille révisable ; aucune dette critique silencieuse.
- Fonction montrable en environnement local avec commandes reproductibles ; les décisions importantes sont documentées en ADR.

## 12. Instrumentation et validation produit
North Star Metric **proposée** : nombre hebdomadaire d'athlètes qui terminent au moins une séance ET ont une interaction sociale significative. Autres KPI : activation (première séance), WAU/MAU, rétention J7/J30, séances par utilisateur actif, pourcentage d'activités publiées, nombre de follows, parcours « copie→séance complétée », invitations actives. Événements analytics agrégés, sans exposition de charges/détails de santé à des tiers par défaut. Objectifs chiffrés à établir avec test pilote, pas de benchmarks inventés.

## 13. Risques / décisions ouvertes et règles pour l'agent
- Décider après audit si le repo a déjà une stack, un backend, une authentification ou des patterns imposés ; **ne pas réécrire l'existant** sans nécessité.
- Choix gestion état Flutter, SGBD, auth, fournisseur stockage, hosting, notifications : arbitrage consigné en ADR si absence de décision.
- Trancher format des schémas workout, versioning, persistence JSONB/relations, catalogue mouvements, fonctionnement offline et édition concurrente.
- Éclaircir si « Hyrox » désigne simple type sportif ou conformité/licence de marque ; ne pas afficher d'affiliation officielle.
- Privilégier feed chronologique au MVP ; ne pas introduire algorithme personnalisé sans données suffisantes.
- **Sécurité :** demander confirmation avant dépenses, services cloud payants, migrations destructives, push en production, publication store, changement d'auth existante ou intégration non réversible.
- En absence de réponse aux détails secondaires, choisir les defaults les plus simples et sûrs et documenter « ASSUMPTION ».

## 14. Prompt prêt à envoyer à un agent de codage
Tu es le lead developer et product engineer de ce projet. Lis intégralement `PRODUCT_SPEC_AGENT.md`, inspecte le dépôt, puis :
1. Établis l'état actuel du repo et les écarts vis-à-vis de la spec, sans inventer de code existant.
2. Crée `/docs/architecture.md`, `/docs/decisions/` pour ADR et un backlog de cartes détaillées dans `/docs/backlog/` (ou issues GitHub si les droits sont disponibles et confirmés), regroupées en epics, ordonnées par dépendance et découpées en lots de 0,5–2 jours.
3. Pour chaque carte indique ID, description, priorité, dépendances, critères d'acceptation testables, tests, fichiers/modules pressentis, estimation et définition de fini.
4. Propose le premier vertical slice et ses tests E2E. Implémente ce premier slice de bout en bout si le dépôt et l'environnement le permettent, en privilégiant des commits petits, lisibles et testables.
5. Démarre par la création d'un compte et d'une séance musculation minimale, puis l'affichage de cette séance dans un feed ; ne commence pas par les clubs, marketplace, IA ou microservices.
6. Ne crée aucune infrastructure facturable ni déploiement externe sans mon approbation. Signale précisément les blocages et les décisions non triviales. Termine avec un résumé de ce qui est fait, les commandes pour lancer/tests, les cartes produites et la prochaine carte à réaliser.

## 15. Sources / contexte marché (à vérifier périodiquement)
- Strava : https://press.strava.com/ ; fonctionnalités fitness/strength en évolution.
- Hevy : https://www.hevyapp.com/ ; https://help.hevyapp.com/
- JEFIT : https://www.jefit.com/
- SugarWOD : https://www.sugarwod.com/
- TrainHeroic : https://www.trainheroic.com/
Ce document est une spécification produit et technique, pas une affirmation d'exclusivité fonctionnelle ni une étude de marché chiffrée.
