# Scenario 1 - Partial file restore

## Purpose

Restore a specific file accidentally deleted from BookStack data using a Restic snapshot and measure the effective RTO. This procedure corresponds to the partial restore scenario required by the project.

## Prerequisites

- The operator is located in the project Docker directory: `~/SAE_S6/docker`
- Docker Compose is installed and operational
- The Restic repository is available
- Snapshot `b0c74d3c` exists
- The `bookstack` container is running
- The target file previously existed in `/config/restore-tests/s1_marker.txt`

## Restoration steps

1. Confirm that the target file is absent:

```bash
docker compose exec bookstack sh -c 'ls -l /config/restore-tests'
```

2. Start the RTO timer:

```bash
START=$(date +%s)
```

3. Prepare the temporary restore directory:

```bash
rm -rf /tmp/restore_partial && mkdir -p /tmp/restore_partial
```

4. Restore only the required file from the snapshot:

```bash
docker compose run --rm --no-deps -v /tmp/restore_partial:/restore --entrypoint restic backup_agent -r /backup_repo restore b0c74d3c --target /restore --include /data/bookstack/restore-tests/s1_marker.txt
```

5. Verify that the file is present in the temporary restore directory:

```bash
ls -l /tmp/restore_partial/data/bookstack/restore-tests
```

6. Display the content of the restored file:

```bash
cat /tmp/restore_partial/data/bookstack/restore-tests/s1_marker.txt
```

7. Recreate the destination directory inside the BookStack container if needed:

```bash
docker compose exec bookstack sh -c 'mkdir -p /config/restore-tests'
```

8. Copy the restored file back into the BookStack container:

```bash
docker cp /tmp/restore_partial/data/bookstack/restore-tests/s1_marker.txt bookstack:/config/restore-tests/s1_marker.txt
```

9. Verify the final restored file inside the container:

```bash
docker compose exec bookstack sh -c 'ls -l /config/restore-tests && cat /config/restore-tests/s1_marker.txt'
```

10. Stop the timer:

```bash
END=$(date +%s)
```

11. Calculate the effective RTO:

```bash
echo "RTO scenario 1 = $((END-START)) seconds"
```

## Verification steps

- Check that `/config/restore-tests/s1_marker.txt` exists again
- Check that the content is exactly `SCENARIO1_OK`

## Success criteria

- The file is restored successfully
- The restored file content is correct
- The restore operation affects only the requested file
- The measured RTO is recorded

## Measured RTO

**2 seconds**

