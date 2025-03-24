##################################################################################
# VARIABLES
##################################################################################

# HTTP Settings

http_directory = "http"

# Virtual Machine Settings

vm_name                     = "Ubuntu-2204-Template-100GB-Thin"
vm_guest_os_type            = "ubuntu64Guest"
vm_version                  = 14
vm_firmware                 = "bios"
vm_cdrom_type               = "sata"
vm_cpu_sockets              = 1
vm_cpu_cores                = 1
vm_mem_size                 = 1024
vm_disk_size                = 102400
thin_provision              = true
disk_eagerly_scrub          = false
vm_disk_controller_type     = ["pvscsi"]
vm_network_card             = "vmxnet3"
vm_boot_wait                = "5s"
ssh_username                = "ubuntu"
ssh_password                = "ubuntu"

# ISO Objects

iso_file                    = "ubuntu-22.04.1-live-server-amd64.iso"
iso_checksum                = "10f19c5b2b8d6db711582e0e27f5116296c34fe4b313ba45f9b201a5007056cb"
iso_checksum_type           = "sha256"
iso_url                     = "https://releases.ubuntu.com/jammy/ubuntu-22.04.1-live-server-amd64.iso" 
# Scripts

shell_scripts               = ["./scripts/setup_ubuntu2204_withDocker.sh"]
