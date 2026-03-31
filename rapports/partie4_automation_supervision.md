# Partie 4 - Automatisation et Supervision des Sauvegardes

Ce document détaille la mise en œuvre de l'automatisation des sauvegardes Restic et de leur supervision en temps réel via une stack Prometheus/Grafana.

---

## 1. Script Orchestrateur (`backup_orchestrator.sh`)

Pour rendre le processus de sauvegarde autonome et robuste, un script orchestrateur a été développé. Il centralise toutes les étapes critiques et communique avec la stack de supervision.

### 1.1 Flux d'exécution
Le script execute les étapes suivantes dans l'ordre :
1. **Dump des bases de données** : Extraction à chaud de MariaDB et PostgreSQL via `docker exec`.
2. **Arrêt propre des conteneurs** : `docker stop` des services pour garantir la cohérence des fichiers de données sur le disque.
3. **Sauvegarde Restic locale** : Snapshots des dossiers de données et des dumps SQL vers le dépôt local.
4. **Réplication distante** : Copie (`restic copy`) du dépôt local vers un stockage S3 (MinIO).
5. **Politique de rétention** : Application des règles de nettoyage (`forget --prune`) sur les dépôts local et distant.
6. **Vérification d'intégrité** : Exécution de `restic check` pour détecter toute corruption.
7. **Redémarrage des conteneurs** : Relance immédiate des services applicatifs.
8. **Reporting & Métriques** : Génération d'un rapport JSON et envoi des métriques au Pushgateway.

### 1.2 Rapport JSON
Chaque exécution génère un fichier de rapport dans `rapports/report_[date].json` :
```json
{
  "date": "2026-03-31T12:00:00Z",
  "status": "success",
  "duration_seconds": 45,
  "snapshot_tags": ["sae_local", "20260331_120000"],
  "errors": "none"
}
```

---

## 2. Automatisation (Systemd)

Pour garantir que les sauvegardes s'exécutent sans intervention humaine, nous utilisons les unités **Systemd**.

- **Service (`backup-restic.service`)** : Unité de type `oneshot` qui exécute le script orchestrateur.
- **Timer (`backup-restic.timer`)** : Programme le lancement du service chaque nuit à **02h00**.

**Commande de vérification :**
```bash
systemctl list-timers --all | grep backup-restic
```

---

## 3. Supervision et Métriques (Prometheus)

Le script orchestrateur pousse des métriques vers le **Prometheus Pushgateway** à la fin de chaque job.

### 3.1 Métriques exposées
- `restic_last_backup_timestamp_seconds` : Horodatage de la dernière sauvegarde réussie.
- `restic_backup_duration_seconds` : Temps total d'exécution du script.
- `restic_backup_size_bytes` : Taille totale du dépôt Restic local (via `du`).
- `restic_integrity_status` : Statut du dernier `check` (0 = OK, 1 = Erreur).

---

## 4. Tableau de bord Grafana

Un dashboard personnalisé "Sauvegardes Restic" a été configuré pour visualiser ces métriques :
- **État d'intégrité** : Un indicateur visuel (Stat panel) passant au rouge en cas d'erreur.
- **Évolution de la durée** : Graphique temporel pour identifier d'éventuelles dérives de performance.
- **Taille du dépôt** : Suivi de la consommation disque et de l'efficacité de la déduplication.

---

## 5. Alerting (Alertmanager)

Deux alertes critiques ont été configurées dans `alert_rules.yml` pour garantir une réaction rapide en cas d'incident :

1. **BackupGaps** : Déclenchée si aucune sauvegarde réussie n'est détectée depuis plus de **25 heures**.
   - *Expression* : `(time() - restic_last_backup_timestamp_seconds{status="success"}) > 90000`
2. **IntegrityFailure** : Déclenchée immédiatement si le statut d'intégrité est différent de 0.
   - *Expression* : `restic_integrity_status != 0`

---

## Conclusion

Cette architecture rend le système de sauvegarde totalement autonome et "observable". En cas de défaillance (disque plein, erreur réseau vers S3, corruption), l'équipe technique est immédiatement alertée via Alertmanager, tout en disposant d'un historique complet via Grafana et les rapports JSON.
