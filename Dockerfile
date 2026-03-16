# Dockerfile.backup
FROM alpine:3.19

# Installation de restic et du client mariadb pour les dumps
RUN apk add --no-cache \
    restic \
    mariadb-client \
    bash \
    tzdata

# Création du répertoire de travail et du point de montage pour le dépôt
RUN mkdir -p /data /backup_repo /scripts

WORKDIR /scripts

# Copie du script de backup (voir étape suivante)
COPY backup_script.sh .
RUN chmod +x backup_script.sh

ENTRYPOINT ["./backup_script.sh"]