# Partie 5 - Tests et procédures de restauration

## 1. Objectif

L’objectif de cette étape est de valider concrètement la capacité de restauration de la solution de sauvegarde mise en place et de mesurer le **RTO effectif** pour plusieurs scénarios réalistes.

Conformément au sujet, trois scénarios de restauration ont été testés :

1. **Restauration partielle** d’un fichier supprimé accidentellement depuis un snapshot Restic
2. **Restauration de la base MariaDB** de BookStack à partir d’un dump sauvegardé dans Restic
3. **Restauration complète du service BookStack** après suppression des conteneurs et des volumes, avec restauration de la configuration Docker et des données

La cible de RTO définie à l’étape 1 pour le service **BookStack + MariaDB** est de **30 minutes**, soit **1800 secondes**.

---

## 2. Environnement de test

L’infrastructure testée repose sur **Docker Compose** et comprend les services suivants :

- **BookStack**
- **MariaDB**
- **PostgreSQL**
- **MinIO**
- **backup_agent** avec **Restic**

La stratégie de sauvegarde repose sur :

- un **dépôt Restic local chiffré**
- une **réplication distante** des snapshots vers un dépôt S3 compatible hébergé sur MinIO
- des **dumps SQL** pour MariaDB et PostgreSQL
- la sauvegarde des **volumes Docker**
- la sauvegarde de la **configuration Docker** du projet

Avant d’effectuer les tests de restauration, la configuration de sauvegarde a été corrigée afin d’inclure également le dossier de configuration Docker du projet (`/project/docker`). Cette correction était nécessaire pour satisfaire l’exigence de restauration complète du scénario 3.

---

## 3. Snapshot de référence utilisé

Le snapshot principal utilisé pour les tests de restauration est le suivant :

- **Snapshot Restic local :** `b0c74d3c`

Ce snapshot contient les éléments suivants :

- `/tmp/dumps`
- `/data/bookstack`
- `/data/db_data`
- `/data/postgres_data`
- `/project/docker`

La présence du fichier témoin du scénario 1 a été vérifiée dans ce snapshot avec :

```bash
docker compose run --rm --no-deps --entrypoint restic backup_agent -r /backup_repo find s1_marker.txt
```

---

## 4. Méthodologie de mesure du RTO

Pour chaque scénario, la même méthode a été appliquée :

- démarrage du chronomètre juste avant la commande de restauration
- arrêt du chronomètre une fois la restauration terminée et les vérifications de succès validées

La mesure a été réalisée avec les commandes suivantes :

```bash
START=$(date +%s)

# opérations de restauration

END=$(date +%s)
echo "RTO = $((END-START)) secondes"
```

---

## 5. Scénario 1 - Restauration partielle d’un fichier

### 5.1 Objectif

Simuler la suppression accidentelle d’un fichier stocké dans les données de BookStack, puis restaurer uniquement ce fichier depuis un snapshot Restic à l’aide de l’option `--include`.

### 5.2 Donnée témoin

Un fichier nommé `s1_marker.txt` a été créé dans le chemin suivant :

`/config/restore-tests/s1_marker.txt`

Contenu du fichier :

`SCENARIO1_OK`

### 5.3 Incident simulé

Le fichier a été supprimé manuellement depuis le conteneur BookStack.

### 5.4 Méthode de restauration

Le fichier a été restauré depuis le snapshot `b0c74d3c` avec la commande suivante :

```bash
docker compose run --rm --no-deps \
  -v /tmp/restore_partial:/restore \
  --entrypoint restic backup_agent \
  -r /backup_repo restore b0c74d3c \
  --target /restore \
  --include /data/bookstack/restore-tests/s1_marker.txt
```

Le fichier restauré a ensuite été recopié dans le conteneur BookStack.

### 5.5 Vérifications effectuées

Les vérifications suivantes ont été réalisées :

- le fichier existe à nouveau dans `/config/restore-tests/`
- le contenu du fichier est correct
- le contenu attendu `SCENARIO1_OK` est bien retrouvé

### 5.6 Résultat

- **Statut :** Succès
- **RTO mesuré :** **2 secondes**

### 5.7 Interprétation

La restauration partielle a été réalisée avec succès. Le RTO observé est très inférieur à la cible de 1800 secondes, ce qui valide la capacité à restaurer rapidement un élément précis depuis un snapshot Restic.

---

## 6. Scénario 2 - Restauration de la base MariaDB de BookStack

### 6.1 Objectif

Simuler la perte complète de la base MariaDB utilisée par BookStack, restaurer le dump SQL depuis Restic, le réinjecter dans MariaDB, puis vérifier que l’application redémarre correctement.

### 6.2 Donnée témoin

