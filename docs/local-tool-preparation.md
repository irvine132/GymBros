# Préparation locale Gym Bro — tentative du 16 octobre 2026

Cette note décrit une tentative **non terminée**. Aucun SDK, JDK, outil de build ou serveur PostgreSQL n'a été installé ou mis en service pendant cette tentative. Le code produit, les tests et le parcours à deux comptes restent absents. Aucun artefact d'un autre projet n'a été modifié. Voir aussi `shared-tools-audit.md` et ADR-001.

## Artefacts et capacité vérifiés

- Archive déjà présente `/dev/shm/flutter_3.47.7.tar.xz` : 1 578 092 224 octets ; `tar -tf` énumère 22 787 membres, dont `flutter/packages/flutter_tools/pubspec.yaml`. `xz -t` réussit. SHA-256 local `af7455f540df951184c7953fbe3cf884766e7541dacf8571f9f582db03dd6230`, identique au champ `sha256` de `https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json` pour Flutter 3.47.7 stable Linux (`stable/linux/flutter_linux_3.47.7-stable.tar.xz`). Aucune nouvelle archive téléchargée.
- `xz --robot --list` indique 2 610 042 880 octets **pour le flux TAR décompressé**, non une mesure exacte de l'occupation disque extraite (en-têtes, arrondi de blocs, métadonnées). L'extraction interrompue `/dev/shm/flutter` occupe ~2,5 Go, mais `packages/flutter_tools` est absent ; `flutter doctor -v` avait échoué. Ne pas déduire du seul écart des tailles que les autres fichiers sont intacts.
- `df -B1 / /dev/shm` : 3 950 637 056 octets disponibles sur `/`, 2 077 990 912 octets disponibles dans `/dev/shm` au contrôle. `free -h` : ~2,0 Gio RAM disponible, swap 4,0 Gio utilisé sur 4,0 Gio. L'archive et l'extraction partielle occupent déjà ~4,0 Go de tmpfs. Le précédent worker a été tué par signal 9 pendant une extraction ; la cause précise n'est pas établie.
- Une extraction propre à côté sur `/` demanderait environ 2,6 Go **plus** les coûts de JDK 21, Maven/Gradle, PostgreSQL, caches Flutter/Pub/Java et marge de tests. Sur seulement 3,7 Go disponibles, la capacité pic de la chaîne complète n'est pas démontrée. La reprise incrémentale en tmpfs ne doit pas être présumée sûre avec swap plein et incident précédent. Prévoir une réserve mesurée pour tous les composants et les processus avant démarrage.

## Blocage de l'outil d'exécution

Tentative bornée d'extraction de l'archive vérifiée dans le répertoire existant :

`tar -xJf /dev/shm/flutter_3.47.7.tar.xz --skip-old-files -C /dev/shm`

La commande a été **refusée avant exécution** par la politique du terminal : `BLOCKED: Security scan — [MEDIUM] Archive extraction to sensitive path ... single-query mode (-q) runs without a user present to approve it`. Une tentative limitée à un seul fichier, avec `-C /srv/hermes-dev/projects/gym-bro/.local-tools`, a reçu le même refus avant toute écriture. Une commande de comparaison TAR a également été refusée. Aucun contournement de ce contrôle n'a été employé ; `mkdir` inclus dans la commande rejetée n'a pas été exécuté. La simple validation cryptographique de l'archive n'est pas un `flutter doctor` réussi.

## Intervention requise et reprise vérifiable

1. L'opérateur doit fournir **un canal d'approbation interactif de l'extraction** pour cette carte ou un runner Gym Bro pré-équipé ; ne pas changer globalement les protections du terminal par l'agent. En parallèle, réserver assez de stockage persistant pour extraction + JDK + PostgreSQL + caches/tests, et confirmer la marge RAM/swap sous charge. Aucun effacement d'artefacts préexistants ni intervention sur les autres projets n'est autorisé par cette note.
2. Après autorisation et capacité avérée, installer les distributions officielles vérifiées dans un répertoire utilisateur dédié à Gym Bro hors Git, sans sudo ou modification de services système. Ne pas réutiliser une extraction partielle sans comparaison/réparation d'intégrité, puis vérifier `flutter doctor -v` et `flutter test` sur un projet smoke réel, Java 21 et build Maven/Gradle, et `SELECT 1` sur PostgreSQL isolé lié à localhost avec port distinct.
3. Reprendre uniquement alors l'implémentation Slice A ; tests serveur auth/IDOR et flux à deux comptes, tests Flutter et exécution locale avant tout push sur `dev/slice-a`. La revue indépendante de l'authentification/permissions porte sur le SHA candidat exact. Aucun push/main/production pendant ce blocage.
