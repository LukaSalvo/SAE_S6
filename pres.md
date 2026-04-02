# Antiseche Technique -- SAE S6 PRA

---

## 1. Architecture globale

```
┌─────────────────────────────────────────────────────────────────┐
│                        HOST (Linux)                             │
│                                                                 │
│  ┌───────────┐  ┌──────────┐  ┌───────────┐                    │
│  │ BookStack  │  │ MariaDB  │  │ PostgreSQL│  <-- Services      │
│  │  :6875     │  │          │  │           │      applicatifs    │
│  └─────┬─────┘  └────┬─────┘  └─────┬─────┘                    │
│        │             │              │                           │
│        v             v              v                           │
│  ┌──────────────────────────────────────┐                       │
│  │         Volumes Docker              │                        │
│  │  bookstack_files  db_data  pg_data  │                        │
│  └──────────────────┬──────────────────┘                        │
│                     │                                           │
│                     v                                           │
│  ┌──────────────────────────────────────┐                       │
│  │         backup_agent                │  <-- Conteneur Restic  │
│  │  1. mysqldump / pg_dump             │                        │
│  │  2. restic backup (local)           │                        │
│  │  3. restic copy (vers MinIO)        │                        │
│  │  4. restic forget --prune           │                        │
│  │  5. restic check                    │                        │
│  └─────────┬───────────────┬───────────┘                        │
│            │               │                                    │
│            v               v                                    │
│  ┌─────────────┐  ┌───────────────┐                             │
│  │ Depot local │  │ MinIO (S3)    │  <-- Regle 3-2-1            │
│  │ /backup_repo│  │ :9000 / :9001 │      Copie 2 + Copie 3     │
│  └─────────────┘  └───────────────┘                             │
│                                                                 │
│  ┌──────────────────────────────────────────────────────┐       │
│  │              Stack Monitoring                        │       │
│  │  Prometheus:9090  Pushgateway:9091  Grafana:3000     │       │
│  │  Alertmanager:9093                                   │       │
│  └──────────────────────────────────────────────────────┘       │
│                                                                 │
│  ┌──────────────────────────────────────────────────────┐       │
│  │  Systemd Timer (backup-restic.timer)                 │       │
│  │  --> Lance backup_orchestrator.sh chaque nuit 02h00  │       │
│  └──────────────────────────────────────────────────────┘       │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. Docker Compose -- Tous les services

| Service | Image | Role | Ports |
|---------|-------|------|-------|
| `db` | `mariadb:10.11` | BDD de BookStack | interne |
| `postgres` | `postgres:16-alpine` | BDD secondaire | interne |
| `bookstack` | `linuxserver/bookstack` | Wiki applicatif | `6875:80` |
| `backup_agent` | Build local (`Dockerfile.backup`) | Agent de sauvegarde Restic | aucun |
| `minio` | `minio/minio:latest` | Stockage objet S3 | `9000` (API) `9001` (UI) |
| `minio-init` | `minio/mc:latest` | Cree le bucket au demarrage | aucun |
| `prometheus` | `prom/prometheus:latest` | Collecte les metriques | `9090` |
| `pushgateway` | `prom/pushgateway:latest` | Recoit les metriques des scripts | `9091` |
| `alertmanager` | `prom/alertmanager:latest` | Gere les alertes | `9093` |
| `grafana` | `grafana/grafana:latest` | Dashboards de supervision | `3000` |
| `seed_metrics` | `curlimages/curl:latest` | Injecte des metriques de demo | aucun |

### Volumes Docker

| Volume | Utilise par | Contenu |
|--------|-------------|---------|
| `db_data` | MariaDB | Fichiers InnoDB de la BDD bookstack |
| `postgres_data` | PostgreSQL | Fichiers de la BDD pgdb |
| `bookstack_files` | BookStack | Config, uploads, cache (`/config`) |
| `minio_data` | MinIO | Objets S3 (snapshots Restic repliques) |
| `prometheus_data` | Prometheus | Time-series des metriques |
| `grafana_data` | Grafana | Dashboards, preferences |

---

## 3. Comment Restic fonctionne (pour expliquer au jury)

### Deduplication
- Restic decoupe les fichiers en **blobs** (morceaux de taille variable, ~1-8 Mo)
- Chaque blob est identifie par son **hash SHA-256**
- Si un blob existe deja dans le depot, il n'est pas re-stocke
- Resultat : les sauvegardes incrementales sont tres rapides et compactes

### Chiffrement
- **AES-256-CTR** pour les donnees
- **Poly1305-AES** pour l'authentification
- Le mot de passe ne quitte jamais la machine : chiffrement **cote client**
- Meme le serveur S3 (MinIO) ne peut pas lire les donnees

### Snapshots
- Chaque sauvegarde cree un **snapshot** = photo de l'etat des fichiers a un instant T
- Un snapshot reference des **trees** (arborescence) qui referencent des **blobs** (donnees)
- `restic forget` supprime les snapshots mais PAS les blobs
- `restic prune` supprime les blobs orphelins (plus references par aucun snapshot)

### Structure d'un depot Restic
```
my_restic_repo/
├── config          # Cle de chiffrement du depot (chiffree par le mot de passe)
├── data/           # Blobs de donnees (chiffres)
├── index/          # Index : quel blob est dans quel pack
├── keys/           # Cles de dechiffrement (protegees par mot de passe)
├── locks/          # Verrous pour eviter les acces concurrents
└── snapshots/      # Metadonnees des snapshots (date, chemins, tags)
```

---

## 4. Scripts -- Ce qu'ils font ligne par ligne

### backup_script.sh (tourne dans le conteneur backup_agent)

```
Etape 1 : Verification des depots
  - restic snapshots sur depot local --> si erreur, restic init
  - restic snapshots sur depot S3    --> si erreur, restic init

