#!/bin/bash
# =============================================================================
# init_loop_device.sh — Simulation d'un disque de sauvegarde séparé
#
# Ce script montre comment créer un vrai loop device Linux pour simuler
# un disque physique dédié aux sauvegardes (comme demandé dans le sujet SAE).
#
# Dans notre environnement Docker sur macOS, on simule ce comportement en
# montant un dossier local (./my_restic_repo) comme volume dans le conteneur.
# Sur un serveur Linux réel, ce script permet d'aller plus loin.
#
# USAGE (Linux uniquement, en root) :
#   sudo bash init_loop_device.sh
# =============================================================================

set -euo pipefail

LOOP_FILE="/var/backup_disk.img"   # Image disque à créer
LOOP_MOUNT="/mnt/backup"           # Point de montage
LOOP_SIZE_MB=500                   # Taille en Mo

echo "[1/5] Création de l'image disque de ${LOOP_SIZE_MB} Mo..."
dd if=/dev/zero of="${LOOP_FILE}" bs=1M count="${LOOP_SIZE_MB}" status=progress

echo "[2/5] Association avec un loop device..."
LOOP_DEV=$(losetup --find --show "${LOOP_FILE}")
echo "      Loop device : ${LOOP_DEV}"

echo "[3/5] Formatage en ext4..."
mkfs.ext4 -L "restic_backup" "${LOOP_DEV}"

echo "[4/5] Montage sur ${LOOP_MOUNT}..."
mkdir -p "${LOOP_MOUNT}"
mount "${LOOP_DEV}" "${LOOP_MOUNT}"

echo "[5/5] Ajout dans /etc/fstab pour la persistance au redémarrage..."
echo "${LOOP_FILE}  ${LOOP_MOUNT}  ext4  loop,defaults  0 0" >> /etc/fstab

echo ""
echo "✔ Loop device prêt : ${LOOP_DEV} monté sur ${LOOP_MOUNT}"
echo "  Ce dossier peut maintenant être utilisé comme RESTIC_REPOSITORY."
echo ""
echo "  Exemple :"
echo "    export RESTIC_REPOSITORY=${LOOP_MOUNT}/restic_repo"
echo "    export RESTIC_PASSWORD_FILE=/etc/restic/password"
echo "    restic init"
