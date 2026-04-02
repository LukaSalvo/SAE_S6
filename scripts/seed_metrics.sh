#!/bin/bash
# =============================================================================
# seed_metrics.sh -- Injecte des metriques de demonstration dans le Pushgateway
# pour que les dashboards Grafana affichent des donnees.
#
# Ce script simule un historique de sauvegardes reussies en poussant
# des metriques a intervalles reguliers.
# =============================================================================

set -e

PUSHGATEWAY_URL="${PUSHGATEWAY_URL:-http://localhost:9091}"
JOB_NAME="restic_backup"

push_metrics() {
    local timestamp_seconds=$1
    local duration=$2
    local size_bytes=$3
    local integrity=$4

    cat <<EOF | curl --silent --data-binary @- "${PUSHGATEWAY_URL}/metrics/job/${JOB_NAME}"
# HELP restic_last_backup_timestamp_seconds Horodatage de la derniere sauvegarde reussie.
# TYPE restic_last_backup_timestamp_seconds gauge
restic_last_backup_timestamp_seconds{status="success"} ${timestamp_seconds}
# HELP restic_backup_duration_seconds Duree totale de la sauvegarde en secondes.
# TYPE restic_backup_duration_seconds gauge
restic_backup_duration_seconds ${duration}
# HELP restic_backup_size_bytes Taille totale du depot Restic.
# TYPE restic_backup_size_bytes gauge
restic_backup_size_bytes ${size_bytes}
# HELP restic_integrity_status Statut du dernier check d'integrite (0=OK, 1=Erreur).
# TYPE restic_integrity_status gauge
restic_integrity_status ${integrity}
EOF
}

echo "=== Seed Metrics : injection des donnees dans le Pushgateway ==="
echo "    Cible : ${PUSHGATEWAY_URL}"

# -- Attendre que le Pushgateway soit pret --
echo "[1/3] Attente du Pushgateway..."
for i in $(seq 1 30); do
    if curl --silent --fail "${PUSHGATEWAY_URL}/-/healthy" > /dev/null 2>&1; then
        echo "      [OK] Pushgateway disponible."
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo "      [ERREUR] Pushgateway non disponible apres 30 tentatives."
        exit 1
    fi
    sleep 2
done

# -- Pousser un premier jeu de metriques realistes --
NOW=$(date +%s)
echo "[2/3] Injection des metriques initiales..."
push_metrics "$NOW" 42 52428800 0
echo "      [OK] Metriques initiales poussees."
echo "           - Timestamp derniere sauvegarde : $(date -d @${NOW} 2>/dev/null || date -r ${NOW} 2>/dev/null || echo ${NOW})"
echo "           - Duree : 42s"
echo "           - Taille depot : 50 Mo"
echo "           - Integrite : OK (0)"

# -- Boucle de rafraichissement pour generer un historique Prometheus --
echo "[3/3] Boucle de rafraichissement (toutes les 60s) pour generer un historique..."
echo "      (Ctrl+C pour arreter)"

CYCLE=0
while true; do
    sleep 60
    CYCLE=$((CYCLE + 1))
    NOW=$(date +%s)

    # Simuler une legere variation de duree (35-55s) et de taille (+~100Ko/cycle)
    DURATION=$(( 35 + RANDOM % 21 ))
    SIZE_BYTES=$(( 52428800 + CYCLE * 102400 ))

    push_metrics "$NOW" "$DURATION" "$SIZE_BYTES" 0
    echo "      [cycle ${CYCLE}] Metriques mises a jour (duree=${DURATION}s, taille=$(( SIZE_BYTES / 1048576 ))Mo)"
done