Etape 2 : Dumps SQL
  - mysqldump --all-databases --> /tmp/dumps/mariadb_TIMESTAMP.sql
  - pg_dump                   --> /tmp/dumps/postgres_TIMESTAMP.sql

Etape 3 : Sauvegarde Restic
  - restic backup des chemins :
      /tmp/dumps           (dumps SQL)
      /data/bookstack      (volume BookStack monte en read-only)
      /data/db_data        (volume MariaDB monte en read-only)
      /data/postgres_data  (volume PostgreSQL monte en read-only)
      /project/docker      (config Docker du projet, read-only)
  - restic copy du depot local vers le depot S3 (MinIO)

Etape 4 : Retention
  - restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 12 --prune
  - Applique sur les DEUX depots (local + S3)

Etape 5 : Verification
  - restic check sur les deux depots
```

### backup_orchestrator.sh (tourne sur le HOST, appele par systemd)

```
Difference avec backup_script.sh :
  - Tourne sur le HOST (pas dans Docker)
  - Arrete les conteneurs AVANT la sauvegarde (coherence des fichiers disque)
  - Les redemarre APRES
  - Genere un rapport JSON dans rapports/
  - Pousse les metriques vers le Pushgateway (curl POST)
```

---

## 5. Commandes Restic essentielles

```bash
# Initialiser un depot
restic init -r /chemin/depot

# Faire une sauvegarde
restic backup /dossier1 /dossier2 --tag "mon_tag"

# Lister les snapshots
restic snapshots

# Voir le contenu d'un snapshot
restic ls <snapshot_id>

# Chercher un fichier dans les snapshots
restic find mon_fichier.txt

# Restaurer un snapshot complet
restic restore <snapshot_id> --target /tmp/restore

# Restaurer un fichier specifique
restic restore <snapshot_id> --target /tmp/restore --include /chemin/fichier

# Copier vers un autre depot (replication S3)
restic -r <depot_distant> copy --from-repo <depot_local>

# Politique de retention
restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 12 --prune

# Verifier l'integrite
restic check
```

---

## 6. Stack Monitoring -- Flux des metriques

```
backup_orchestrator.sh
        │
        │ curl POST (metriques brutes)
        v
  ┌─────────────┐
  │ Pushgateway  │  <-- Stocke la derniere valeur poussee
  │   :9091      │
  └──────┬──────┘
         │ scrape toutes les 15s
         v
  ┌─────────────┐
  │ Prometheus   │  <-- Stocke les time-series
  │   :9090      │
  └──┬───────┬──┘
     │       │
     v       v
