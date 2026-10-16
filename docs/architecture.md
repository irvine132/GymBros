# Architecture cible et état réel — Slice A

Source : `PRODUCT_SPEC_AGENT.md` v1.0. Ce document décrit la cible, pas une implémentation existante. Au 16 octobre 2026, dépôt initial vide (`d76c1702b1c38ef11468d63680b956d8789fa8cb`), branche isolée `dev/slice-a`. Aucun code, migration, test, CI ou service préexistant. Le premier incrément n'est **pas terminé** tant que le client mobile et le serveur n'ont pas été construits et que le parcours deux comptes n'a pas été exercé.

## Découpage vertical et frontières

- `mobile/` : Flutter Android/iOS, navigation initiale sur Feed, écrans connexion/inscription, Train, historique privé, résumé et publication explicite, détail de publication. Gestion d'état feature-first, dépôt local de brouillon persistant et identifiant de session généré côté client. Les onglets et fonctionnalités hors Slice A doivent être clairement désactivés, pas simulés.
- `server/identity` : utilisateurs, hash de mot de passe éprouvé, sessions authentifiées, expiration/révocation, normalisation du pseudo. Jamais de secret dans les logs.
- `server/training` : séances de musculation avec exercices ordonnés et séries validées (`reps`, `weight`, `unit` kg/lb, `completed`). Brouillon, complétion immuable, historique propriétaire. `client_generated_id` unique par propriétaire pour retry.
- `server/publishing` : publication distincte d'une séance ; aucune publication à la complétion ; commande opt-in explicite, visibilité `PUBLIC` pour Slice A ; lecture du feed et du détail filtrée par autorisation serveur, champs publics projetés séparément (pas d'horaire de début précis, ni de localisation, ni de contact). Suppression/masquage ultérieur sans altérer la séance.
- `server/safety` : blocage bilatéral pour lecture/interactions inter-comptes ; signalement authentifié et idempotent (cible/rapporteur) avant ouverture sociale. Aucun chemin d'administration publique.
- `server/platform` : API `/api/v1`, erreurs cohérentes, validation, migrations additives non destructives, seed local séparé des environnements non-dev, tests d'intégration.

Limites de confiance : toute requête cliente est hostile. L'identité vient du mécanisme d'auth serveur, jamais d'un `owner_id` soumis. Toute lecture/écriture par ID vérifie propriétaire ou audience et blocage en base, y compris détail et pagination. Éviter les endpoints génériques exposant le JSON interne d'une séance. Validation bornée : titres, charges finies/non négatives, répétitions positives, unités explicites, nombre d'exercices/séries plafonné et longueur des champs limitée. Unité stockée par résultat et conversion uniquement pour l'affichage ; dates UTC ; version de schéma de résultat et nom d'exercice en snapshot. Les résultats publiés restent résumés publics, les brouillons/données sensibles ne quittent pas le compte propriétaire.

## Parcours Slice A et tests de preuve

1. A s'inscrit, se connecte, arrive sur feed vide ; A crée une séance musculation et saisit exercice, séries, reps, charge et unité. Le brouillon survit à un redémarrage du client et peut être repris. En ligne, les écritures sont idempotentes par identifiant client ; la synchronisation offline robuste et résolution de conflits restent hors Slice A.
2. A complète : historique personnel accessible, aucun post public. Une répétition réseau de la complétion n'ajoute ni séance ni post.
3. A choisit explicitement « Publier » : post distinct, public et visible dans feed puis détail sans données sensibles ; réessayer ne crée pas un second post. A se déconnecte ; le jeton local est effacé/invalidé.
4. B s'inscrit/se connecte et lit la publication publique de A ; B ne peut ni lire ni modifier la séance privée de A, ni publier cette séance, ni obtenir son brouillon par ID manipulé. A bloque B : le feed/détail cessent d'exposer le post à B. B peut signaler un post autorisé avant blocage. Tests automatisés unitaires, serveur intégration (migrations et deux comptes), widget Flutter et parcours end-to-end local requis avant qualification de cette tranche.

Les comptes de démonstration doivent être créés par un seed de développement explicite, non par une migration de production, avec secrets locaux non versionnés. Les identifiants de connexion de démonstration sont documentés seulement si non réutilisables en production ; préférer un script seed générant des comptes isolés en base de développement.

## Ordre de livraison et périmètre restant

Slice A seul : feed des publications publiques sans follow, pas d'algorithme, pagination simple et état vide ; aucun modèle/copieur, CrossFit/Hyrox, recherche, likes/commentaires, club, IA, paiement. Slice B : graphe follow, demandes privées, audience followers, feed abonnements par curseur. Slice C : templates/copier/adapter/provenance. Slice D : formats hybrides et offline outbox/conflicts. Slice E : découverte, modération admin, export/suppression, sécurité bêta, CI et télémétrie. Récupération de compte, limites de débit, suivi d'erreurs, politique de rétention et conformité juridique sont des exigences MVP/bêta non couvertes par Slice A ; ne pas exposer ce slice en production avant leur validation. Voir `docs/backlog/README.md`.

## Exécution locale envisagée, non encore vérifiée

Flutter 3.47.7 / Dart 3.13.5 et Java 21 / Spring Boot 3 / PostgreSQL restent des *propositions* (ADR-001). Ne pas présenter `flutter doctor`, `flutter test`, build Android/iOS, migration Flyway ou E2E comme réussis : la suite Flutter disponible en `/dev/shm/flutter` est incomplète (`packages/flutter_tools` absent), Java et PostgreSQL non disponibles dans ce shell et l'accès Docker est refusé. Aucune installation SDK supplémentaire ou extraction lourde ne doit être tentée avec 1,9 Go libre sur `/` et swap saturé ; mesurer capacité et prévoir un environnement de build isolé avant reprise. La disponibilité de `flutter --version` ne prouve pas une installation complète (`flutter doctor -v` échoue). Les futures commandes exactes de lancement ne seront documentées comme vérifiées qu'après implémentation et exercice réel.
