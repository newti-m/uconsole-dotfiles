# Ansible Homelab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Set up an Ansible project on `auto` (192.168.1.154) that manages all homelab hosts and can gather facts from all of them with a single command.

**Architecture:** Project lives at `~/homelab-ansible/` on `auto`. All commands run on `auto` via SSH from the uConsole. Inventory uses YAML with per-host vars. The repo is pushed to GitHub from `auto`.

**Tech Stack:** Ansible (pip), Python 3, SSH key auth (already configured)

> **Note:** All commands in this plan run on `auto` unless marked `[uConsole]`. SSH in with `ssh auto` first.

---

## File Map

| File | Purpose |
|---|---|
| `ansible.cfg` | Default settings, inventory path, SSH config reference |
| `inventory/hosts.yml` | Host groups (proxmox, servers, network) |
| `inventory/host_vars/aputer.yml` | Windows host connection vars |
| `inventory/host_vars/pbx.yml` | Proxmox node 1 root user |
| `inventory/host_vars/pbx2.yml` | Proxmox node 2 |
| `inventory/host_vars/plexy3-1.yml` | Proxmox node 1 ntm user |
| `inventory/host_vars/pihole.yml` | Pi-hole VM |
| `inventory/host_vars/auto.yml` | Local connection for self-management |
| `playbooks/gather_facts.yml` | Gather and display system facts from all hosts |

---

### Task 1: Install Ansible on `auto` and distribute its SSH key

**Files:** none

- [ ] **Step 1: SSH into auto**

```bash
ssh auto
```

- [ ] **Step 2: Install Ansible via pip**

```bash
sudo apt update && sudo apt install -y python3-pip python3-venv
pip3 install --user ansible
```

- [ ] **Step 3: Verify Ansible is available**

```bash
~/.local/bin/ansible --version
```

Expected output starts with: `ansible [core 2.x.x]`

- [ ] **Step 4: Add ~/.local/bin to PATH if needed**

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc
ansible --version
```

- [ ] **Step 5: Generate SSH key on auto (if not present)**

```bash
ls ~/.ssh/id_ed25519 2>/dev/null || ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""
cat ~/.ssh/id_ed25519.pub
```

- [ ] **Step 6: Distribute auto's key to all managed hosts**

Run each from **auto**. You will be prompted for passwords (the same ones you used earlier from the uConsole):

```bash
ssh-copy-id newti@192.168.1.70   # aputer
ssh-copy-id root@192.168.1.41    # pbx
ssh-copy-id auto@192.168.1.63    # pbx2
ssh-copy-id ntm@192.168.1.41     # plexy3-1
ssh-copy-id ntm@192.168.1.185    # pihole
```

(`auto` itself is a local connection — no key needed.)

- [ ] **Step 7: Verify SSH works from auto to each host**

```bash
ssh newti@192.168.1.70 echo ok   # aputer
ssh root@192.168.1.41 echo ok    # pbx
ssh auto@192.168.1.63 echo ok    # pbx2
ssh ntm@192.168.1.41 echo ok     # plexy3-1
ssh ntm@192.168.1.185 echo ok    # pihole
```

Each should print `ok` without a password prompt.

---

### Task 2: Create repo on GitHub and initialize locally

**Files:** `~/homelab-ansible/.gitignore`

> Run this task from the **uConsole** where `gh` is authenticated.

- [ ] **Step 1: Create GitHub repo [uConsole]**

```bash
gh repo create homelab-ansible --private --description "Ansible homelab automation"
```

- [ ] **Step 2: Initialize repo on auto**

```bash
# on auto
mkdir ~/homelab-ansible && cd ~/homelab-ansible
git init
git remote add origin git@github.com:newti-m/homelab-ansible.git
```

- [ ] **Step 3: Create .gitignore**

```bash
cat > ~/homelab-ansible/.gitignore << 'EOF'
*.vault
*.secret
*.retry
__pycache__/
.env
EOF
```

- [ ] **Step 4: Initial commit**

```bash
cd ~/homelab-ansible
git add .gitignore
git commit -m "init: add .gitignore"
git branch -M main
git push -u origin main
```

---

### Task 3: Create ansible.cfg

**Files:** Create `~/homelab-ansible/ansible.cfg`

- [ ] **Step 1: Write ansible.cfg**

```bash
cat > ~/homelab-ansible/ansible.cfg << 'EOF'
[defaults]
inventory = inventory/hosts.yml
host_key_checking = False
interpreter_python = auto

