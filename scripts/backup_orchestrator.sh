#!/bin/bash
# =============================================================================
# backup_orchestrator.sh — Orchestrateur de sauvegarde Restic avec supervision
# =============================================================================

set -e

# Configuration
PROJECT_DIR="/Users/lukasalvo/Documents/BUT/3_Annee/SAE/SAE_S6"
BACKUP_SCRIPT="${PROJECT_DIR}/scripts/backup_script.sh"
REPORT_DIR="${PROJECT_DIR}/rapports"
PUSHGATEWAY_URL="http://localhost:9091/metrics/job/restic_backup"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
REPORT_FILE="${REPORT_DIR}/report_${TIMESTAMP}.json"

# Configuration Restic pour l'orchestrateur (Host)
export RESTIC_REPOSITORY="${PROJECT_DIR}/my_restic_repo"
export RESTIC_REMOTE_REPOSITORY="s3:http://localhost:9000/restic-bucket"
export RESTIC_PASSWORD_FILE="${PROJECT_DIR}/restic_password.txt"
export AWS_ACCESS_KEY_ID="minioadmin"
export AWS_SECRET_ACCESS_KEY="minioadmin"

# Liste des conteneurs à arrêter
CONTAINERS=("bookstack" "mariadb" "postgres")

echo "--- Démarrage de l'orchestration ---"
START_TIME=$(date +%s)

# 1. Dumps des bases de données (Pendant que les conteneurs tournent)
echo "Extracting database dumps via docker exec..."
mkdir -p /tmp/dumps
docker exec mariadb mysqldump -uroot -psecret_pass --all-databases --single-transaction --quick > /tmp/dumps/mariadb_${TIMESTAMP}.sql
docker exec postgres pg_dump -U pguser -d pgdb > /tmp/dumps/postgres_${TIMESTAMP}.sql

# 2. Arrêt des conteneurs (Pour cohérence des fichiers de données)
echo "Stopping containers: ${CONTAINERS[*]}..."
for container in "${CONTAINERS[@]}"; do
    docker stop "$container" || echo "Warning: Could not stop $container"
done

# 3. Exécution de Restic (Depuis le Host)
echo "Running Restic backup from host..."
STATUS=0
{
  # c) Sauvegarde locale
  restic -r "${RESTIC_REPOSITORY}" backup /tmp/dumps "${PROJECT_DIR}/docker" --tag "sae_local" --tag "${TIMESTAMP}"
  # d) Réplication
  restic -r "${RESTIC_REMOTE_REPOSITORY}" copy --from-repo "${RESTIC_REPOSITORY}" --from-password-file "${RESTIC_PASSWORD_FILE}" --tag "sae_local"
  # e) Rétention
  restic -r "${RESTIC_REPOSITORY}" forget --keep-daily 7 --keep-weekly 4 --keep-monthly 12 --prune
  restic -r "${RESTIC_REMOTE_REPOSITORY}" forget --keep-daily 7 --keep-weekly 4 --keep-monthly 12 --prune
  # f) Vérification
  restic -r "${RESTIC_REPOSITORY}" check
  restic -r "${RESTIC_REMOTE_REPOSITORY}" check
} || STATUS=1

# 4. Redémarrage des conteneurs
echo "Starting containers..."
for container in "${CONTAINERS[@]}"; do
    docker start "$container" || echo "Warning: Could not start $container"
done

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# 4. Génération du rapport JSON
mkdir -p "${REPORT_DIR}"
cat <<EOF > "${REPORT_FILE}"
{
  "date": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "status": "$([ $STATUS -eq 0 ] && echo "success" || echo "failure")",
  "duration_seconds": $DURATION,
  "snapshot_tags": ["sae_local", "${TIMESTAMP}"],
  "errors": "$([ $STATUS -eq 1 ] && echo "Check logs for details" || echo "none")"
}
EOF

# 5. Exposition des métriques Prometheus (Pushgateway)
INTEGRITY_STATUS=$STATUS # 0 = OK, 1 = Error
# Utilisation de du -sk pour une meilleure portabilité (Mac/Linux)
SNAPSHOT_SIZE=$(du -sk "${PROJECT_DIR}/my_restic_repo" | awk '{print $1 * 1024}' || echo 0)

cat <<EOF | curl --data-binary @- "${PUSHGATEWAY_URL}"
# HELP restic_last_backup_timestamp_seconds Last transition of backup state to success.
# TYPE restic_last_backup_timestamp_seconds gauge
restic_last_backup_timestamp_seconds{status="success"} $([ $STATUS -eq 0 ] && echo $END_TIME || echo 0)
# HELP restic_backup_duration_seconds Duration of the backup process in seconds.
# TYPE restic_backup_duration_seconds gauge
restic_backup_duration_seconds $DURATION
# HELP restic_backup_size_bytes Total size of the Restic repository.
# TYPE restic_backup_size_bytes gauge
restic_backup_size_bytes $SNAPSHOT_SIZE
# HELP restic_integrity_status Status of the last integrity check (0=OK, 1=Error).
# TYPE restic_integrity_status gauge
restic_integrity_status $INTEGRITY_STATUS
EOF

echo "--- Orchestration terminée (Status: $STATUS) ---"
echo "Rapport généré: ${REPORT_FILE}"
