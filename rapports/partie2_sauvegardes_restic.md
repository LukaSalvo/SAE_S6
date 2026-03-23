# Sauvegardes Locales avec Restic

Ce document détaille la mise en place d'un système de sauvegardes incrémentales, chiffrées et dédupliquées pour une infrastructure Docker (MariaDB, PostgreSQL, BookStack).

## 1. Objectif
L'objectif est de garantir la résilience des données via une règle 3-2-1, en commençant par une sauvegarde locale automatisée sur un stockage simulé (dossier dédié simulant un disque de secours).

## 2. Architecture de la solution

La solution repose sur un **Agent de Sauvegarde** (conteneur Docker `backup_agent`) qui orchestre les étapes suivantes.

### Composants techniques :
- **Restic** : Outil de sauvegarde moderne gérant le chiffrement et la déduplication.
- **Dumps BDD** : Utilisation de `mysqldump` et `pg_dump` pour une extraction cohérente des bases.
- **Docker Compose** : Orchestration des volumes et des secrets.

## 3. Détails de l'implémentation

### A. Installation (`Dockerfile.backup`)
L'agent est basé sur une image **Alpine Linux** légère contenant les clients MariaDB/PostgreSQL et le binaire Restic.
- [Dockerfile.backup](file:///Users/lukasalvo/Documents/BUT/3_Annee/SAE/SAE_S6/Dockerfile.backup)

### B. Script de Sauvegarde (`backup_script.sh`)
Le script automatise le flux complet :
1. **Initialisation** : Crée le dépôt Restic dans `/backup_repo` s'il n'existe pas.
2. **Extraction** : Génère des fichiers `.sql` pour MariaDB et PostgreSQL.
3. **Backup** : Envoie les dossiers `/data/*` et les dumps SQL vers le dépôt chiffré.
4. **Rétention** : Applique une règle de "pruning" :
   - 7 sauvegardes journalières.
   - 4 sauvegardes hebdomadaires.
   - 12 sauvegardes mensuelles.
5. **Intégrité** : Lance une vérification (`restic check`) pour garantir l'absence de corruption.
- [backup_script.sh](file:///Users/lukasalvo/Documents/BUT/3_Annee/SAE/SAE_S6/backup_script.sh)

### C. Sécurité
Le mot de passe du dépôt est stocké dans un fichier protégé (`restic_password.txt`) monté en lecture seule. La variable `RESTIC_PASSWORD_FILE` permet à Restic d'y accéder sans jamais exposer le mot de passe en clair dans les processus ou les logs.

## 4. Commandes de gestion

Voici les commandes essentielles pour administrer vos sauvegardes via Docker Compose :

| Action | Commande |
| :--- | :--- |
| **Démarrer la stack** | `docker-compose up -d` |
| **Lancer un backup manuel** | `docker-compose start backup_agent` |
| **Voir les résultats (logs)** | `docker-compose logs -f backup_agent` |
| **Lister les snapshots** | `docker-compose run --rm backup_agent snapshots` |
| **Vérifier le dépôt** | `docker-compose run --rm backup_agent check` |
| **Explorer les fichiers** | `docker-compose run --rm backup_agent ls latest` |

## 5. Simulation du Loop Device
Dans cette configuration Docker, le "disque de sauvegarde" est simulé par un montage lié (bind mount) sur l'hôte vers le dossier `./my_restic_repo`. Cela garantit que les sauvegardes survivent à la suppression des conteneurs, tout en restant isolées des volumes de production.
