# API Slice A (locale, `/api/v1`)

Toutes les lectures/mutations hors `auth/register` et `auth/login` exigent `Authorization: Bearer <jeton>`. JSON strict (champs inconnus rejetés) ; réponse 401 session absente/expirée, 404 ressource interdite/inexistante, 400 valeur invalide, 409 identité déjà utilisée. Ne jamais enregistrer le jeton dans les logs. Service bind 127.0.0.1 par défaut et CORS limité aux origines navigateur localhost ; le gateway de test HTTPS distinct est décrit dans `public-api-test.md`.

| Méthode | Chemin | Corps minimal | Résultat |
|---|---|---|---|
| POST | `/auth/register` | `{"handle":"alice_1","email":"alice@example.test","password":"..."}` | 201 `{token,userId}` ; pseudo 3–32 minuscules/chiffres/underscore, mot de passe 12–128 caractères |
| POST | `/auth/login` | `{email,password}` | 200 `{token,userId}` |
| POST | `/auth/logout` | `{}` | 204, jeton révoqué |
| GET | `/me` | — | `{id,handle}` |
| GET | `/me/summary` | — | `{handle,sessions,publications}` : comptes réels propres uniquement (séances terminées et posts actifs) |
| GET | `/exercises` | — | catalogue de mouvements versionné dans le code, noms FR/catégories/unité suggérée ; le nom choisi est sauvegardé en snapshot de séance |
| POST | `/sessions` | `{clientId:UUID,title,exercises:[{name,sets:[{reps,weight,unit:"kg"|"lb"}]}]}` | 201 ou 200 si clientId déjà vu par le propriétaire ; même session |
| PUT | `/sessions/{id}` | même corps | 200 si brouillon appartenant au compte, 404 sinon |
| GET | `/sessions`, `/sessions/{id}` | — | 50 dernières séances / DTO complet seulement au propriétaire ; détail inclut `published` et `workout` privés |
| POST | `/sessions/{id}/complete` | `{}` | 200, fin privée et idempotente |
| POST | `/sessions/{id}/posts` | `{}` | 201 ou 200 si déjà publié ; uniquement sur séance complétée propriétaire |
| GET | `/feed?offset=0` | — | 20 posts publics à la fois, filtrés par blocage avant pagination ; offset 0–1000 |
| GET | `/posts/{id}` | — | post public visible ou 404 |
| POST | `/users/{id}/block` | `{}` | 201/200 ; bloque visibilité inter-comptes dans les deux sens |
| POST | `/posts/{id}/reports` | `{reason}` | 201/200 si post visible ; raison 1–300 caractères |

DTO public : liste blanche `id, authorId, author, title, sport, exerciseCount, date` (jour UTC), `exercises:[{name,sets:[{reps,weight,unit}]}]`. Les séries/charges deviennent visibles seulement après publication volontaire et confirmation mobile ; jamais `clientId`, payload brut, brouillon, email, horaire de début ni localisation. La publication est distincte de la séance : elle ne se crée jamais lors de `complete`. Les résultats privés sont immuables après fin. `resultSchemaVersion=1` est conservé sur la session. Le catalogue est une liste de départ statique, sans nouvelle table/migration, et la saisie libre reste possible. Les erreurs Spring par défaut ne sont pas encore un contrat d'erreurs normalisé ; sécurité et rate limiting bêta à compléter.

## Slice B — identité publique et abonnements (V4 additive)

Règle de visibilité : `docs/decisions/ADR-003-private-accounts-follow-feed.md`. Tous les endpoints requièrent le bearer hors auth. Le compte privé reste trouvable par pseudo/nom (identité minimale), mais aucune publication, même historiquement PUBLIC, n'est visible pour les inconnus. Un blocage dans les deux sens retire profil/recherche/posts/fils (404 pour une ressource). Les séances et `/me/summary` demeurent propriétaires.

| Méthode | Chemin | Résultat |
|---|---|---|
| GET | `/me` | `{id,handle,displayName,private,unit}` ; email absent |
| PUT | `/me/profile` | `{displayName:null ou 1–60,private:bool,unit:"kg"|"lb"}` ; réponse `/me` ; handle immuable |
| GET | `/users?query=...` | 2–60 caractères ; 20 profils visibles `{id,handle,displayName,private,relation}` (`NONE`, `PENDING`, `ACCEPTED`), jamais email/stats privés |
| GET | `/users/{id}` | profil minimal ou 404 si bloqué/inexistant |
| GET | `/users/{id}/posts?limit=20&cursor=...` | `{items,nextCursor}` ; 404 pour compte privé non accepté, projections seules |
| POST/DELETE | `/users/{id}/follow` | POST `{status}` ACCEPTED public ou PENDING privé (200/202) ; DELETE `{status:"NONE"}` (200), idempotents pour cible accessible ; self 400 |
| GET | `/me/follow-requests` | `{id,handle}[]` demandes reçues non bloquées |
| POST | `/follow-requests/{requesterId}/accept` ou `/reject` | seul destinataire, uniquement PENDING → `{status}` ; sinon 404 |
| GET | `/feed/following?limit=20&cursor=...` | `{items,nextCursor}`, tri inverse `(published_at,id)`, filtrage ACCEPTED + non-bloqué avant LIMIT, audiences PUBLIC/FOLLOWERS |
| POST | `/sessions/{id}/posts` | `{audience:"PUBLIC"|"FOLLOWERS"}` facultatif pour clients précédents (défaut PUBLIC) ; premier post immuable, même post au retry |

