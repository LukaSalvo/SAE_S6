#!/bin/bash
# =============================================================================
# backup_script.sh — Agent de sauvegarde Restic
#
# Variables d'environnement requises (injectées par Docker Compose) :
#   RESTIC_REPOSITORY       chemin vers le dépôt Restic
#   RESTIC_PASSWORD_FILE    chemin vers le fichier de mot de passe
#   MYSQL_HOST              hôte MariaDB
#   MYSQL_ROOT_PASSWORD     mot de passe root MariaDB
#   POSTGRES_HOST           hôte PostgreSQL
#   POSTGRES_USER           utilisateur PostgreSQL
#   POSTGRES_PASSWORD       mot de passe PostgreSQL
#   POSTGRES_DB             base de données PostgreSQL à sauvegarder
# =============================================================================

set -euo pipefail

DUMP_DIR="/tmp/dumps"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

echo "============================================================"
echo " Démarrage de la sauvegarde — $(date)"
echo " Dépôt Restic : ${RESTIC_REPOSITORY}"
echo "============================================================"

# ─────────────────────────────────────────────────────────────────────────────
# 1. Initialisation du dépôt Restic (si non existant)
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "[1/5] Vérification / initialisation du dépôt Restic..."

if restic snapshots &>/dev/null; then
    echo "      ✔ Dépôt déjà initialisé."
else
    echo "      ℹ  Dépôt absent — initialisation en cours..."
    restic init
    echo "      ✔ Dépôt initialisé avec succès."
fi

# ─────────────────────────────────────────────────────────────────────────────
# 2. Dump des bases de données
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "[2/5] Extraction des bases de données..."

mkdir -p "${DUMP_DIR}"

# — MariaDB (mysqldump) --------------------------------------------------------
MYSQL_DUMP="${DUMP_DIR}/mariadb_${TIMESTAMP}.sql"
echo "      → mysqldump vers ${MYSQL_DUMP}"
mysqldump \
    --host="${MYSQL_HOST}" \
    --user=root \
    --password="${MYSQL_ROOT_PASSWORD}" \
    --all-databases \
    --single-transaction \
    --quick \
    > "${MYSQL_DUMP}"
echo "      ✔ Dump MariaDB terminé ($(du -sh "${MYSQL_DUMP}" | cut -f1))."

# — PostgreSQL (pg_dump) -------------------------------------------------------
PG_DUMP="${DUMP_DIR}/postgres_${TIMESTAMP}.sql"
echo "      → pg_dump vers ${PG_DUMP}"
PGPASSWORD="${POSTGRES_PASSWORD}" pg_dump \
    --host="${POSTGRES_HOST}" \
    --username="${POSTGRES_USER}" \
    --dbname="${POSTGRES_DB}" \
    --format=plain \
    --no-password \
    > "${PG_DUMP}"
echo "      ✔ Dump PostgreSQL terminé ($(du -sh "${PG_DUMP}" | cut -f1))."

# ─────────────────────────────────────────────────────────────────────────────
# 3. Sauvegarde Restic — dumps BDD + volumes Docker
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "[3/5] Sauvegarde Restic..."

restic backup \
    "${DUMP_DIR}" \
    /data/bookstack \
    /data/db_data \
    /data/postgres_data \
    --tag "daily_backup" \
    --tag "timestamp_${TIMESTAMP}"

echo "      ✔ Sauvegarde Restic terminée."

# Nettoyage des dumps temporaires
rm -f "${DUMP_DIR}"/*.sql
echo "      ✔ Dumps temporaires supprimés."

# ─────────────────────────────────────────────────────────────────────────────
# 4. Politique de rétention
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "[4/5] Application de la politique de rétention..."

restic forget \
    --keep-daily   7 \
    --keep-weekly  4 \
    --keep-monthly 12 \
    --prune

echo "      ✔ Politique de rétention appliquée."

# ─────────────────────────────────────────────────────────────────────────────
# 5. Vérification d'intégrité du dépôt
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "[5/5] Vérification d'intégrité du dépôt..."

restic check

echo ""
echo "============================================================"
echo " Sauvegarde terminée avec succès — $(date)"
echo "============================================================"