# Comparaison des Options d'Externalisation (Sauvegarde S3)

Dans le cadre du PRA (Plan de Reprise d'Activité), nous avons comparé l'utilisation d'un stockage objet auto-hébergé (MinIO) et d'un stockage Cloud public (S3/B2).

| Critère | Option A : MinIO (Auto-hébergé) | Option B : Cloud Public (Scaleway/B2) |
| :--- | :--- | :--- |
| **Coût** | Gratuit (Logiciel Open Source). Coût lié à l'infrastructure physique. | Modèle "Pay-as-you-go" après quota gratuit. Pas d'investissement matériel. |
| **Complexité** | Moyenne à élevée. Nécessite de gérer le serveur, les mises à jour et le stockage physique. | Faible. Service managé prêt à l'emploi avec une simple clé API. |
| **Souveraineté** | Maximale. Vous gardez le contrôle total sur l'emplacement physique des données. | Variable. Soumis aux juridictions du fournisseur (Cloud Act, RGPD). |
| **Performances** | Très hautes si local, limitées par l'upload si répliqué à distance par vos soins. | Dépend de la qualité de la connexion internet vers le Cloud. |
| **Maintenance** | À votre charge (disques, réseau, sécurité MinIO). | Gérée par le fournisseur Cloud (SLA élevé). |

**Conclusion du groupe :** Nous avons choisi l'**Option A (MinIO)** pour cette démonstration afin de simuler une infrastructure totalement maîtrisée et auto-suffisante, ce qui est idéal pour des tests en environnement local ou pour des entreprises privilégiant la souveraineté absolue de leurs données.
