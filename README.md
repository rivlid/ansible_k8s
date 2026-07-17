# ansible_k8s — bootstrap production Kubernetes кластера

Плейбуки для развёртывания HA-кластера Kubernetes **с нуля до состояния, в котором
дальше работает GitOps**. Зона ответственности этой репы — ноды и control plane.
Всё, что живёт «внутри» кластера (MetalLB, ingress-nginx, прокси, мониторинг),
управляется через ArgoCD из репы **argo_sadko** — см. её README.

```
ansible_k8s (эта репа)          argo_sadko + ArgoCD
┌─────────────────────────┐     ┌──────────────────────────────┐
│ ОС, containerd, kubeadm │ --> │ MetalLB, ingress-nginx,      │
│ HA (haproxy+keepalived) │     │ sadko-proxy, мониторинг ...  │
│ calico, etcd backup     │     │                              │
└─────────────────────────┘     └──────────────────────────────┘
        запускается руками            синкается из git само
```

## Кластер

- 3 мастера (`10.69.0.10-12`) + 21 воркер (`10.69.0.20-40`) — см. `inventory/hosts.ini`
- Kubernetes v1.36.1, containerd, CNI calico
- HA control plane: HAProxy + Keepalived, VIP `10.69.0.250`, порт `8888` → apiserver `6443`
- pod network: `172.13.0.0/16`

## Требования

- Доступ по ssh root на все ноды (см. `ansible.cfg`)
- Файл с паролем vault: `~/.vault/ha` (в vault зашифрован `keepalived_auth_pass`)
- Пакеты k8s/containerd кладутся из `src_pkg_dir: /root` — версии заданы в `group_vars/all.yml`

## Порядок развёртывания

Плейбуки нумерованы — запускаются по порядку:

| # | Плейбук | Что делает | Хосты |
|---|---------|-----------|-------|
| 01 | `01-prepare-nodes.yml` | Подготовка ОС: модули ядра, sysctl, swap off и т.п. (роль `common`) | все |
| 02 | `02-install-runtime-and-k8s.yml` | containerd + kubeadm/kubelet/kubectl (роли `containerd`, `kubernetes`) | все |
| 03 | `03-ha.yml` | HAProxy + Keepalived, VIP для apiserver (роль `ha`) | мастера |
| 04 | `04-init-cluster.yml` | `kubeadm init` на первом мастере + calico (роли `init`, `calico`) | masters[0] |
| 05 | `05-join-masters.yml` | Загрузка сертификатов, join остальных мастеров (роли `upload_certs`, `generate_token`) | мастера |
| 06 | `06-join-workers.yml` | Join воркеров | воркеры |
| 07 | `07-metallb.yml` | **DEPRECATED** — MetalLB теперь через ArgoCD (репа metallb + argo_sadko) | — |
| 08 | `08-ingress-nginx.yml` | **DEPRECATED** — ingress-nginx теперь через ArgoCD (репа k8s/ingress-nginx) | — |
| 09 | `09-etcd-backup.yml` | etcdctl + бэкап etcd на NFS по крону (роли `etcdctl`, `etcd_backup`) | мастера |

```bash
ansible-playbook 01-prepare-nodes.yml
ansible-playbook 02-install-runtime-and-k8s.yml
# ... и так далее по номерам, 07 и 08 пропускаем
```

После 06 (кластер собран, ноды Ready) и 09 — дальше по инструкции из README репы
**argo_sadko**: установка ArgoCD хелмом и применение Application-ов
(MetalLB → ingress-nginx → sadko-proxy).

### Почему 07 и 08 deprecated

Изначально MetalLB и ingress-nginx ставились этими плейбуками (kubectl apply
статических манифестов). Сейчас оба компонента управляются ArgoCD из git — при
развёртывании начисто их надо ставить через ArgoCD, а не ансиблом, иначе получится
конфигурация вне GitOps. Плейбуки оставлены в репе как справка и аварийный вариант
(например, поднять ingress до того, как заработал ArgoCD).

## Переменные — group_vars/all.yml

Ключевое:

| Переменная | Значение | Комментарий |
|------------|----------|-------------|
| `k8s_version` / `k8s_release` | 1.36.1 | версия кластера |
| `vip` | 10.69.0.250 | VIP apiserver (keepalived) |
| `haproxy_port` | 8888 | порт VIP → apiserver 6443 |
| `pod_network_cidr` | 172.13.0.0/16 | сеть подов (calico) |
| `keepalived_auth_pass` | vault | пароль VRRP |
| `etcd_backup_*` | NFS 192.168.10.6:/mnt/data/backup/k8s | cron в 6:00, ротация 30 дней |
| `metallb_*`, `ingress_nginx_replicas` | — | устарели вместе с плейбуками 07/08, актуальные значения — в git-репах metallb / argo_sadko |

## Бэкап etcd

Плейбук 09 ставит `etcdctl` (v3.6.8) на мастера, монтирует NFS
`192.168.10.6:/mnt/data/backup/k8s` в `/mnt/backup/etcd` и заводит cron:
снапшот etcd ежедневно в 6:00, хранение 30 дней.

Восстановление — стандартное `etcdctl snapshot restore` (см. документацию kubeadm
по disaster recovery).

## Приложение: пример BGP-конфига для bird (на стороне шлюза)

MetalLB анонсирует адреса сервисов по BGP (myASN 64513 → peerASN 64512,
peer `10.69.0.254`). Конфигурация пиров на шлюзе (bird):

```nginx
filter k8s_services {
        if net ~ [ 192.168.253.0/24{32,32} ] then accept;
        reject;
}
template bgp k8s_peers {
        local as 64512;
        import filter k8s_services;
        export none;
        import limit 20 action block;
}
protocol bgp k8s_w00 from k8s_peers { neighbor 10.69.0.10 as 64513; }
protocol bgp k8s_w01 from k8s_peers { neighbor 10.69.0.11 as 64513; }
protocol bgp k8s_w02 from k8s_peers { neighbor 10.69.0.12 as 64513; }
protocol bgp k8s_w03 from k8s_peers { neighbor 10.69.0.20 as 64513; }
protocol bgp k8s_w04 from k8s_peers { neighbor 10.69.0.21 as 64513; }
protocol bgp k8s_w05 from k8s_peers { neighbor 10.69.0.22 as 64513; }
```

> Спикеры MetalLB работают на нодах — при добавлении воркеров, с которых должен
> идти анонс, добавить соответствующие `protocol bgp` секции.
