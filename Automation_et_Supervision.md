# Automatisation et Supervision (Partie 5)

Ce document détaille la mise en œuvre de l'automatisation des sauvegardes et de leur supervision via une stack Prometheus/Grafana.

## 1. Orchestration des Sauvegardes
Le script orchestrateur [backup_orchestrator.sh](file:///Users/lukasalvo/Documents/BUT/3_Annee/SAE/SAE_S6/scripts/backup_orchestrator.sh) automatise le cycle de vie complet d'une sauvegarde :
1.  **Dump BDD** : Extraction à chaud via `docker exec`.
2.  **Arrêt des services** : `docker stop` pour garantir la cohérence des fichiers sur disque.
3.  **Sauvegarde Restic** : Backup local + réplication S3 (MinIO).
4.  **Redémarrage** : Relance des conteneurs applicatifs.
5.  **Reporting** : Génération d'un rapport JSON dans le dossier `rapports/`.
6.  **Métriques** : Envoi des données vers le **Pushgateway** pour Prometheus.

## 2. Automatisation (Systemd)
Pour rendre le processus autonome, deux fichiers `systemd` ont été créés :
-   **Service** : [backup-restic.service](file:///Users/lukasalvo/Documents/BUT/3_Annee/SAE/SAE_S6/systemd/backup-restic.service) (Exécute l'orchestrateur).
-   **Timer** : [backup-restic.timer](file:///Users/lukasalvo/Documents/BUT/3_Annee/SAE/SAE_S6/systemd/backup-restic.timer) (Déclenche le service chaque nuit à 02:00).

## 3. Supervision et Alerting
La stack de monitoring est déployée via Docker Compose et comprend :
-   **Prometheus** : Collecte les métriques poussées par le script.
-   **Pushgateway** : Point d'entrée pour les métriques de jobs éphémères (scripts).
-   **Grafana** : Affiche le tableau de bord "Sauvegardes Restic" (Access: Port 3000).
-   **Alertmanager** : Gère les notifications d'alerte.

### Alertes Configurées :
-   `BackupGaps` : Déclenchée si aucune sauvegarde réussie n'est détectée depuis plus de 25 heures.
-   `IntegrityFailure` : Déclenchée si le dernier `restic check` a échoué.

## 4. Vérification et Maintenance
-   **Voir les métriques brutes** : `curl http://localhost:9091/metrics`
-   **Vérifier le dernier rapport** : Consultez le dernier fichier JSON dans `rapports/`.
-   **Logs Systemd** : `journalctl -u backup-restic.service`
