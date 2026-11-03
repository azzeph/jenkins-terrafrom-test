# Terraform Libvirt Deployment (Modern Provider v0.9+)

Комплект Terraform-манифестов для деплоя двух (и более) виртуальных машин в KVM/libvirt с использованием современного провайдера `dmacvicar/libvirt` (архитектура v0.9+ на базе Terraform Plugin Framework).

## Архитектура проекта

```text
ai-qwen-libvirt/
├── main.tf                    # Корневой манифест (провайдер, базовый образ, вызов модуля)
├── variables.tf               # Входные переменные проекта с дефолтными значениями
├── outputs.tf                 # Итоговые outputs (список и map ВМ с IP и хостнеймами)
├── terraform.tfvars.example   # Пример конфигурации параметров окружения
└── modules/
    └── libvirt_vm/            # Переиспользуемый модуль создания ВМ
        ├── versions.tf        # Требования к версиям провайдера
        ├── variables.tf       # Входные параметры модуля (CPU, RAM, диск, сеть, cloud-init)
        ├── main.tf            # Ресурсы (cloudinit_disk, volume, domain, data source IP)
        └── outputs.tf         # Экспортируемые данные модуля (id, name, IP адреса)
```

## Ключевые особенности v0.9+

- **Строгое соответствие Libvirt XML Schema**: параметры устройств, дисков и сети точно соответствуют структуре libvirt.
- **Copy-on-Write (CoW)**: базовый образ скачивается один раз на уровне корня (`base_image`), а каждая ВМ создаёт тонкий оверлей-том (`backing_store`).
- **Cloud-Init ISO**: автоматическая генерация конфигурации пользователя, SSH-ключей и hostname через `libvirt_cloudinit_disk` и монтирование в качестве виртуального CD-ROM.
- **Ожидание и получение IP-адресов**: 
  - На интерфейсе домена включен блок `wait_for_ip`, чтобы дождаться аренды DHCP или ответа QEMU Guest Agent.
  - Используется официальный data source `libvirt_domain_interface_addresses` для извлечения IPv4 адресов.

## Быстрый старт

1. Скопируйте файл переменных:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```
2. Укажите свой публичный SSH-ключ и скорректируйте параметры пула/сети в `terraform.tfvars`.
3. Инициализируйте и запустите:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

4. По завершении выполнения `terraform apply` выведет список ВМ:
   ```json
   Outputs:

   vm_list = [
     {
       "hostname" = "web-srv-01"
       "primary_ip" = "192.168.122.145"
       "ip_addresses" = [
         "192.168.122.145",
         "fe80::..."
       ]
     },
     {
       "hostname" = "web-srv-02"
       "primary_ip" = "192.168.122.146"
       "ip_addresses" = [
         "192.168.122.146",
         "fe80::..."
       ]
     }
   ]
   ```