[ssh_connection]
ssh_args = -o ControlMaster=auto -o ControlPersist=10m
EOF
```

- [ ] **Step 2: Verify it parses**

```bash
cd ~/homelab-ansible && ansible --version | grep 'config file'
```

Expected: `config file = /home/ntm/homelab-ansible/ansible.cfg`

- [ ] **Step 3: Commit**

```bash
cd ~/homelab-ansible
git add ansible.cfg
git commit -m "add ansible.cfg"
```

---

### Task 4: Create inventory

**Files:** Create `~/homelab-ansible/inventory/hosts.yml`

- [ ] **Step 1: Create inventory directory and hosts.yml**

```bash
mkdir -p ~/homelab-ansible/inventory/host_vars
cat > ~/homelab-ansible/inventory/hosts.yml << 'EOF'
all:
  children:
    proxmox:
      hosts:
        pbx:
        pbx2:
        plexy3-1:
    servers:
      hosts:
        aputer:
        auto:
    network:
      hosts:
        pihole:
EOF
```

- [ ] **Step 2: Verify inventory parses**

```bash
cd ~/homelab-ansible && ansible-inventory --list
```

Expected: JSON showing all 6 hosts across the three groups.

- [ ] **Step 3: Commit**

```bash
cd ~/homelab-ansible
git add inventory/hosts.yml
git commit -m "add inventory with proxmox, servers, network groups"
```

---

### Task 5: Create host_vars

**Files:** Create all 6 files in `~/homelab-ansible/inventory/host_vars/`

- [ ] **Step 1: auto.yml (local connection)**

```bash
cat > ~/homelab-ansible/inventory/host_vars/auto.yml << 'EOF'
ansible_host: 192.168.1.154
ansible_user: ntm
ansible_connection: local
ansible_python_interpreter: /usr/bin/python3
EOF
```

- [ ] **Step 2: pbx.yml**

```bash
cat > ~/homelab-ansible/inventory/host_vars/pbx.yml << 'EOF'
ansible_host: 192.168.1.41
ansible_user: root
ansible_python_interpreter: /usr/bin/python3
EOF
```

- [ ] **Step 3: pbx2.yml**

```bash
cat > ~/homelab-ansible/inventory/host_vars/pbx2.yml << 'EOF'
ansible_host: 192.168.1.63
ansible_user: auto
ansible_python_interpreter: /usr/bin/python3
EOF
```

- [ ] **Step 4: plexy3-1.yml**

```bash
cat > ~/homelab-ansible/inventory/host_vars/plexy3-1.yml << 'EOF'
ansible_host: 192.168.1.41
ansible_user: ntm
ansible_python_interpreter: /usr/bin/python3
EOF
```

- [ ] **Step 5: pihole.yml**

```bash
cat > ~/homelab-ansible/inventory/host_vars/pihole.yml << 'EOF'
ansible_host: 192.168.1.185
ansible_user: ntm
ansible_python_interpreter: /usr/bin/python3
EOF
```

- [ ] **Step 6: aputer.yml (Windows)**

```bash
cat > ~/homelab-ansible/inventory/host_vars/aputer.yml << 'EOF'
ansible_host: 192.168.1.70
ansible_user: newti
ansible_connection: ssh
ansible_shell_type: powershell
ansible_python_interpreter: auto
EOF
```

- [ ] **Step 7: Commit**

```bash
cd ~/homelab-ansible
git add inventory/host_vars/
git commit -m "add host_vars for all 6 hosts"
git push
```

---

### Task 6: Test connectivity

**Files:** none

- [ ] **Step 1: Ping all Linux hosts (exclude aputer for now)**

```bash
cd ~/homelab-ansible && ansible all:!aputer -m ping
```

Expected — each host returns:
```
pbx | SUCCESS => { "ping": "pong" }
pbx2 | SUCCESS => { "ping": "pong" }
plexy3-1 | SUCCESS => { "ping": "pong" }
pihole | SUCCESS => { "ping": "pong" }
auto | SUCCESS => { "ping": "pong" }
```

Fix any failures before proceeding (check SSH key is on the host, username is correct).

- [ ] **Step 2: Test aputer separately**

```bash
cd ~/homelab-ansible && ansible aputer -m ping
```

Expected: `aputer | SUCCESS => { "ping": "pong" }`

If it fails with "Python not found", find the Python path on aputer:

```bash
ssh aputer "where python"
```

Then update `inventory/host_vars/aputer.yml` with the full path, e.g.:
```yaml
ansible_python_interpreter: C:\Python312\python.exe
```

---

### Task 7: Create gather_facts playbook

**Files:** Create `~/homelab-ansible/playbooks/gather_facts.yml`

- [ ] **Step 1: Create playbooks directory and gather_facts.yml**

```bash
mkdir -p ~/homelab-ansible/playbooks
cat > ~/homelab-ansible/playbooks/gather_facts.yml << 'EOF'
---
- name: Gather and display host facts
  hosts: all
  gather_facts: true

  tasks:
    - name: Display Linux system summary
      ansible.builtin.debug:
        msg:
          - "Hostname:  {{ ansible_hostname }}"
          - "OS:        {{ ansible_distribution }} {{ ansible_distribution_version }}"
          - "CPUs:      {{ ansible_processor_vcpus }}"
          - "RAM:       {{ (ansible_memtotal_mb / 1024) | round(1) }} GB"
          - "Uptime:    {{ (ansible_uptime_seconds / 3600) | round(1) }} hours"
          - "Disk /:    {{ ansible_mounts | selectattr('mount', 'equalto', '/') | map(attribute='size_total') | first | human_readable }} total"
      when: ansible_system != 'Win32NT'

    - name: Display Windows system summary
      ansible.builtin.debug:
        msg:
          - "Hostname:  {{ ansible_hostname }}"
          - "OS:        {{ ansible_os_name | default('Windows') }}"
          - "CPUs:      {{ ansible_processor_count | default('unknown') }}"
          - "RAM:       {{ (ansible_memtotal_mb / 1024) | round(1) }} GB"
      when: ansible_system == 'Win32NT'
EOF
```

- [ ] **Step 2: Run against Linux hosts to verify**

```bash
cd ~/homelab-ansible && ansible-playbook playbooks/gather_facts.yml -l proxmox,network,auto
```

Expected: Each host prints a debug block with hostname, OS, CPUs, RAM, uptime, and disk.

- [ ] **Step 3: Run against aputer**

```bash
cd ~/homelab-ansible && ansible-playbook playbooks/gather_facts.yml -l aputer
```

Expected: aputer prints the Windows summary block. If gather_facts fails for Windows, add `gather_facts: false` for aputer and use `raw` module to collect basic info — but try this first.

- [ ] **Step 4: Run against all hosts**

```bash
cd ~/homelab-ansible && ansible-playbook playbooks/gather_facts.yml
```

Expected: All 6 hosts complete with `ok` status (no failures).

- [ ] **Step 5: Commit and push**

```bash
cd ~/homelab-ansible
git add playbooks/gather_facts.yml
git commit -m "add gather_facts playbook"
git push
```

---

## Done

`ansible-playbook playbooks/gather_facts.yml` runs cleanly against all 6 hosts and prints a system summary for each. Foundation is in place for future playbooks (patching, service management, config deployment).
