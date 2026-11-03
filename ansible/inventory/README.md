# Ansible inventories

Inventories in this directory are **generated** from Terraform outputs by
`scripts/terraform_inventory.py`. One directory per git branch:

```
ansible/inventory/<branch>/hosts.ini
```

Generate one manually:

```bash
python3 scripts/terraform_inventory.py --terraform-dir . --branch "$(git rev-parse --abbrev-ref HEAD)"
ansible-playbook -i ansible/inventory/$(git rev-parse --abbrev-ref HEAD | tr '/' '-')/hosts.ini ansible/site.yml
```
