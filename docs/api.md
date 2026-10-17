# API Slice A (locale, `/api/v1`)

Toutes les lectures/mutations hors `auth/register` et `auth/login` exigent `Authorization: Bearer <token>`. JSON strict (champs inconnus rejetés) ; réponse 401 session absente/expirée, 404 ressource interdite/inexistante, 400 valeur invalide, 409 identité déjà utilisée. Ne jamais enregistrer le jeton dans les logs. Service bind 127.0.0.1 par défaut et CORS limité aux origines navigateur localhost. Pas d'exposition publique avec cette configuration.

| Méthode | Chemin | Corps minimal | Résultat |
|---|---|---|---|
| POST | `/auth/register` | `{"handle":"alice_1","email":"alice@example.test","password":"..."}` | 201 `{token,userId}` ; pseudo 3–32 minuscules/chiffres/underscore, mot de passe 12–128 caractères |
| POST | `/auth/login` | `{email,password}` | 200 `{token,userId}` |
| POST | `/auth/logout` | `{}` | 204, jeton révoqué |
| GET | `/me` | — | `{id,handle}` |
| POST | `/sessions` | `{clientId:UUID,title,exercises:[{name,sets:[{reps,weight,unit:"kg"|"lb"}]}]}` | 201 ou 200 si clientId déjà vu par le propriétaire ; même session |
| PUT | `/sessions/{id}` | même corps | 200 si brouillon appartenant au compte, 404 sinon |
| GET | `/sessions`, `/sessions/{id}` | — | 50 derniers historiques/DTO complet seulement au propriétaire |
| POST | `/sessions/{id}/complete` | `{}` | 200, fin privée et idempotente |
| POST | `/sessions/{id}/posts` | `{}` | 201 ou 200 si déjà publié ; uniquement sur séance complétée propriétaire |
| GET | `/feed?offset=0` | — | 20 posts publics à la fois, filtrés par blocage avant pagination ; offset 0–1000 |
| GET | `/posts/{id}` | — | post public visible ou 404 |
| POST | `/users/{id}/block` | `{}` | 201/200 ; bloque visibilité inter-comptes dans les deux sens |
| POST | `/posts/{id}/reports` | `{reason}` | 201/200 si post visible ; raison 1–300 caractères |

DTO public : `id, authorId, author, title, sport, exerciseCount, date` (jour UTC). Pas de brouillon, email, horaire de début, séries ou localisation. La publication est distincte de la séance : elle ne se crée jamais lors de `complete`. Les résultats privés sont immuables après fin. `resultSchemaVersion=1` est conservé sur la session. Les erreurs Spring par défaut ne sont pas encore un contrat d'erreurs normalisé ; sécurité et rate limiting bêta à compléter.