Curseur base64url `(instant UTC|UUID)` opaque, max 150 caractères ; limite 1–20, erreur 400 si invalide. Le fil Découvrir `/feed?offset` reste réservé aux comptes publics et posts PUBLIC. Le détail applique le même contrat, y compris après changement de privacité/blocage. Aucune lecture de session privée complète pour un tiers. La passerelle HTTPS de test conserve une allowlist exacte de ces seules routes et paramètres ; aucun endpoint admin.

## Tranche C — modèles personnels et copie (V5 additive)

Voir `docs/decisions/ADR-004-copy-templates-provenance.md`. Tous les chemins exigent le bearer ; les modèles et leurs éditions/démarrages sont limités au propriétaire. Les inconnus et tiers reçoivent 404. Aucun endpoint de liste de modèles d'autrui.

| Méthode | Chemin | Résultat |
|---|---|---|
| POST | `/posts/{id}/copy` | 201 `{id,title,exercises,definitionVersion:1,version:1,sourcePostId,sourceAuthor}` si le post est lisible au moment de l'action ; retry 200 même modèle propriétaire, revérifie le droit avant réponse |
| GET | `/templates`, `/templates/{id}` | Jusqu'à 50 modèles personnels / détail ; `exercises` est le snapshot de cibles, jamais les résultats du compte source |
| PUT | `/templates/{id}` | `{title,exercises:[{name,sets:[{reps,weight,unit}]}]}` ; même validation que séance, incrémente `version` ; original et autres modèles inchangés |
| POST | `/templates/{id}/sessions` | `{clientId:UUID}` ; 201 brouillon personnel indépendant contenant le snapshot, retry 200 même séance via clientId |

`/sessions/{id}` du propriétaire et les projections post/fil du copieur portent `sourcePostId` et `sourceAuthor` uniquement si le lecteur est actuellement autorisé à lire la source. Sinon `sourceUnavailable:true` sans identité, titre ou ID source ; la copie acquise conserve ses propres cibles après révocation. La session est privée par défaut, `complete` et `posts` existants restent séparés. Aucun changement de politique de comptes ni d'audience. La version est celle de la définition courante ; l'historique des anciennes éditions et les templates créés de zéro sont reportés, pas d'affirmation CRUD complet/version history dans cette tranche.

## Tranche D1 — WOD CrossFit (sans migration de table)

Voir `docs/decisions/ADR-005-crossfit-wod-results.md`. Même bearer, propriétaire et modèle de publication opt-in que les séances précédentes ; le payload privé est `resultSchemaVersion:2`. La création/réédition STRENGTH ne peut pas modifier un WOD et un retry avec `clientId` d'une autre discipline renvoie 409.

| Méthode | Chemin | Résultat |
|---|---|---|
| POST | `/wods` | `{clientId:UUID,title,format:"AMRAP"|"EMOM"|"FOR_TIME",timeCapSeconds:60..7200,movements:["Burpees"],result:{rounds:5,reps:7,scaled:false}}` ; For Time utilise `{timeSeconds:610,scaled:true}`. 201 créé, 200 même clientId WOD ; 400 score/format hors contrat |
| PUT | `/wods/{id}` | même corps, uniquement brouillon du propriétaire, sinon 404 |
| GET/POST | `/sessions/{id}`, `/sessions/{id}/complete`, `/sessions/{id}/posts` | réutilisent détail privé, fin privée et publication volontaire existants ; aucune conversion implicite |

Projection publique WOD uniquement `{id,authorId,author,title,date,sport:"CROSSFIT",format,timeCapSeconds,movements,result}` avec `result` limité à rounds/reps/timeSeconds/scaled. Le time cap est un objectif d'effort, pas un horaire de début. Pas de session brute, `clientId` ni heures précises. `/posts/{id}/copy` refuse les WOD avec 400 (copie version 1 STRENGTH seulement), après contrôle de visibilité ; aucun bouton Copier affiché pour un WOD.

## Tranche D3 — fin locale privée conditionnelle

`POST /sessions/{id}/complete-expected` accepte le payload sportif privé exact soumis à la création (`Workout`, `Wod` ou `Hyrox` comme JSON). Bearer requis, propriétaire seul : 404 si absent ou tiers, 409 si payload différent du brouillon distant ou d'une séance déjà terminée, 200 si brouillon identique terminé ou si même fin rejouée. Comparaison JSONB sans champs null ; `clientId` reste stable. Ce chemin ne crée jamais de publication. Il ne remplace pas les anciens clients utilisant `/complete` sans garde ; voir `docs/decisions/ADR-007-offline-completion-outbox.md`. La passerelle n'autorise que POST avec UUID au bon chemin et corps ≤64 Kio, pas de route administrative.
