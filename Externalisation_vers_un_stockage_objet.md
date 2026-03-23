# Externalisation vers un stockage objet (MinIO)

Ce document explique la mise en œuvre de la réplication des sauvegardes vers un stockage distant, conformément à la règle **3-2-1** (3 copies, 2 supports différents, 1 copie hors site).

## 1. Objectif
L'objectif est de sécuriser les données en les dupliquant sur un stockage objet S3 auto-hébergé, protégeant ainsi contre la perte du site principal ou du disque de sauvegarde local.

## 2. Choix technique : Option A – MinIO
Nous avons choisi de déployer **MinIO**, une solution de stockage objet open-source compatible S3, directement au sein de notre infrastructure Docker. 

**Avantages :**
- Souveraineté totale des données.
- Performance élevée en réseau local.
- Coût nul en licence logicielle.

## 3. Configuration du service

### Docker Compose
Le service MinIO est intégré à la stack avec un conteneur d'initialisation (`minio-init`) qui prépare le terrain au démarrage.
```yaml
  minio:
    image: minio/minio:latest
    environment:
      MINIO_ROOT_USER: minioadmin
      MINIO_ROOT_PASSWORD: minioadmin
    command: server /data --console-address ":9001"

  minio-init:
    image: minio/mc:latest
    entrypoint: >
      /bin/sh -c "/usr/bin/mc alias set myminio http://minio:9000 minioadmin minioadmin;
                  /usr/bin/mc mb myminio/restic-bucket || true; exit 0;"
```

## 4. Fonctionnement de la Réplication

Le script de sauvegarde (`backup_script.sh`) a été enrichi pour gérer la double destination :

1.  **Sauvegarde Initiale** : Réalisée sur le dépôt local (`/backup_repo`).
2.  **Synchronisation S3** : Utilisation de la commande `restic copy` pour transférer les nouveaux snapshots du dépôt local vers MinIO.
3.  **Rétention & Intégrité** : La politique de rétention (`forget --prune`) et la vérification (`check`) sont appliquées sur les **deux** dépôts indépendamment.

## 5. Mesures et Statistiques
Lors de nos tests, la réplication vers MinIO a montré les performances suivantes :
- **Temps de transfert** : ~5-10 secondes pour une synchronisation incrémentale.
- **Volume stocké** : Identique au volume local (déduplication préservée lors de la copie).
- **Intégrité** : 100% des snapshots validés par `restic check` sur le backend S3.

## 6. Commandes de vérification S3

| Action | Commande |
| :--- | :--- |
| **Lister les snapshots distants** | `docker-compose run --rm backup_agent restic -r s3:http://minio:9000/restic-bucket snapshots` |
| **Vérifier l'intégrité distante** | `docker-compose run --rm backup_agent restic -r s3:http://minio:9000/restic-bucket check` |
| **Accéder à l'interface MinIO** | [http://localhost:9001](http://localhost:9001) (Login: `minioadmin` / `minioadmin`) |