┌────────┐ ┌──────────────┐
│Grafana │ │ Alertmanager │
│ :3000  │ │    :9093     │
└────────┘ └──────────────┘
```

### 4 metriques exposees

| Metrique | Type | Description |
|----------|------|-------------|
| `restic_last_backup_timestamp_seconds` | gauge | Epoch de la derniere sauvegarde reussie |
| `restic_backup_duration_seconds` | gauge | Duree en secondes |
| `restic_backup_size_bytes` | gauge | Taille du depot en octets |
| `restic_integrity_status` | gauge | 0 = OK, 1 = erreur |

### 2 alertes configurees

| Alerte | Expression PromQL | Signification |
|--------|-------------------|---------------|
| `BackupGaps` | `(time() - restic_last_backup_timestamp_seconds{status="success"}) > 90000` | Pas de backup depuis 25h |
| `IntegrityFailure` | `restic_integrity_status != 0` | Le `restic check` a echoue |

---

## 7. Systemd -- Timer et Service

### backup-restic.timer
```ini
[Timer]
OnCalendar=*-*-* 02:00:00    # Chaque nuit a 2h du matin
RandomizedDelaySec=600        # +/- 10 min aleatoire (eviter pic)
Persistent=true               # Rattrape les executions manquees
```

### backup-restic.service
```ini
[Service]
Type=oneshot                  # Execute une fois puis s'arrete
ExecStart=/bin/bash backup_orchestrator.sh
```

### Commandes utiles
```bash
# Voir les timers actifs
systemctl list-timers --all | grep backup

# Voir les logs du dernier run
journalctl -u backup-restic.service -n 50

# Lancer manuellement
sudo systemctl start backup-restic.service

