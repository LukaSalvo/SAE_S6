# Rapport d'Analyse et Stratégie de Sauvegarde (Étape 1)

**Projet :** Conception d'un Plan de Reprise d'Activité (PRA) pour infrastructure conteneurisée  
**Contexte :** SAÉ S6.B.01 - Reprise rapide d'activité et externalisation cloud

---

## 1. Inventaire des données critiques

L'infrastructure repose sur des conteneurs Docker. Pour garantir une restauration complète, nous avons identifié les composants suivants comme étant critiques :

| Service | Type de donnée | Nature de la donnée | Emplacement (Volume/Chemin) |
| :--- | :--- | :--- | :--- |
| **MariaDB** | Base de données | Données textuelles, utilisateurs, pages BookStack | Volume `db_data` |
| **BookStack** | Fichiers applicatifs | Images téléchargées, avatars, logos | Volume `bookstack_data` |
| **Prometheus** | Métriques | Historique de supervision (TSDB) | Volume `prometheus_data` |
| **Grafana** | Configuration | Dashboards personnalisés, sources de données | Volume `grafana_data` |
| **Infrastructure** | Configuration | Fichiers de déploiement et variables d'environnement | `/opt/infra/*.yml` et `.env` |

---

## 2. Objectifs de reprise (RPO & RTO)

Nous avons défini des objectifs différenciés selon la criticité des services :

### A. Services de Production (BookStack + MariaDB)
* **RPO (Recovery Point Objective) : 1 heure.** *Justification :* Les utilisateurs ne doivent pas perdre plus d'une heure de travail de documentation en cas d'incident majeur.
* **RTO (Recovery Time Objective) : 30 minutes.** *Justification :* Le service de base de connaissances est central pour l'entreprise et doit être rétabli très rapidement.

### B. Services de Supervision (Prometheus + Grafana)
* **RPO : 6 heures.** *Justification :* Une perte partielle de l'historique des métriques est acceptable.
* **RTO : 2 heures.** *Justification :* La perte momentanée de la supervision n'arrête pas la production, mais limite la visibilité.

---

## 3. Stratégie de Sauvegarde : La Règle 3-2-1

Pour garantir une résilience maximale, nous adoptons la **règle 3-2-1**, pilier de la gestion des risques informatiques :

* **3 copies des données :** 1.  La donnée en production (conteneurs actifs).
    2.  Une sauvegarde locale (snapshot Restic sur le disque serveur).
    3.  Une sauvegarde externalisée (dépôt Restic distant).
* **2 supports différents :** * Le stockage SSD local du serveur (accès rapide pour restauration immédiate).
    * Un stockage objet distant (S3) indépendant de l'infrastructure physique du serveur.
* **1 copie hors site :** * Externalisation vers un fournisseur Cloud (ex: AWS S3, Scaleway ou MinIO distant) pour protéger les données contre les sinistres physiques (incendie, vol, inondation).

---

## 4. Scénarios d'incident et Cas de tests

Afin de valider notre PRA lors de l'étape 5, nous définissons les trois scénarios de tests suivants :

### Scénario 1 : Panne disque (Perte totale locale)
* **Description :** Simulation d'une défaillance matérielle rendant le répertoire `/var/lib/docker/volumes` inaccessible.
* **Action de test :** Suppression du répertoire de données local sur le serveur.
* **Objectif de restauration :** Reconstruction de l'infrastructure à partir de la copie **hors site (Cloud)**.

### Scénario 2 : Erreur humaine (Suppression de volume)
* **Description :** Un administrateur supprime par erreur le volume MariaDB via `docker volume rm`.
* **Action de test :** `docker-compose down` suivi d'un `docker volume rm db_data`.
* **Objectif de restauration :** Restauration ciblée du dernier snapshot depuis le **stockage local** via Restic.

### Scénario 3 : Corruption de données (Ransomware simulé)
* **Description :** Les fichiers de la base de données sont altérés ou chiffrés par un processus malveillant. Les conteneurs tournent mais le service est HS.
* **Action de test :** Injection de données aléatoires dans les fichiers `.ibd` de MariaDB (`dd if=/dev/urandom of=/var/lib/docker/volumes/db_data/_data/ibdata1`).
* **Objectif de restauration :** Utilisation de la fonction "Point-in-Time" de Restic pour revenir à un état sain juste avant l'attaque.