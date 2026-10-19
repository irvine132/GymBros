# Gym Bro — direction UI MVP, première tranche

Intention : carnet d'entraînement accueillant, pas tableau de performance ni réseau social à pression. La séance est privée par défaut ; la décision de partager est séparée, détaillée et confirmée.

Palette réversible : graphite #192326 pour structure et texte, fond minéral #F4F5EF, blanc pour les cartes, accent citron #C7EE60 pour avatar/repère. Pas de faux likes, statistiques ou badges. Typographie système avec titres gras 34/21, corps 15, espaces 8/12/20/24 ; contraste élevé sur fond clair. Boutons principaux d'au moins 52 px et lignes/puces tactiles adaptées. Le texte agrandi doit rester défilable, sans contenu critique dans une zone fixe hors navigation.

Navigation : Accueil (explication, communauté publique, CTA), Entraînement (historique, brouillon local/reprise, nouvelle séance), Profil (identité et comptes réels). Détail de publication et résumé sont des destinations contextuelles ; Clubs reste hors périmètre, sans bouton inerte. Pas de chiffres inventés, dates au jour seulement en public, unités explicites.

Catalogue de départ versionné dans l'API : 8 mouvements FR. Le nom et les résultats sont conservés dans la séance, sans référence mutable ni migration. La saisie libre est conservée. Les captures d'aperçu de widgets utilisent des fixtures explicitement fictives et ne démontrent pas la connexion au backend ; les tests d'intégration à deux comptes démontrent séparément les droits serveur.

Les anciennes publications de scripts techniques `Public smoke <8 hex>` ou `Demo squat <8 hex>` sont signalées dans le fil et le détail lorsque le pseudo correspond au format des comptes jetables générés. Repérage heuristique d'une dette de données de test existantes, sans masquage ni effacement : un titre/pseudo imitateur pourrait être étiqueté à tort ; un futur marquage de provenance serveur explicite est préférable avant ouverture à de vrais utilisateurs. L'aperçu sur le port local 18085 porte un bandeau DÉMO et simule l'API sans faux contenu présenté comme réel dans l'APK.

Suite après retour visuel sur cette tranche : B identité/visibilité sociale, C modèles et copie, D offline/conflits et sports avancés, E découverte/récupération et sûreté bêta ; tous sous acceptation distincte du backlog. Pas de prétention au MVP intégral dans cette livraison.