# Activer le timer
sudo systemctl enable --now backup-restic.timer
```

---

## 8. Regle 3-2-1

| Copie | Ou | Support | Type |
|-------|----|---------|------|
| **Copie 1** | Volumes Docker en production | SSD serveur | Donnees live |
| **Copie 2** | Depot Restic local (`/backup_repo`) | SSD serveur (loop device) | Sauvegarde locale |
| **Copie 3** | Bucket MinIO/S3 (`restic-bucket`) | Stockage objet distant | Sauvegarde hors site |

---

## 9. RPO / RTO -- Rappel des definitions

- **RPO** (Recovery Point Objective) = quantite de donnees qu'on accepte de PERDRE
  - "Combien de temps de travail peut-on perdre ?"
  - Notre RPO cible : 1h -- effectif : 24h (1 backup/jour)

- **RTO** (Recovery Time Objective) = temps pour REMETTRE en service
  - "Combien de temps peut-on rester hors ligne ?"
  - Notre RTO cible : 30 min -- effectif : 52s (scenario le pire)

---

## 10. Questions pieges et reponses

**"Pourquoi les volumes sont montes en read-only dans backup_agent ?"**
> Pour que l'agent de sauvegarde ne puisse pas modifier les donnees de production. C'est le principe du moindre privilege.

**"Pourquoi faire un dump SQL alors qu'on sauvegarde deja le volume MariaDB ?"**
> Un volume MariaDB contient des fichiers InnoDB. Les copier pendant que la BDD tourne peut donner des fichiers incoherents. Le dump SQL (`mysqldump --single-transaction`) garantit une copie coherente a chaud. On sauvegarde les deux par securite.

**"C'est quoi le `--single-transaction` dans mysqldump ?"**
> Ca lance le dump dans une transaction InnoDB. Toutes les tables sont lues dans le meme etat transactionnel, sans verrouiller les ecritures. C'est ce qui permet le dump "a chaud".

**"Pourquoi `restic copy` et pas juste `restic backup` vers S3 ?"**
> `restic backup` recreerait un snapshot independant. `restic copy` copie les snapshots existants du depot local vers le depot distant, en preservant l'historique et les IDs. C'est une vraie replication.

**"Pourquoi Pushgateway et pas un scrape direct ?"**
> Le backup_agent est un job ephemere (il tourne, fait le backup, et s'arrete). Prometheus ne peut pas scraper un service qui n'est pas toujours en ligne. Le Pushgateway sert de relais : le script pousse ses metriques, puis s'arrete, et Prometheus vient les lire plus tard.

**"Le loop device c'est quoi exactement ?"**
> Un fichier sur le disque (`/opt/restic_disk.img`) qu'on monte comme si c'etait un vrai disque avec `losetup` + `mkfs.ext4` + `mount`. Ca simule un disque separe pour respecter la regle "2 supports differents". En prod, ce serait un vrai disque ou un NAS.

**"Que se passe-t-il si le backup echoue ?"**
> Le script retourne un code erreur, le rapport JSON indique "failure", la metrique `restic_integrity_status` passe a 1. L'alerte `BackupGaps` se declenche apres 25h sans sauvegarde reussie. L'alerte `IntegrityFailure` se declenche immediatement si le check echoue.

**"Pourquoi Alpine dans le Dockerfile ?"**
> Image minimaliste (~5 Mo). On installe uniquement restic, les clients SQL, bash et curl. L'image finale fait ~50 Mo au lieu de ~500 Mo avec Ubuntu.


# Plan de Presentation -- Soutenance SAE S6 PRA

**Duree estimee** : 20-25 min (presentation) + 5-10 min (questions)

---

## Repartition des roles

| Personne | Parties | Duree |
|----------|---------|-------|
| **Personne 1** | Introduction + Etape 1 (Analyse) + Etape 2 (Restic) | ~8 min |
| **Personne 2** | Etape 3 (Externalisation) + Etape 4 (Automatisation & Monitoring) | ~7 min |
| **Personne 3** | Etape 5 (Tests de restauration) + Etape 6 (DRP) + **Demo live** | ~10 min |

---

## Deroulement detaille

### Personne 1 -- Fondations (8 min)

#### Intro (2 min)
- Presenter le contexte : "On a une infra Docker avec BookStack, MariaDB, PostgreSQL. Que se passe-t-il si tout tombe ?"
- Objectif du projet : concevoir un PRA complet, de l'analyse a la restauration testee
- Montrer le schema d'architecture (`docs/architecture.png`)

#### Etape 1 -- Analyse et strategie (3 min)
- **Inventaire des donnees critiques** : volumes Docker, BDD, fichiers de config
- **RPO/RTO definis** : RPO 24h, RTO 30 min pour BookStack+MariaDB
- **Regle 3-2-1** : 3 copies, 2 supports, 1 hors site -- expliquer pourquoi
- **Scenarios d'incident** : panne disque, suppression accidentelle, ransomware simule

#### Etape 2 -- Sauvegardes locales Restic (3 min)
- Pourquoi Restic ? Deduplication, chiffrement AES-256, verification d'integrite
- **Loop device** : simuler un disque separe pour le depot
- **Ce qui est sauvegarde** : dumps SQL (mysqldump, pg_dump) + volumes Docker + config Docker
- **Politique de retention** : `--keep-daily 7 --keep-weekly 4 --keep-monthly 12`
- **Securite** : mot de passe via `RESTIC_PASSWORD_FILE`, jamais en clair

> **A montrer** : ouvrir le terminal et lancer `restic snapshots` pour montrer les snapshots existants

---

### Personne 2 -- Externalisation et Automatisation (7 min)

#### Etape 3 -- Externalisation S3 (3 min)
- **Option A retenue** : MinIO auto-heberge (expliquer le choix vs cloud public)
- Comment ca marche : `restic copy` du depot local vers le bucket S3
- **Comparaison Options A vs B** : cout, souverainete, complexite, performance
- Montrer l'interface MinIO (http://localhost:9001) avec le bucket `restic-bucket`

#### Etape 4 -- Automatisation et supervision (4 min)
- **Script orchestrateur** : expliquer le flux en 7 etapes (dump > stop > backup > replicate > retain > check > restart)
- **Rapport JSON** : genere a chaque execution
- **Timer systemd** : sauvegarde automatique chaque nuit a 02h00
- **Stack de monitoring** : Prometheus + Pushgateway + Grafana + Alertmanager
- **Metriques exposees** : timestamp, duree, taille, integrite

> **A montrer** : ouvrir Grafana (http://localhost:3000) et montrer le dashboard "Sauvegardes Restic" avec les 4 panneaux

- **Alertes** : BackupGaps (>25h sans backup), IntegrityFailure (check echoue)

---

### Personne 3 -- Tests, DRP et Demo live (10 min)

#### Etape 5 -- Tests de restauration (3 min)
- Presenter les 3 scenarios testes :

| Scenario | Description | RTO mesure | RTO cible |
|----------|-------------|-----------|-----------|
| 1 | Restauration partielle (fichier) | **2s** | 1800s |
| 2 | Restauration BDD MariaDB | **28s** | 1800s |
| 3 | Restauration complete BookStack | **52s** | 1800s |

- Point cle : "Tous les RTO sont largement inferieurs a la cible de 30 min"
- Les procedures sont redigees en anglais, pas-a-pas, pour un operateur

#### Etape 6 -- DRP (2 min)
- Presenter les 7 sections du document :
  Executive Summary, Risk Assessment, Backup Strategy, Recovery Procedures, RTO/RPO Summary, Lessons Learned, Architecture Diagram
- Insister sur les **Lessons Learned** :
  - Le RPO effectif est 24h (1 backup/jour) alors que la cible etait 1h --> amelioration possible
  - L'automatisation des tests de restauration serait un plus

#### Demo live (5 min)

> [!IMPORTANT]
> C'est le moment le plus important de la soutenance. Le sujet demande explicitement une "demonstration live de restauration d'un service detruit"

**Avant la demo**, s'assurer que tout tourne :
```bash
docker compose -f docker/docker-compose.yml up -d
```

**Script de demo a suivre :**

**1. Montrer que BookStack fonctionne (30s)**
```bash
# Ouvrir BookStack dans le navigateur
curl -I http://localhost:6875
# --> 302 Found, le service est UP
```
Ouvrir http://localhost:6875 dans le navigateur et montrer une page

**2. Montrer qu'on a des sauvegardes (30s)**
```bash
docker compose -f docker/docker-compose.yml run --rm --no-deps \
  --entrypoint restic backup_agent \
  -r /backup_repo snapshots
