# Terraform + libvirt: multi-VM lab with cloud-init

Deploys **two or more** KVM/QEMU virtual machines on a libvirt host using the
[`dmacvicar/libvirt`](https://github.com/dmacvicar/terraform-provider-libvirt)
provider (v0.9+, the rewritten provider that mirrors the libvirt XML schema).

Every VM gets:

- a qcow2 **overlay disk** backed by a shared cloud image (thin provisioning),
- a **cloud-init** seed ISO (user-data / meta-data / network-config),
- a **static IP** with a matching DHCP reservation,
- **UEFI (OVMF)** firmware, `host-passthrough` CPU, serial console and a
  qemu-guest-agent channel,
- a **hostname + IP output** printed by Terraform once the guest is up.

## Layout

```
.
├── versions.tf              # terraform + provider requirements
├── variables.tf             # all input variables (with defaults)
├── main.tf                  # composition: network module + VM module (for_each)
├── base_image.tf            # shared base cloud image volume
├── outputs.tf               # hostname / IP / MAC / SSH per VM
├── terraform.tfvars.example # copy -> terraform.tfvars and edit
├── Jenkinsfile              # parameterised Terraform CI pipeline
├── scripts/
│   └── terraform_inventory.py   # Terraform -> Ansible INI inventory
├── ansible/
│   ├── Jenkinsfile          # parameterised Ansible pipeline
│   ├── ansible.cfg
│   ├── site.yml             # sample playbook
│   └── inventory/
│       └── <branch>/hosts.ini   # generated, one dir per branch
└── modules/
    ├── network/             # reusable libvirt network (NAT or isolated)
    │   ├── main.tf
    │   └── versions.tf
    └── vm/                  # reusable single-VM module
        ├── main.tf
        ├── versions.tf
        └── templates/
            ├── user-data.yaml.tftpl
            └── network-config.yaml.tftpl
```

The `vms` variable is a **map**, so adding a third/fourth VM is a one-liner —
no new Terraform files needed.

## Prerequisites

```bash
# libvirt + qemu
sudo systemctl enable --now libvirtd
sudo virsh pool-list --all          # the 'default' pool must exist
ls /usr/share/edk2/x64/OVMF_CODE.4m.fd   # UEFI firmware (edk2-ovmf)

# your user needs access to the libvirt socket (or run with sudo)
sudo usermod -aG libvirt,kvm "$USER"
```

The provider connects to `qemu:///system` by default. For a rootless setup set
`libvirt_uri = "qemu:///session"`.

### IMPORTANT: allow VM forwarding in UFW

If the host runs **UFW** (the default on many desktops), its default forward
policy is **DROP**, which silently blocks the guest -> internet traffic. The
VMs will boot and get an IP, but DNS/HTTP/SSH from the guest to the outside
will time out. Fix it once, on the host:

```bash
# 1) allow forwarding for the libvirt bridge
sudo sed -i 's/^DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw

# 2) tell UFW to allow routed traffic out of the lab bridge
BRIDGE=virbr1                      # the bridge created by the tf-lab network
UPLINK=$(ip route show default | awk '{print $5; exit}')

sudo ufw route allow in on "$BRIDGE" out on "$UPLINK"
sudo ufw route allow in on "$UPLINK" out on "$BRIDGE"

sudo ufw reload
```

(`virsh net-dumpxml tf-lab | grep '<bridge'` shows the bridge name; it is
usually `virbr1` when the stock `default` network also exists.)

## Usage

```bash
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars            # set ssh_public_key_path and your VMs

terraform init
terraform plan
terraform apply
```

After apply:

```bash
terraform output
terraform output -json vms | jq

# Example:
#   "node1" -> { hostname = "node1", ip = "10.10.0.11", mac = "52:54:00:ca:12:f3" }
```

SSH into a VM:

```bash
terraform output ssh_commands
ssh ubuntu@10.10.0.11
```

## How the IP address is obtained

Because each guest is configured with a **static** address via cloud-init, the
IP is known at plan time. During `apply`:

1. the domain is created and booted with UEFI + `host-passthrough` CPU;
2. a `null_resource.reachable` **gate** blocks until the guest actually answers
   `ping` on its configured address (fails loudly if it never comes up);
3. `outputs.tf` reports the address, cross-checking the provider's
   `libvirt_domain_interface_addresses` data source (DHCP lease / guest agent)
   and falling back to the configured static IP.

The MAC address of each VM is derived deterministically from the VM key
(`52:54:00:xx:xx:xx`) and registered as a DHCP reservation on the network, so
local DNS (`node1.lab.local`) resolves to the intended address.

## Project name & naming scheme

`project_name` is the single source of truth. Every other name is derived from
it unless you set the corresponding variable explicitly:

| Derived name | Rule | Example (`project_name = "tf"`) |
|---|---|---|
| `network_name` | `<project>-net` | `tf-net` |
| `network_domain` | `<project>.local` | `tf.local` |
| VM name / hostname | `<vm_name_prefix><i>` | `tf-node1`, `tf-node2`, ... |
| VM IP | `cidrhost(cidr, vm_ip_start_offset + i - 1)` | `10.10.0.11`, `10.10.0.12`, ... |

The storage **pool** is the stock `default` pool by default (it usually
pre-exists and holds more than this project). If you set `pool_name` to a new
name, it is **created automatically** as a `dir` pool under `storage_pool_dir`
(`/var/lib/libvirt/images` by default) — the libvirt provider can only create
volumes inside an existing pool, so this is done with a small idempotent
`terraform_data` + `virsh pool-define-as/build/start` step.

## Configuration reference

| Variable | Default | Description |
|---|---|---|
| `project_name` | `lab` | base name for network/domain/VMs |
| `libvirt_uri` | `qemu:///system` | libvirt connection URI |
| `pool_name` | `default` | storage pool (auto-created if missing) |
| `storage_pool_dir` | `/var/lib/libvirt/images` | parent dir for an auto-created pool |
| `base_image_url` | Ubuntu 24.04 cloud image | base image URL |
| `base_image_name` | `ubuntu-noble-base.qcow2` | base volume name |
| `vm_disk_size` | `21474836480` (20 GiB) | overlay disk size in bytes |
| `network_name` | `""` -> `<project>-net` | network name |
| `network_cidr` | `10.10.0.0/24` | network CIDR |
| `network_gateway` | `10.10.0.1` | gateway |
| `network_domain` | `""` -> `<project>.local` | DNS domain |
| `network_isolation` | `false` | `true` = isolated (no NAT) |
| `vm_count` | `2` | number of auto-generated VMs (>= 2) |
| `vm_name_prefix` | `""` -> `<project>-node` | hostname prefix |
| `vm_ip_start_offset` | `11` | host part of the first VM IP |
| `vm_default_vcpu` | `2` | vCPUs per generated VM |
| `vm_default_memory_mib` | `2048` | MiB per generated VM |
| `admin_user` | `ubuntu` | cloud-init admin user |
| `iface_name` | `enp1s0` | NIC name inside the guest |
| `firmware` | `uefi` | `uefi` (OVMF) or `bios` |
| `ssh_public_key_path` | `~/.ssh/id_ed25519.pub` | injected SSH key |
| `vms` | `null` (auto-generate) | optional explicit override map |

Auto-generated mode (default) — just pick a project and a count:

```hcl
project_name = "team42"
vm_count     = 3
# -> team42-net, team42.local, team42-node1..3 @ 10.10.0.11..13
```

Explicit override (optional) — set `vms` for full per-VM control; it wins over
the auto-generated map:

```hcl
vms = {
  web = { hostname = "web", ip = "10.10.0.21", vcpu = 4, memory_mib = 8192 }
  db  = { hostname = "db",  ip = "10.10.0.22", vcpu = 2, memory_mib = 4096 }
}
```

Each `vms` entry accepts: `hostname`, `ip` (required, inside `network_cidr`),
`vcpu` (default 2), `memory_mib` (default 2048), `mac` (optional, auto-derived)
and `autostart` (default true).

## Jenkins pipeline

The repository ships a parameterised `Jenkinsfile` (declarative). Create a
*Pipeline from SCM* job, point it at this repo, and the first build prompts for
the parameters. The key ones are:

| Parameter | Purpose |
|---|---|
| `PROJECT_NAME` | drives network/domain/VM names (see above) |
| `ACTION` | `plan`, `apply` or `destroy` |
| `VM_COUNT` | how many VMs to create |
| `VM_NAME_PREFIX` | hostname prefix (empty -> `<project>-node`) |
| `VM_IP_START_OFFSET` | host part of the first VM IP |
| `VM_DEFAULT_VCPU` / `VM_DEFAULT_MEMORY_MIB` | per-VM sizing |
| `NETWORK_CIDR` / `NETWORK_GATEWAY` | network addressing |
| `NETWORK_ISOLATION` | NAT (false) or isolated (true) |
| `AUTO_APPROVE` | skip the interactive confirmation |
| `PLAN_WITH_DETAILS` | save a full plan to `plan.txt` as an artifact |

The pipeline writes `terraform.tfvars` from these parameters, then runs
`init -> validate -> plan -> (apply|destroy)` and prints/archives the resulting
**hostnames and IPs** (`terraform output vms`, `ssh_commands.txt`).

> **State:** the pipeline keeps the workspace so the local `terraform.tfstate`
> survives between builds (deleting it would orphan the VMs). For shared or
> team use, configure a remote backend (e.g. an S3/GCS/Consul backend or a
> `pg` backend) and then you can safely enable workspace cleanup.

## Ansible: dynamic inventory + pipeline

`scripts/terraform_inventory.py` builds an **Ansible INI inventory** from
`terraform output -json vms`. Each host entry carries `ansible_host` (IP),
`ansible_user` (cloud-init admin user) and `hostname`.

Inventories are written **one directory per branch**:

```
ansible/inventory/<branch>/hosts.ini
```

```bash
# generate for the current git branch
python3 scripts/terraform_inventory.py

# explicit branch (slashes are sanitised to dashes: feature/x -> feature-x)
python3 scripts/terraform_inventory.py --branch feature/x

# preview without writing
python3 scripts/terraform_inventory.py --dry-run

# use the script itself as an executable inventory
ansible-playbook -i scripts/terraform_inventory.py ansible/site.yml

# or use the generated INI
ansible-playbook -i ansible/inventory/local/hosts.ini ansible/site.yml
```

Example output (`ansible/inventory/<branch>/hosts.ini`):

```ini
[vms]
tf-node1 ansible_host=10.10.0.11 ansible_user=ubuntu hostname=tf-node1 ansible_mac=52:54:00:ca:12:f3
tf-node2 ansible_host=10.10.0.12 ansible_user=ubuntu hostname=tf-node2 ansible_mac=52:54:00:15:b1:8a

[all:children]
vms

[all:vars]
ansible_python_interpreter=/usr/bin/python3
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
```

Options: `--terraform-dir`, `--branch`, `--inventory-root`, `--output`,
`--group`, `--no-mac`, `--host-key-checking`, `--dry-run`, and the dynamic
inventory protocol flags `--list` / `--host`.

### Ansible pipeline

`ansible/Jenkinsfile` is a second (parameterised) pipeline that:

1. resolves the branch (`BRANCH_NAME`, else git, else `local`),
2. regenerates `ansible/inventory/<branch>/hosts.ini` from Terraform,
3. runs `ansible-playbook --syntax-check`,
4. runs the playbook — automatically (**auto** mode) or after a **manual
   confirmation gate** (**manual** mode, the default).

| Parameter | Purpose |
|---|---|
| `RUN_MODE` | `manual` (default) — pause at the manual stage; `auto` — run immediately |
| `TERRAFORM_DIR` | Terraform directory (empty -> repo root) |
| `PLAYBOOK` | playbook path (default `ansible/site.yml`) |
| `LIMIT` / `TAGS` / `EXTRA_VARS` | passed through to Ansible |
| `CHECK_MODE` | dry-run (`--check`) |
| `GENERATE_INVENTORY` | regenerate the inventory first |
| `USE_DYNAMIC_INVENTORY` | use `scripts/terraform_inventory.py` directly as an executable (dynamic) inventory instead of the generated `hosts.ini` |

#### The manual stage

With `RUN_MODE=manual` the build stops at **"Manual: run Ansible"** and shows
an input dialog. The operator fills in / overrides per run:

| Field | Meaning |
|---|---|
| `PLAYBOOK` | playbook to execute |
| `LIMIT` | host or group (`--limit`), empty = all |
| `TAGS` / `SKIP_TAGS` | `--tags` / `--skip-tags` |
| `EXTRA_VARS` | `--extra-vars` as `key=value key2=value2` |
| `CHECK_MODE` | dry run (`--check`) |
| `USE_DYNAMIC_INVENTORY` | dynamic script vs generated `hosts.ini` |
| `FORKS` | `--forks` (empty = ansible.cfg default) |
| `CONFIRM` | must stay checked; uncheck to skip the run |

The approver's Jenkins user is captured via `submitterParameter` and echoed to
the log. Aborting the input aborts the build; unchecking `CONFIRM` finishes it
as a no-op.

Dynamic inventory in the pipeline resolves to
`${WORKSPACE}/scripts/terraform_inventory.py`; the script locates the
Terraform directory itself and needs no extra flags, so the inventory always
reflects the current `terraform output -json vms`.

Ansible config lives in `ansible/ansible.cfg`; a sample playbook is
`ansible/site.yml`. Generated inventories are git-ignored — see
`ansible/inventory/README.md`.

## Operating the VMs

```bash
virsh list --all
virsh domifaddr <project>-node1
virsh net-dhcp-leases <project>-net
virsh console <project>-node1     # Ctrl+] to exit
virsh domdisplay <project>-node1  # VNC endpoint
sudo virsh destroy <project>-node1  # hard power off
```

## Troubleshooting

**VM hangs early in boot, often right after `Btrfs loaded`**

`Btrfs loaded` is printed by the kernel *inside the initramfs*, right after it
loads filesystem modules. If boot appears to stop there, the initramfs cannot
find its root filesystem. The config guards against the common causes:

- **UEFI (OVMF)** firmware for q35 cloud images (a BIOS boot of a q35 cloud
  image is the classic cause of an early initramfs hang). `firmware = "uefi"`
  is the default.
- `cpu = { mode = "host-passthrough" }` so KVM acceleration actually applies.
- an explicit `serials` device **and** a `console=ttyS0` GRUB drop-in written by
  cloud-init, plus `boot_devices = [hd, cdrom]`.
- the overlay disk is attached by **explicit file path** so `vda` is bound to
  `<vm>.qcow2` (with the base image as its qcow2 backing store).

Diagnose what actually happened:

```bash
qemu-img info /var/lib/libvirt/images/ubuntu-noble-base.qcow2
qemu-img info --backing-chain /var/lib/libvirt/images/node1.qcow2
sudo virsh console node1                 # Ctrl+] to exit
sudo virsh dumpxml node1 | sed -n '/<devices>/,/<\/devices>/p'
sudo journalctl -u libvirtd --since "15 min ago"
```

**Guest boots but has no IPv4 / no internet**

- Confirm the guest has its static address: `ssh ubuntu@10.10.0.11 ip -br addr`
- If ping to the gateway works but DNS/HTTP does not, you almost certainly hit
  the **UFW forwarding** issue described above — apply the UFW fix.
- Re-check the network DHCP range: static reservations **must fall inside** the
  `dhcp-range`, otherwise dnsmasq ignores them. This module sets the range to
  `10.10.0.10 - 10.10.0.254` for that reason.

**`Provider produced inconsistent result after apply` on `libvirt_volume.seed`**

The cloud-init seed is an ISO with the `cidata` label. Do not pin
`target.format.type = "raw"` on it — libvirt auto-detects `iso` and the
provider reads that back, causing the inconsistency. The volume is created
without an explicit `target.format.type` on purpose (see `modules/vm/main.tf`).

**Force a full rebuild of a VM**

```bash
terraform apply \
  -replace='module.vm["node1"].libvirt_domain.this' \
  -replace='module.vm["node2"].libvirt_domain.this'
```

## Notes / caveats

- **UEFI NVRAM** is per-VM at `/var/lib/libvirt/qemu/nvram/<name>_VARS.fd`.
  If you change `firmware`, recreate the domain (see above).
- **Static addressing:** the guest is configured with a static address via
  `network-config` (netplan, renderer `networkd`). The DHCP reservation is kept
  in sync for lease-based discovery and local DNS. To use pure DHCP, set
  `dhcp4: true` in `modules/vm/templates/network-config.yaml.tftpl` (and make
  sure the reservation is inside the DHCP range).
- **Interface name:** the netplan template matches the NIC by MAC and uses
  `enp1s0` (the predictable name of the first virtio NIC on q35). Override with
  `iface_name` if your image differs.
- **Base image immutability:** overlays use the base volume as a qcow2 backing
  store. Never delete `libvirt_volume.base` while overlays exist.
- **provider version:** written and validated against `dmacvicar/libvirt`
  `v0.9.9`. This is the new provider — the legacy v0.8 `libvirt_domain` schema
  differs significantly.
