# Ansible Homelab — Design Spec

**Date:** 2026-05-23

## Overview

An Ansible project living on `auto` (192.168.1.154) that manages all homelab hosts including itself. Initial scope: inventory + fact gathering. Foundation for future playbooks (patching, service management, config deployment).

## Inventory

YAML inventory with hosts organized into three groups:

| Group | Hosts |
|---|---|
| `proxmox` | pbx, pbx2, plexy3-1 |
| `servers` | aputer, auto |
| `network` | pihole |

## Host Connection Details

| Host | IP | User | Notes |
|---|---|---|---|
| aputer | 192.168.1.70 | newti | |
| pbx | 192.168.1.41 | root | Proxmox node 1 |
| pbx2 | 192.168.1.63 | auto | Proxmox node 2 |
| plexy3-1 | 192.168.1.41 | ntm | Proxmox node 1 (non-root) |
| pihole | 192.168.1.185 | ntm | Pi-hole DNS VM |
| auto | 192.168.1.154 | ntm | Automation server, local connection |

## Project Structure

```
~/homelab-ansible/
├── ansible.cfg
├── inventory/
│   ├── hosts.yml
│   └── host_vars/
│       ├── aputer.yml
│       ├── pbx.yml
│       ├── pbx2.yml
│       ├── plexy3-1.yml
│       ├── pihole.yml
│       └── auto.yml
└── playbooks/
    └── gather_facts.yml
```

## ansible.cfg

- Inventory path: `inventory/hosts.yml`
- SSH args reference `~/.ssh/config` so existing host aliases resolve correctly
- Host key checking disabled for LAN hosts (already in known_hosts)

## gather_facts Playbook

Runs against all hosts (or a subset via `-l <group>`). Prints per host:

- Hostname
- OS + version
- CPU count
- Total RAM
- Disk usage on `/`
- Uptime

Usage:
```bash
ansible-playbook playbooks/gather_facts.yml          # all hosts
ansible-playbook playbooks/gather_facts.yml -l proxmox  # proxmox group only
```

## Future Playbooks (out of scope for this spec)

- `patch_all.yml` — apt update + upgrade across all hosts
- `restart_service.yml` — parameterized service restart
- `deploy_configs.yml` — push config files from `auto` to hosts
