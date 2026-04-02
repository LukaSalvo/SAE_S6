# SAE S6.B.01 -- Plan de Reprise d'Activite (PRA)

**Projet tutoure** -- BUT Informatique 3A, Parcours DACS
**Objectif** : Conception et mise en oeuvre d'un PRA pour infrastructure conteneurisee (Docker)

---

## Structure du depot

```
SAE_S6/
├── docs/                                    # Documents de reference
│   ├── s6_sujet_pra.pdf                     #   Sujet officiel
│   ├── rapport_partie2_restic.pdf           #   Rapport PDF (Partie 2)
│   └── architecture.png                     #   Diagramme d'architecture
│
├── rapports/                                # Rapports techniques (Markdown)
│   ├── partie1_analyse_strategie.md         #   Etape 1 -- Analyse & strategie
│   ├── partie2_sauvegardes_restic.md        #   Etape 2 -- Sauvegardes locales Restic
│   ├── partie3_externalisation.md           #   Etape 3 -- Externalisation S3/MinIO
│   ├── partie3_comparaison_options.md       #   Etape 3 -- Comparaison Option A vs B
│   ├── partie4_automation_supervision.md    #   Etape 4 -- Automatisation & supervision
│   ├── partie5_test_restauration.md         #   Etape 5 -- Tests de restauration (RTO)
│   └── partie6_drp.md                       #   Etape 6 -- Disaster Recovery Plan
│
├── scripts/                                 # Scripts operationnels
│   ├── backup_script.sh                     #   Agent de sauvegarde (execute dans le conteneur)
│   ├── backup_orchestrator.sh               #   Orchestrateur (execute depuis le host)
│   └── init_loop_device.sh                  #   Initialisation du loop device (Linux)
│
├── docker/                                  # Configuration Docker
│   ├── docker-compose.yml                   #   Stack complete (MariaDB, PostgreSQL, BookStack, MinIO, Monitoring)
│   └── Dockerfile.backup                    #   Image de l'agent de sauvegarde
│
├── systemd/                                 # Automatisation systemd
│   ├── backup-restic.service                #   Unite de service (oneshot)
│   └── backup-restic.timer                  #   Timer (chaque nuit a 02h00)
│
├── monitoring/                              # Stack de supervision
│   ├── prometheus.yml                       #   Configuration Prometheus
│   ├── alert_rules.yml                      #   Regles d'alertes (BackupGaps, IntegrityFailure)
│   ├── alertmanager.yml                     #   Configuration Alertmanager
│   └── grafana/
│       └── provisioning/                    #   Provisioning automatique (dashboards, datasources)
│
├── drp/                                     # Procedures de restauration (en anglais)
│   ├── 01_partial_restore.md                #   Scenario 1 -- Restauration partielle
│   ├── 02_mariadb_restore.md                #   Scenario 2 -- Restauration MariaDB
│   └── 03_full_service_restore.md           #   Scenario 3 -- Restauration complete
│
└── restic_password.txt                      # Mot de passe Restic (ne pas committer)
```

---

## Avancement

| # | Etape | Avancement |
|---|-------|------------|
| 1 | Analyse de l'existant et strategie | Termine |
| 2 | Sauvegardes locales avec Restic | Termine |
| 3 | Externalisation vers stockage objet (MinIO) | Termine |
| 4 | Automatisation et supervision | Termine |
| 5 | Tests et procedures de restauration | Termine |
| 6 | Disaster Recovery Plan (DRP) | Termine |

---

## Pre-requis

- **Docker** et **Docker Compose** installes
- **Git** installe
- Ports disponibles : `6875` (BookStack), `9000`/`9001` (MinIO), `9090` (Prometheus), `9091` (Pushgateway), `9093` (Alertmanager), `3000` (Grafana)

---

## Guide d'execution par etape

### Etape 1 -- Analyse de l'existant et strategie

Cette etape est documentaire. Consulter le rapport :

```bash
cat rapports/partie1_analyse_strategie.md
```

Contenu : inventaire des donnees critiques, objectifs RPO/RTO, regle 3-2-1, scenarios d'incident.

---

### Etape 2 -- Sauvegardes locales avec Restic

#### 2.1 Creer le fichier de mot de passe Restic

```bash
echo "MonMotDePasseRestic2026!" > restic_password.txt
chmod 600 restic_password.txt
```

#### 2.2 Demarrer l'infrastructure (BDD + BookStack)

```bash
docker compose -f docker/docker-compose.yml up -d db postgres bookstack
```

#### 2.3 (Optionnel) Creer un loop device pour simuler un disque separe

```bash
sudo bash scripts/init_loop_device.sh
```

#### 2.4 Lancer une sauvegarde manuelle via l'agent

```bash
docker compose -f docker/docker-compose.yml run --rm backup_agent
```

#### 2.5 Verifier les snapshots et l'integrite

```bash
docker compose -f docker/docker-compose.yml run --rm backup_agent restic -r /backup_repo snapshots
docker compose -f docker/docker-compose.yml run --rm backup_agent restic -r /backup_repo check
```

Rapport detaille : `rapports/partie2_sauvegardes_restic.md`

---

