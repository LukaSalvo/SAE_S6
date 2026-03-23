#!/bin/bash
# =============================================================================
# backup_script.sh — Agent de sauvegarde Restic pour infrastructure Docker
# =============================================================================

set -euo pipefail

# Configuration des répertoires
DUMP_DIR="/tmp/dumps"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

echo "============================================================"
echo " 🚀 Démarrage de la sauvegarde — $(date)"
echo " 📂 Dépôt Restic : ${RESTIC_REPOSITORY}"
echo " 🔑 Password file : ${RESTIC_PASSWORD_FILE}"
echo "============================================================"

# ─────────────────────────────────────────────────────────────────────────────
# 1. Initialisation du dépôt Restic (si non existant)
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "[1/5] 🛠️  Vérification / initialisation du dépôt Restic..."

if restic snapshots >/dev/null 2>&1; then
    echo "      ✔ Dépôt déjà initialisé."
else
    echo "      ℹ  Dépôt absent — initialisation en cours dans ${RESTIC_REPOSITORY}..."
    restic init
    echo "      ✔ Dépôt initialisé avec succès."
fi

# ─────────────────────────────────────────────────────────────────────────────
# 2. Dumps des bases de données
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "[2/5] 🗄️  Extraction des bases de données..."

mkdir -p "${DUMP_DIR}"

# --- MariaDB (mysqldump) ---
MYSQL_DUMP="${DUMP_DIR}/mariadb_${TIMESTAMP}.sql"
echo "      → mysqldump (MariaDB) vers ${MYSQL_DUMP}"
if mysqldump --host="${MYSQL_HOST}" --user=root --password="${MYSQL_ROOT_PASSWORD}" --all-databases --single-transaction --quick > "${MYSQL_DUMP}"; then
    echo "      ✔ Dump MariaDB terminé ($(du -sh "${MYSQL_DUMP}" | cut -f1))."
else
    echo "      ❌ Erreur lors du dump MariaDB."
    exit 1
fi

# --- PostgreSQL (pg_dump) ---
PG_DUMP="${DUMP_DIR}/postgres_${TIMESTAMP}.sql"
echo "      → pg_dump (PostgreSQL) vers ${PG_DUMP}"
if PGPASSWORD="${POSTGRES_PASSWORD}" pg_dump --host="${POSTGRES_HOST}" --username="${POSTGRES_USER}" --dbname="${POSTGRES_DB}" --format=plain --no-password > "${PG_DUMP}"; then
    echo "      ✔ Dump PostgreSQL terminé ($(du -sh "${PG_DUMP}" | cut -f1))."
else
    echo "      ❌ Erreur lors du dump PostgreSQL."
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# 3. Sauvegarde Restic — dumps + volumes applicatifs
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "[3/5] 💾 Sauvegarde Restic en cours..."

# On sauvegarde les dumps ainsi que les dossiers montés depuis les volumes Docker
restic backup \
    "${DUMP_DIR}" \
    /data/bookstack \
    /data/db_data \
    /data/postgres_data \
    --tag "sae_backup" \
    --tag "${TIMESTAMP}"

echo "      ✔ Sauvegarde Restic terminée."

# Nettoyage des dumps temporaires pour libérer de l'espace
rm -f "${DUMP_DIR}"/*.sql
echo "      ✔ Nettoyage des fichiers temporaires terminé."

# ─────────────────────────────────────────────────────────────────────────────
# 4. Politique de rétention (Règle de prune)
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "[4/5] 🧹 Application de la politique de rétention..."
echo "      Conservation : 7 jours, 4 semaines, 12 mois."

restic forget \
    --keep-daily 7 \
    --keep-weekly 4 \
    --keep-monthly 12 \
    --prune

echo "      ✔ Nettoyage des anciens snapshots terminé."

# ─────────────────────────────────────────────────────────────────────────────
# 5. Vérification d'intégrité
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "[5/5] 🔍 Vérification d'intégrité du dépôt..."

restic check

echo ""
echo "============================================================"
echo " ✅ Sauvegarde terminée avec succès — $(date)"
echo "============================================================"