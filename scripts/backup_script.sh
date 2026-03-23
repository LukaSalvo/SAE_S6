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
# 1. Initialisation des dépôts Restic (Local + Remote)
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "[1/5] 🛠️  Vérification / initialisation des dépôts Restic..."

# — Dépôt Local —
if restic -r "${RESTIC_REPOSITORY}" snapshots >/dev/null 2>&1; then
    echo "      ✔ Dépôt LOCAL déjà initialisé."
else
    echo "      ℹ  Dépôt LOCAL absent — initialisation..."
    restic -r "${RESTIC_REPOSITORY}" init
    echo "      ✔ Dépôt LOCAL initialisé."
fi

# — Dépôt Remote (S3) —
if restic -r "${RESTIC_REMOTE_REPOSITORY}" snapshots >/dev/null 2>&1; then
    echo "      ✔ Dépôt REMOTE (S3) déjà initialisé."
else
    echo "      ℹ  Dépôt REMOTE (S3) absent — initialisation..."
    restic -r "${RESTIC_REMOTE_REPOSITORY}" init
    echo "      ✔ Dépôt REMOTE (S3) initialisé."
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
# 3. Sauvegarde Restic — Double destination (L/R)
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "[3/5] 💾 Sauvegardes Restic en cours..."

# — SAUVEGARDE LOCALE —
echo "      → Sauvegarde vers le dépôt LOCAL..."
restic -r "${RESTIC_REPOSITORY}" backup \
    "${DUMP_DIR}" \
    /data/bookstack \
    /data/db_data \
    /data/postgres_data \
    --tag "sae_local" \
    --tag "${TIMESTAMP}"

# — RÉPLICATION DISTANTE (S3) —
# Note: On utilise 'copy' pour répliquer les snapshots du dépôt local vers le remote
echo "      → Réplication vers le dépôt REMOTE (S3)..."
restic -r "${RESTIC_REMOTE_REPOSITORY}" copy \
    --from-repo "${RESTIC_REPOSITORY}" \
    --from-password-file "${RESTIC_PASSWORD_FILE}" \
    --tag "sae_local"

echo "      ✔ Sauvegardes terminées."

# Nettoyage des dumps temporaires
rm -f "${DUMP_DIR}"/*.sql

# ─────────────────────────────────────────────────────────────────────────────
# 4. Politique de rétention sur les deux dépôts
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "[4/5] 🧹 Application de la politique de rétention..."

for repo in "${RESTIC_REPOSITORY}" "${RESTIC_REMOTE_REPOSITORY}"; do
    echo "      → Pruning sur ${repo}..."
    restic -r "${repo}" forget \
        --keep-daily 7 \
        --keep-weekly 4 \
        --keep-monthly 12 \
        --prune >/dev/null
done

echo "      ✔ Nettoyage terminé."

# ─────────────────────────────────────────────────────────────────────────────
# 5. Vérification d'intégrité
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "[5/5] 🔍 Vérification d'intégrité des dépôts..."

for repo in "${RESTIC_REPOSITORY}" "${RESTIC_REMOTE_REPOSITORY}"; do
    echo "      → Check sur ${repo}..."
    restic -r "${repo}" check
done

echo ""
echo "============================================================"
echo " ✅ Sauvegarde et Réplication terminées avec succès — $(date)"
echo "============================================================"