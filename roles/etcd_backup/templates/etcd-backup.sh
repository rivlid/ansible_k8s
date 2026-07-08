#!/bin/bash

BACKUP_DIR="{{ etcd_backup_mount }}"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/etcd-$DATE.db"

/usr/local/bin/etcdctl snapshot save "$BACKUP_FILE" \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

if [ $? -eq 0 ] && [ -s "$BACKUP_FILE" ]; then
  echo "OK $(date)" > "$BACKUP_DIR/etcd-backup.status"
  find "$BACKUP_DIR" -name "etcd-*.db" -mtime +{{ etcd_backup_retention_days }} -delete
else
  echo "FAIL $(date)" > "$BACKUP_DIR/etcd-backup.status"
  rm -f "$BACKUP_FILE"
  exit 1
fi