#!/bin/bash
# =============================================================================
# backup_script.sh — Agent de sauvegarde Restic pour infrastructure Docker
# =============================================================================

set -euo pipefail

# Configuration des répertoires
DUMP_DIR="/tmp/dumps"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

echo "============================================================"
echo " Demarrage de la sauvegarde -- $(date)"
echo " Depot Restic : ${RESTIC_REPOSITORY}"
echo " Password file : ${RESTIC_PASSWORD_FILE}"
echo "============================================================"

# ─────────────────────────────────────────────────────────────────────────────
# 1. Initialisation des dépôts Restic (Local + Remote)
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "[1/5] Verification / initialisation des depots Restic..."

# — Dépôt Local —
if restic -r "${RESTIC_REPOSITORY}" snapshots >/dev/null 2>&1; then
    echo "      [OK] Depot LOCAL deja initialise."
else
    echo "      [INFO] Depot LOCAL absent -- initialisation..."
    restic -r "${RESTIC_REPOSITORY}" init
    echo "      [OK] Depot LOCAL initialise."
fi

# — Dépôt Remote (S3) —
if restic -r "${RESTIC_REMOTE_REPOSITORY}" snapshots >/dev/null 2>&1; then
    echo "      [OK] Depot REMOTE (S3) deja initialise."
else
    echo "      [INFO] Depot REMOTE (S3) absent -- initialisation..."
    restic -r "${RESTIC_REMOTE_REPOSITORY}" init
    echo "      [OK] Depot REMOTE (S3) initialise."
fi

# ─────────────────────────────────────────────────────────────────────────────
# 2. Dumps des bases de données
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "[2/5] Extraction des bases de donnees..."

mkdir -p "${DUMP_DIR}"

# --- MariaDB (mysqldump) ---
MYSQL_DUMP="${DUMP_DIR}/mariadb_${TIMESTAMP}.sql"
echo "      > mysqldump (MariaDB) vers ${MYSQL_DUMP}"
if mysqldump --host="${MYSQL_HOST}" --user=root --password="${MYSQL_ROOT_PASSWORD}" --all-databases --single-transaction --quick > "${MYSQL_DUMP}"; then
    echo "      [OK] Dump MariaDB termine ($(du -sh "${MYSQL_DUMP}" | cut -f1))."
else
    echo "      [ERREUR] Erreur lors du dump MariaDB."
    exit 1
fi

# --- PostgreSQL (pg_dump) ---
PG_DUMP="${DUMP_DIR}/postgres_${TIMESTAMP}.sql"
echo "      > pg_dump (PostgreSQL) vers ${PG_DUMP}"
if PGPASSWORD="${POSTGRES_PASSWORD}" pg_dump --host="${POSTGRES_HOST}" --username="${POSTGRES_USER}" --dbname="${POSTGRES_DB}" --format=plain --no-password > "${PG_DUMP}"; then
    echo "      [OK] Dump PostgreSQL termine ($(du -sh "${PG_DUMP}" | cut -f1))."
else
    echo "      [ERREUR] Erreur lors du dump PostgreSQL."
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# 3. Sauvegarde Restic — Double destination (L/R)
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "[3/5] Sauvegardes Restic en cours..."

# — SAUVEGARDE LOCALE —
echo "      > Sauvegarde vers le depot LOCAL..."

BACKUP_PATHS=(
    "${DUMP_DIR}"
    /data/bookstack
    /data/db_data
    /data/postgres_data
    /project/docker
)

# Sauvegarde facultative du .env s'il existe
if [ -f /project/.env ]; then
    BACKUP_PATHS+=( /project/.env )
fi

restic -r "${RESTIC_REPOSITORY}" backup \
    "${BACKUP_PATHS[@]}" \
    --tag "sae_local" \
    --tag "${TIMESTAMP}"

# — RÉPLICATION DISTANTE (S3) —
# Note: On utilise 'copy' pour répliquer les snapshots du dépôt local vers le remote
echo "      > Replication vers le depot REMOTE (S3)..."
restic -r "${RESTIC_REMOTE_REPOSITORY}" copy \
    --from-repo "${RESTIC_REPOSITORY}" \
    --from-password-file "${RESTIC_PASSWORD_FILE}" \
    --tag "sae_local"

echo "      [OK] Sauvegardes terminees."

# Nettoyage des dumps temporaires
rm -f "${DUMP_DIR}"/*.sql

# ─────────────────────────────────────────────────────────────────────────────
# 4. Politique de rétention sur les deux dépôts
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "[4/5] Application de la politique de retention..."

for repo in "${RESTIC_REPOSITORY}" "${RESTIC_REMOTE_REPOSITORY}"; do
    echo "      > Pruning sur ${repo}..."
    restic -r "${repo}" forget \
        --keep-daily 7 \
        --keep-weekly 4 \
        --keep-monthly 12 \
        --prune >/dev/null
done

echo "      [OK] Nettoyage termine."

# ─────────────────────────────────────────────────────────────────────────────
# 5. Vérification d'intégrité
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "[5/5] Verification d'integrite des depots..."

for repo in "${RESTIC_REPOSITORY}" "${RESTIC_REMOTE_REPOSITORY}"; do
    echo "      > Check sur ${repo}..."
    restic -r "${repo}" check
done

echo ""
echo "============================================================"
echo " [OK] Sauvegarde et Replication terminees avec succes -- $(date)"
echo "============================================================"