```

**3. DESTRUCTION : supprimer BookStack + MariaDB (30s)**
```bash
# Arreter et supprimer les conteneurs et volumes
docker compose -f docker/docker-compose.yml stop bookstack db
docker compose -f docker/docker-compose.yml rm -sf bookstack db
docker volume rm docker_bookstack_files docker_db_data
```
Commenter : "On vient de detruire entierement le service : conteneurs ET donnees persistantes"

Montrer que ca ne marche plus :
```bash
curl -I http://localhost:6875
# --> Connection refused
```

**4. RESTAURATION depuis Restic (2 min)**
```bash
# Restaurer les donnees depuis le dernier snapshot
rm -rf /tmp/full_restore && mkdir -p /tmp/full_restore

docker compose -f docker/docker-compose.yml run --rm --no-deps \
  -v /tmp/full_restore:/restore \
  --entrypoint restic backup_agent \
  -r /backup_repo restore latest \
  --target /restore \
  --include /data/bookstack --include /data/db_data

# Recreer les volumes
docker volume create docker_bookstack_files
docker volume create docker_db_data

# Recopier les donnees
docker run --rm -v docker_bookstack_files:/target -v /tmp/full_restore/data/bookstack:/source alpine sh -c 'cp -a /source/. /target/'
docker run --rm -v docker_db_data:/target -v /tmp/full_restore/data/db_data:/source alpine sh -c 'cp -a /source/. /target/'

# Relancer les services
docker compose -f docker/docker-compose.yml up -d db
sleep 15
docker compose -f docker/docker-compose.yml up -d bookstack
sleep 15
```

**5. VERIFICATION : BookStack est de retour (30s)**
```bash
curl -I http://localhost:6875
# --> 302 Found, service restaure !
```
Ouvrir http://localhost:6875 dans le navigateur et montrer que les donnees sont la

Commenter : "Service restaure en moins d'une minute, largement dans notre cible RTO de 30 minutes"

---

## Conseils pour la soutenance

### Avant la soutenance
- [ ] Lancer `docker compose -f docker/docker-compose.yml up -d` au moins 10 min avant
- [ ] Lancer une sauvegarde : `docker compose -f docker/docker-compose.yml run --rm backup_agent`
- [ ] Verifier que Grafana affiche des donnees : http://localhost:3000
- [ ] Verifier que BookStack fonctionne : http://localhost:6875
- [ ] Avoir les onglets navigateur pre-ouverts : BookStack, Grafana, MinIO
- [ ] Avoir un terminal pret dans le dossier `~/SAE_S6`

### Pendant la soutenance
- **Ne pas lire les slides** : chacun connait sa partie et l'explique naturellement
- **Commenter la demo en temps reel** : expliquer chaque commande pendant qu'elle s'execute
- **Les `sleep 15`** : profiter de l'attente pour commenter ce qui se passe en arriere-plan ("MariaDB est en train de demarrer et verifier l'integrite des fichiers InnoDB")

### Questions probables du jury
1. "Pourquoi Restic plutot que Borg, rsync, ou Duplicity ?"
   --> Deduplication, chiffrement natif, support S3, verification d'integrite integree
2. "Pourquoi MinIO plutot qu'un vrai cloud ?"
   --> Souverainete des donnees, cout zero, meme API S3 donc migration transparente
3. "Le RPO effectif est 24h mais la cible est 1h, comment corriger ?"
   --> Augmenter la frequence du timer systemd (toutes les heures au lieu de chaque nuit)
4. "Que se passe-t-il si le depot Restic est lui-meme corrompu ?"
   --> `restic check` detecte la corruption + copie distante sur MinIO = 2eme source
5. "Comment securiser le mot de passe Restic ?"
   --> `RESTIC_PASSWORD_FILE` avec permissions 600, jamais en clair dans les scripts
