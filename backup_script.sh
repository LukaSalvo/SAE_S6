#!/bin/bash

# Configuration via variables d'environnement
# RESTIC_REPOSITORY et RESTIC_PASSWORD_FILE seront passés par Docker Compose

echo "--- Démarrage de la sauvegarde $(date) ---"

# 1. Dump de la base de données MariaDB
echo "Extraction de la base de données..."
mysqldump -h db_host -u root -p${MYSQL_ROOT_PASSWORD} --all-databases > /tmp/db_dump.sql

# 2. Sauvegarde Restic (Dump + Volumes de fichiers)
# On sauvegarde le dump et le dossier /data (où on montera les volumes Docker)
restic backup /tmp/db_dump.sql /data --tag "daily_backup"

# 3. Nettoyage du dump temporaire
rm /tmp/db_dump.sql

# 4. Politique de rétention (Keep-daily 7, etc.)
echo "Application de la politique de rétention..."
restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 12 --prune

# 5. Vérification d'intégrité
echo "Vérification du dépôt..."
restic check

echo "--- Sauvegarde terminée avec succès ---"