Une page nommée :

`SAE_RESTORE_DB_TEST`

a été créée dans BookStack avant la sauvegarde.

La vérification SQL a montré que cette entrée apparaissait **2 fois** dans la table `bookstack.entities`. Cette valeur a servi de marqueur de référence pour le test.

### 6.3 Incident simulé

L’application BookStack a été arrêtée, puis la base `bookstack` a été supprimée avec :

```sql
DROP DATABASE bookstack;
```

### 6.4 Méthode de restauration

Le dossier `/tmp/dumps` a été restauré depuis le snapshot `b0c74d3c`, puis le dump MariaDB le plus récent a été réinjecté dans MariaDB.

### 6.5 Vérifications effectuées

Les vérifications suivantes ont été réalisées :

- BookStack redémarre correctement
- une réponse HTTP valide est obtenue (`302 Found` vers `/login`)
- le marqueur SQL est à nouveau présent avec une valeur de **2**

Requête de vérification utilisée :

```sql
SELECT COUNT(*) AS marker_count
FROM bookstack.entities
WHERE name='SAE_RESTORE_DB_TEST';
```

### 6.6 Résultat

- **Statut :** Succès
- **RTO mesuré :** **28 secondes**

### 6.7 Interprétation

La restauration de la base MariaDB a été menée à bien sans perte du marqueur applicatif. Le service BookStack est redevenu accessible après restauration du dump. Le RTO observé reste très inférieur à la cible de 1800 secondes.

---

## 7. Scénario 3 - Restauration complète du service BookStack

### 7.1 Objectif

Simuler la destruction complète du service BookStack en supprimant :

- les conteneurs `bookstack` et `mariadb`
- les volumes Docker `docker_bookstack_files` et `docker_db_data`

Puis restaurer l’ensemble depuis les sauvegardes, y compris :

- les données de BookStack
- les données MariaDB
- la configuration Docker

### 7.2 Incident simulé

Les éléments suivants ont été supprimés :

- conteneur `bookstack`
- conteneur `mariadb`
- volume `docker_bookstack_files`
- volume `docker_db_data`

### 7.3 Méthode de restauration

Les éléments suivants ont été restaurés depuis le snapshot `b0c74d3c` :

- `/data/bookstack`
- `/data/db_data`
- `/project/docker`

Les volumes Docker ont ensuite été recréés, puis les données restaurées y ont été recopiées. La configuration Docker du projet a également été restaurée à partir du snapshot avant le redémarrage des services.

### 7.4 Vérifications effectuées

Les vérifications suivantes ont été effectuées :

- BookStack répond avec `302 Found` vers `/login`
- la requête SQL sur le marqueur renvoie toujours **2**
- le fichier `s1_marker.txt` est de nouveau présent avec le contenu `SCENARIO1_OK`

### 7.5 Résultat

- **Statut :** Succès
- **RTO mesuré :** **52 secondes**

### 7.6 Interprétation

La restauration complète du service BookStack a réussi. Le service a pu être reconstruit après suppression complète des conteneurs et des volumes, tout en restaurant également la configuration Docker nécessaire au redémarrage. Le RTO mesuré reste largement inférieur à la cible de 1800 secondes.

---

## 8. Tableau comparatif des RTO

| Scénario | RTO mesuré | RTO cible | Résultat |
|---|---:|---:|---|
| Restauration partielle d’un fichier | 2 s | 1800 s | OK |
| Restauration de la base MariaDB | 28 s | 1800 s | OK |
| Restauration complète du service BookStack | 52 s | 1800 s | OK |

---

## 9. Difficultés rencontrées et correctifs apportés

Plusieurs ajustements ont été nécessaires avant de pouvoir exécuter les tests de restauration de manière fiable :

- ajout de la sauvegarde du dossier de configuration Docker dans le périmètre Restic
- correction de la configuration persistante de BookStack
- correction de la clé applicative `APP_KEY`
- vérification des volumes réellement utilisés par les conteneurs Docker
- validation du contenu réel des snapshots avant restauration

Ces ajustements ont permis de rendre la stratégie de restauration réellement opérationnelle et testable.

---

## 10. Conclusion

Les trois scénarios de restauration demandés ont été réalisés avec succès :

- **2 secondes** pour la restauration partielle d’un fichier
- **28 secondes** pour la restauration de la base MariaDB
- **52 secondes** pour la restauration complète du service BookStack

Dans les trois cas, le **RTO effectif mesuré** reste très inférieur à la cible de **1800 secondes** définie pour le service BookStack + MariaDB.

Ces tests valident donc le bon fonctionnement de la stratégie de sauvegarde et de restauration mise en place dans le cadre du PRA.

