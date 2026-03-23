# Scenario 3 - Full restore of the BookStack service

## Purpose

Restore the full BookStack service after total destruction of its containers and persistent volumes, including Docker configuration and persistent data, and measure the effective RTO. This procedure corresponds to the full service restoration scenario required by the project.

## Prerequisites

- The operator is located in: `~/SAE_S6/docker`
- Docker Compose is installed and operational
- Snapshot `b0c74d3c` exists
- The correct Docker volume names are:
  - `docker_bookstack_files`
  - `docker_db_data`
- The MariaDB root password is `secret_pass`
- The expected SQL marker count for `SAE_RESTORE_DB_TEST` is `2`
- The expected restored file content is `SCENARIO1_OK`

## Restoration steps

1. Stop the `bookstack` and `db` services:

```bash
docker compose stop bookstack db
```

2. Remove the BookStack and MariaDB containers:

```bash
docker compose rm -sf bookstack db
```

3. Remove the persistent volumes:

```bash
docker volume rm "docker_bookstack_files" "docker_db_data"
```

4. Start the RTO timer:

```bash
START=$(date +%s)
```

5. Prepare the temporary full restore directory:

```bash
rm -rf /tmp/full_restore && mkdir -p /tmp/full_restore
```

6. Restore BookStack data, MariaDB data, and Docker configuration from Restic:

```bash
docker compose run --rm --no-deps -v /tmp/full_restore:/restore --entrypoint restic backup_agent -r /backup_repo restore b0c74d3c --target /restore --include /data/bookstack --include /data/db_data --include /project/docker
```

7. Verify that the restored directories are present:

```bash
ls -ld /tmp/full_restore/data/bookstack
ls -ld /tmp/full_restore/data/db_data
ls -l /tmp/full_restore/project/docker
```

8. Recreate the Docker volumes:

```bash
docker volume create "docker_bookstack_files"
docker volume create "docker_db_data"
```

9. Copy restored BookStack data back into the BookStack volume:

```bash
docker run --rm -v "docker_bookstack_files":/target -v /tmp/full_restore/data/bookstack:/source alpine sh -c 'cp -a /source/. /target/'
```

10. Copy restored MariaDB data back into the MariaDB volume:

```bash
docker run --rm -v "docker_db_data":/target -v /tmp/full_restore/data/db_data:/source alpine sh -c 'cp -a /source/. /target/'
```

11. Restore the Docker configuration files into the current project Docker directory:

```bash
cp -a /tmp/full_restore/project/docker/. .
```

12. Start MariaDB:

```bash
docker compose up -d db
```

13. Wait for MariaDB initialization:

```bash
sleep 20
```

14. Start BookStack:

```bash
docker compose up -d bookstack
```

15. Wait for BookStack initialization:

```bash
sleep 20
```

16. Verify HTTP availability:

```bash
curl -I http://localhost:6875
```

17. Verify SQL data restoration:

```bash
docker compose exec db mariadb -uroot -psecret_pass -e "SELECT COUNT(*) AS marker_count FROM bookstack.entities WHERE name='SAE_RESTORE_DB_TEST';"
```

18. Verify file restoration:

```bash
docker compose exec bookstack sh -c 'ls -l /config/restore-tests && cat /config/restore-tests/s1_marker.txt'
```

19. Stop the timer:

```bash
END=$(date +%s)
```

20. Calculate the effective RTO:

```bash
RTO=$((END-START))
echo "RTO scenario 3 = ${RTO} seconds"
```

21. Display the RTO target for comparison:

```bash
echo "Target RTO = 1800 seconds"
```

## Verification steps

- Confirm that BookStack responds with `302 Found` to `/login` or `200 OK`
- Confirm that the SQL marker count returns to `2`
- Confirm that `/config/restore-tests/s1_marker.txt` exists and contains `SCENARIO1_OK`

## Success criteria

- BookStack and MariaDB are fully recreated
- Restored data is usable
- Docker configuration is restored from backup
- The application is reachable again
- The SQL and file markers are successfully recovered
- The measured RTO is recorded and compared to the target

## Measured RTO

**52 seconds**

