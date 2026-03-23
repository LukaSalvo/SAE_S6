# Scenario 2 - MariaDB restore for BookStack

## Purpose

Restore the BookStack MariaDB database from a Restic-backed SQL dump after intentional deletion of the database, restart the application, and measure the effective RTO. This procedure corresponds to the database restore scenario required by the project.

## Prerequisites

- The operator is located in: `~/SAE_S6/docker`
- Docker Compose is installed and operational
- Snapshot `b0c74d3c` exists
- The `db` and `bookstack` services are available
- The MariaDB root password is `secret_pass`
- The reference SQL marker count for the test page name `SAE_RESTORE_DB_TEST` is `2`

## Restoration steps

1. Verify the reference marker count before the incident:

```bash
docker compose exec db mariadb -uroot -psecret_pass -e "SELECT COUNT(*) AS marker_count FROM bookstack.entities WHERE name='SAE_RESTORE_DB_TEST';"
```

2. Stop BookStack:

```bash
docker compose stop bookstack
```

3. Delete the BookStack database:

```bash
docker compose exec db mariadb -uroot -psecret_pass -e "DROP DATABASE bookstack; SHOW DATABASES;"
```

4. Start the RTO timer:

```bash
START=$(date +%s)
```

5. Prepare the temporary restore directory:

```bash
rm -rf /tmp/restore_db && mkdir -p /tmp/restore_db
```

6. Restore the dump directory from Restic:

```bash
docker compose run --rm --no-deps -v /tmp/restore_db:/restore --entrypoint restic backup_agent -r /backup_repo restore b0c74d3c --target /restore --include /tmp/dumps
```

7. List the available MariaDB dumps:

```bash
find /tmp/restore_db/tmp/dumps -name 'mariadb_*.sql' | sort
```

8. Select the latest dump file:

```bash
DUMP_FILE=$(find /tmp/restore_db/tmp/dumps -name 'mariadb_*.sql' | sort | tail -n 1)
```

9. Display the selected file path:

```bash
echo "$DUMP_FILE"
```

10. Reimport the dump into MariaDB:

```bash
cat "$DUMP_FILE" | docker compose exec -T db mariadb -uroot -psecret_pass
```

11. Start BookStack again:

```bash
docker compose start bookstack
```

12. Wait for the application to initialize:

```bash
sleep 20
```

13. Verify HTTP availability:

```bash
curl -I http://localhost:6875
```

14. Verify the marker count after restoration:

```bash
docker compose exec db mariadb -uroot -psecret_pass -e "SELECT COUNT(*) AS marker_count FROM bookstack.entities WHERE name='SAE_RESTORE_DB_TEST';"
```

15. Stop the timer:

```bash
END=$(date +%s)
```

16. Calculate the effective RTO:

```bash
echo "RTO scenario 2 = $((END-START)) seconds"
```

## Verification steps

- Confirm that BookStack responds with `302 Found` to `/login` or `200 OK`
- Confirm that the SQL marker count returns to `2`

## Success criteria

- The deleted database is restored successfully
- The SQL dump is imported without error
- BookStack becomes reachable again
- The marker value is identical before and after restoration
- The measured RTO is recorded

## Measured RTO

**28 seconds**