### Etape 3 -- Externalisation vers MinIO (S3)

#### 3.1 Demarrer MinIO et initialiser le bucket

```bash
docker compose -f docker/docker-compose.yml up -d minio
docker compose -f docker/docker-compose.yml run --rm minio-init
```

#### 3.2 Acceder a l'interface MinIO

- URL : http://localhost:9001
- Login : `minioadmin` / `minioadmin`

#### 3.3 Lancer une sauvegarde complete (locale + replication S3)

```bash
docker compose -f docker/docker-compose.yml run --rm backup_agent
```

Le script `backup_script.sh` execute automatiquement :
1. Dump des bases MariaDB (`mysqldump`) et PostgreSQL (`pg_dump`)
2. Sauvegarde Restic locale (volumes + dumps + config Docker)
3. Replication vers MinIO via `restic copy`
4. Politique de retention sur les deux depots (`--keep-daily 7 --keep-weekly 4 --keep-monthly 12 --prune`)
5. Verification d'integrite des deux depots (`restic check`)

#### 3.4 Verifier les snapshots distants

```bash
docker compose -f docker/docker-compose.yml run --rm backup_agent restic -r s3:http://minio:9000/restic-bucket snapshots
```

Rapports detailles : `rapports/partie3_externalisation.md` et `rapports/partie3_comparaison_options.md`

---

### Etape 4 -- Automatisation et supervision

#### 4.1 Demarrer la stack de monitoring

```bash
docker compose -f docker/docker-compose.yml up -d prometheus pushgateway alertmanager grafana seed_metrics
```

Le service `seed_metrics` injecte automatiquement des metriques de demonstration
dans le Pushgateway (toutes les 60s) pour que les dashboards Grafana affichent
des donnees sans avoir besoin de lancer une vraie sauvegarde.

Interfaces de supervision :
- **Prometheus** : http://localhost:9090
- **Pushgateway** : http://localhost:9091
- **Grafana** : http://localhost:3000 (login : `admin` / `admin`)
- **Alertmanager** : http://localhost:9093

#### 4.2 Installer le timer systemd (automatisation nocturne)

```bash
sudo cp systemd/backup-restic.service /etc/systemd/system/
sudo cp systemd/backup-restic.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now backup-restic.timer
```

#### 4.3 Verifier le timer

```bash
systemctl list-timers --all | grep backup-restic
```

#### 4.4 Lancer l'orchestrateur manuellement (pour tester)

```bash
bash scripts/backup_orchestrator.sh
```

L'orchestrateur realise dans l'ordre :
1. Dump des bases de donnees via `docker exec`
2. Arret propre des conteneurs (`docker stop`)
3. Sauvegarde Restic locale
4. Replication vers le stockage distant (MinIO/S3)
5. Politique de retention
6. Verification d'integrite (`restic check`)
7. Redemarrage des conteneurs
8. Generation d'un rapport JSON dans `rapports/`
9. Envoi des metriques vers le Pushgateway

#### 4.5 Metriques exposees

| Metrique | Description |
|----------|-------------|
| `restic_last_backup_timestamp_seconds` | Horodatage de la derniere sauvegarde reussie |
| `restic_backup_duration_seconds` | Duree de la sauvegarde |
| `restic_backup_size_bytes` | Taille du depot Restic local |
| `restic_integrity_status` | Statut d'integrite (0 = OK, 1 = erreur) |

#### 4.6 Alertes configurees

| Alerte | Condition |
|--------|-----------|
| `BackupGaps` | Aucune sauvegarde reussie depuis plus de 25 heures |
| `IntegrityFailure` | Echec de la verification d'integrite |

Rapport detaille : `rapports/partie4_automation_supervision.md`

---

### Etape 5 -- Tests et procedures de restauration

Les trois scenarios demandes par le sujet ont ete realises et documentes :

#### 5.1 Scenario 1 -- Restauration partielle d'un fichier

```bash
# Restaurer un fichier specifique depuis un snapshot
docker compose -f docker/docker-compose.yml run --rm --no-deps \
  -v /tmp/restore_partial:/restore \
  --entrypoint restic backup_agent \
  -r /backup_repo restore latest \
  --target /restore \
  --include /data/bookstack/restore-tests/s1_marker.txt

# Recopier le fichier dans le conteneur
docker cp /tmp/restore_partial/data/bookstack/restore-tests/s1_marker.txt bookstack:/config/restore-tests/
```

**RTO mesure : 2 secondes** (cible : 1800 s)

#### 5.2 Scenario 2 -- Restauration de la base MariaDB

```bash
# Restaurer le dump SQL depuis Restic
docker compose -f docker/docker-compose.yml run --rm --no-deps \
  -v /tmp/restore_db:/restore \
  --entrypoint restic backup_agent \
  -r /backup_repo restore latest \
  --target /restore \
  --include /tmp/dumps

# Trouver le dernier dump MariaDB
DUMP_FILE=$(find /tmp/restore_db/tmp/dumps -name 'mariadb_*.sql' | sort | tail -n 1)

# Reimporter dans MariaDB
cat "$DUMP_FILE" | docker compose -f docker/docker-compose.yml exec -T db mariadb -uroot -psecret_pass

# Redemarrer BookStack
docker compose -f docker/docker-compose.yml restart bookstack
```

