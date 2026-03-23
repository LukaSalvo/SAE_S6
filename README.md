# SAÉ S6.B.01 – Plan de Reprise d'Activité (PRA)

**Projet tuteuré** – BUT Informatique 3A, Parcours DACS  
**Objectif** : Conception et mise en œuvre d'un PRA pour infrastructure conteneurisée (Docker)

---

## 📁 Structure du dépôt

```
SAE_S6/
├── docs/                           # Sujets et documents de référence
│   ├── s6_sujet_pra.pdf            #   Sujet officiel
│   ├── rapport_partie2_restic.pdf  #   Rapport PDF (Partie 2)
│   └── architecture.png            #   Diagramme d'architecture
│
├── rapports/                       # Rapports techniques (Markdown)
│   ├── partie1_analyse_strategie.md        # Étape 1 – Analyse & stratégie
│   ├── partie2_sauvegardes_restic.md       # Étape 2 – Sauvegardes locales
│   ├── partie3_externalisation.md          # Étape 3 – Externalisation S3/MinIO
│   └── partie3_comparaison_options.md      # Étape 3 – Comparaison A vs B
│
├── scripts/                        # Scripts opérationnels
│   ├── backup_script.sh            #   Script orchestrateur de sauvegarde
│   └── init_loop_device.sh         #   Initialisation du loop device (Linux)
│
├── docker/                         # Configuration Docker
│   ├── docker-compose.yml          #   Stack complète (MariaDB, PostgreSQL, BookStack, MinIO, Agent)
│   └── Dockerfile.backup           #   Image de l'agent de sauvegarde
│
├── systemd/                        # (À venir) Timer & service systemd
├── monitoring/                     # (À venir) Prometheus, Grafana, Alertmanager
│   ├── prometheus/
│   ├── grafana/
│   └── alertmanager/
└── drp/                            # (À venir) Disaster Recovery Plan
```

## 📊 Avancement

| # | Étape | Avancement |
|---|-------|------------|
| 1 | Analyse de l'existant et stratégie | ✅ Terminé |
| 2 | Sauvegardes locales avec Restic | ✅ Terminé |
| 3 | Externalisation vers stockage objet (MinIO) | ✅ Terminé |
| 4 | Automatisation et supervision | 🔲 À faire |
| 5 | Tests et procédures de restauration | 🔲 À faire |
| 6 | Disaster Recovery Plan (DRP) | 🔲 À faire |

---

## 🚀 Guide d'exécution par étape

### Étape 1 – Analyse de l'existant et stratégie

Cette étape est documentaire. Consulter le rapport :

```bash
cat rapports/partie1_analyse_strategie.md
```

Contenu : inventaire des données critiques, objectifs RPO/RTO, règle 3-2-1, scénarios d'incident.

---

### Étape 2 – Sauvegardes locales avec Restic

#### Prérequis
Créer le fichier de mot de passe Restic à la racine du projet :
```bash
echo "MonMotDePasseRestic2026!" > restic_password.txt
chmod 600 restic_password.txt
```

#### Démarrer l'infrastructure complète (BDD + BookStack)
```bash
cd docker/
docker compose up -d db postgres bookstack
```

#### Optionnel – Créer un loop device (Linux uniquement)
```bash
sudo bash scripts/init_loop_device.sh
```

#### Lancer une sauvegarde manuelle
```bash
cd docker/
docker compose run --rm backup_agent
```

#### Vérifier les snapshots et l'intégrité
```bash
cd docker/
docker compose run --rm backup_agent restic -r /backup_repo snapshots
docker compose run --rm backup_agent restic -r /backup_repo check
```

---

### Étape 3 – Externalisation vers MinIO (S3)

#### Démarrer MinIO + initialisation du bucket
```bash
cd docker/
docker compose up -d minio
docker compose run --rm minio-init
```

#### Accéder à l'interface MinIO
- URL : http://localhost:9001
- Login : `minioadmin` / `minioadmin`

#### Lancer une sauvegarde complète (locale + réplication S3)
```bash
cd docker/
docker compose run --rm backup_agent
```
Le script effectue automatiquement :
1. Dump des bases MariaDB et PostgreSQL
2. Sauvegarde Restic locale
3. Réplication vers MinIO via `restic copy`
4. Politique de rétention sur les deux dépôts
5. Vérification d'intégrité des deux dépôts

#### Vérifier les snapshots distants
```bash
cd docker/
docker compose run --rm backup_agent restic -r s3:http://minio:9000/restic-bucket snapshots
```

---

### Étape 4 – Automatisation et supervision *(à venir)*

```bash
# Installer le timer systemd
sudo cp systemd/backup.service /etc/systemd/system/
sudo cp systemd/backup.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now backup.timer
sudo systemctl list-timers
```

---

### Étape 5 – Tests de restauration *(à venir)*

```bash
# Scénario 1 – Restauration partielle (fichier supprimé)
restic -r /backup_repo restore latest --target /tmp/restore_test --include "/data/bookstack"

# Scénario 2 – Restauration BDD MariaDB
restic -r /backup_repo restore latest --target /tmp/restore_db --include "/tmp/dumps"
mysql -h db -u root -p < /tmp/restore_db/tmp/dumps/mariadb_*.sql

# Scénario 3 – Restauration complète d'un service
docker compose down && docker volume rm db_data bookstack_files
restic -r /backup_repo restore latest --target /tmp/full_restore
# Recréer les volumes et relancer
```

---

### Étape 6 – Disaster Recovery Plan *(à venir)*

Le DRP sera rédigé dans `drp/DRP.md` avec les sections : Executive Summary, Risk Assessment, Backup Strategy, Recovery Procedures, RTO/RPO Summary, Lessons Learned, Architecture Diagram.

---

## 🔧 Technologies

| Outil | Rôle |
|-------|------|
| **Restic** | Sauvegarde incrémentale chiffrée (AES-256) |
| **Docker Compose** | Orchestration des conteneurs |
| **MariaDB** | Base de données BookStack |
| **PostgreSQL** | Base de données secondaire |
| **BookStack** | Application wiki |
| **MinIO** | Stockage objet S3 auto-hébergé |
| **Prometheus / Grafana** | Supervision *(à venir)* |