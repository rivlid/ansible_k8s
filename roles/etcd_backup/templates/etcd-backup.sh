#!/bin/bash

BACKUP_DIR="{{ etcd_backup_mount }}"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/etcd-$DATE.db"

ETCDCTL_API=3 etcdctl snapshot save "$BACKUP_FILE" \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

if [ $? -eq 0 ]; then
  # Верификация снапшота
  ETCDCTL_API=3 etcdctl snapshot status "$BACKUP_FILE" --write-out=table
  if [ $? -eq 0 ]; then
    echo "OK $(date)" > "$BACKUP_DIR/etcd-backup.status"
    find "$BACKUP_DIR" -name "etcd-*.db" -mtime +{{ etcd_backup_retention_days }} -delete
  else
    echo "FAIL verification $(date)" > "$BACKUP_DIR/etcd-backup.status"
    rm -f "$BACKUP_FILE"
    exit 1
  fi
else
  echo "FAIL $(date)" > "$BACKUP_DIR/etcd-backup.status"
  exit 1
fi