**RTO mesure : 28 secondes** (cible : 1800 s)

#### 5.3 Scenario 3 -- Restauration complete du service BookStack

```bash
# Detruire les conteneurs et volumes
docker compose -f docker/docker-compose.yml stop bookstack db
docker compose -f docker/docker-compose.yml rm -sf bookstack db
docker volume rm docker_bookstack_files docker_db_data

# Restaurer depuis Restic
docker compose -f docker/docker-compose.yml run --rm --no-deps \
  -v /tmp/full_restore:/restore \
  --entrypoint restic backup_agent \
  -r /backup_repo restore latest \
  --target /restore \
  --include /data/bookstack --include /data/db_data --include /project/docker

# Recreer les volumes et y copier les donnees
docker volume create docker_bookstack_files
docker volume create docker_db_data
docker run --rm -v docker_bookstack_files:/target -v /tmp/full_restore/data/bookstack:/source alpine sh -c 'cp -a /source/. /target/'
docker run --rm -v docker_db_data:/target -v /tmp/full_restore/data/db_data:/source alpine sh -c 'cp -a /source/. /target/'

# Relancer les services
docker compose -f docker/docker-compose.yml up -d db
sleep 20
docker compose -f docker/docker-compose.yml up -d bookstack
```

**RTO mesure : 52 secondes** (cible : 1800 s)

#### Tableau comparatif des RTO

| Scenario | RTO mesure | RTO cible | Resultat |
|----------|-----------|-----------|----------|
| Restauration partielle | 2 s | 1800 s | OK |
| Restauration BDD MariaDB | 28 s | 1800 s | OK |
| Restauration complete BookStack | 52 s | 1800 s | OK |

Procedures detaillees (en anglais, pas-a-pas) : `drp/01_partial_restore.md`, `drp/02_mariadb_restore.md`, `drp/03_full_service_restore.md`

Rapport detaille : `rapports/partie5_test_restauration.md`

---

### Etape 6 -- Disaster Recovery Plan (DRP)

Le DRP complet est disponible dans `rapports/partie6_drp.md`. Il contient les sections suivantes, conformement au sujet :

1. **Executive Summary** -- Strategie, services couverts, objectifs RPO/RTO
2. **Risk Assessment** -- Tableau des risques (probabilite, impact, mitigations)
3. **Backup Strategy** -- Architecture 3-2-1, outils, frequences, retention
4. **Recovery Procedures** -- Procedures de restauration validees a l'etape 5
5. **RTO/RPO Summary Table** -- Recapitulatif par service
6. **Lessons Learned** -- Retour d'experience (reussites et ameliorations)
7. **Architecture Diagram** -- Schema de l'infrastructure de sauvegarde

---

## Demarrage rapide (stack complete)

Pour lancer l'ensemble de l'infrastructure en une seule commande :

```bash
# 1. Creer le fichier mot de passe Restic (si pas encore fait)
echo "MonMotDePasseRestic2026!" > restic_password.txt
chmod 600 restic_password.txt

# 2. Demarrer tous les services
docker compose -f docker/docker-compose.yml up -d

# 3. Lancer une premiere sauvegarde
docker compose -f docker/docker-compose.yml run --rm backup_agent
```

Acceder aux services :
- **BookStack** : http://localhost:6875
- **MinIO Console** : http://localhost:9001 (`minioadmin` / `minioadmin`)
- **Grafana** : http://localhost:3000 (`admin` / `admin`)
- **Prometheus** : http://localhost:9090
- **Alertmanager** : http://localhost:9093

---

## Technologies

| Outil | Role |
|-------|------|
| **Restic** | Sauvegarde incrementale chiffree (AES-256), deduplication |
| **Docker Compose** | Orchestration des conteneurs |
| **MariaDB** | Base de donnees BookStack |
| **PostgreSQL** | Base de donnees secondaire |
| **BookStack** | Application wiki |
| **MinIO** | Stockage objet S3 auto-heberge |
| **Prometheus** | Collecte des metriques de sauvegarde |
| **Pushgateway** | Point d'entree pour metriques de jobs ephemeres |
| **Grafana** | Tableau de bord de supervision |
| **Alertmanager** | Gestion des alertes (BackupGaps, IntegrityFailure) |
| **Systemd** | Automatisation des sauvegardes (timer nocturne) |

---

## Livrables attendus (sujet)

Conformite par rapport au sujet `s6_sujet_pra.pdf` :

| Livrable | Emplacement | Statut |
|----------|-------------|--------|
| Scripts de sauvegarde et de restauration | `scripts/` | Livre |
| Fichiers de configuration systemd (service + timer) | `systemd/` | Livre |
| Configurations Prometheus, Alertmanager et Grafana | `monitoring/` | Livre |
| Disaster Recovery Plan | `rapports/partie6_drp.md` | Livre |
| Rapport technique (commandes Restic, resultats RTO, comparaison stockage) | `rapports/` | Livre |
| Procedures de restauration pas-a-pas (en anglais) | `drp/` | Livre |