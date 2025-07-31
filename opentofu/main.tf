terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.7.0"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

# Ubuntu cloud image
resource "libvirt_volume" "ubuntu_base" {
  name   = "ubuntu-base.qcow2"
  pool   = "default"
  source = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
  format = "qcow2"
}

# VM disk
resource "libvirt_volume" "vm_disk" {
  name           = "vm-disk.qcow2"
  base_volume_id = libvirt_volume.ubuntu_base.id
  pool           = "default"
  size           = 21474836480 # 20GB
}

# Cloud-init config with logging setup
resource "libvirt_cloudinit_disk" "commoninit" {
  name      = "commoninit.iso"
  pool      = "default"
  user_data = <<-EOF
    #cloud-config
    users:
      - name: ubuntu
        sudo: ALL=(ALL) NOPASSWD:ALL
        groups: users, admin, sudo
        shell: /bin/bash
        lock_passwd: false
        passwd: $6$rounds=4096$salt$hash # Change this
        ssh_authorized_keys:
          - ssh-rsa YOUR_SSH_PUBLIC_KEY_HERE
    
    ssh_pwauth: true
    disable_root: false
    
    packages:
      - openssh-server
      - curl
      - wget
      - rsyslog
    
    write_files:
      - path: /etc/rsyslog.d/49-filebeat.conf
        content: |
          # Send logs to ELK stack
          *.* @@host.docker.internal:5000
        permissions: '0644'
    
    runcmd:
      - systemctl enable ssh
      - systemctl start ssh
      - systemctl enable rsyslog
      - systemctl restart rsyslog
      - mkdir -p /var/log/applications
      - chmod 755 /var/log/applications
  EOF
}

# VM definition
resource "libvirt_domain" "vm" {
  name   = "ubuntu-vm-elk"
  memory = "2048"
  vcpu   = 2

  cloudinit = libvirt_cloudinit_disk.commoninit.id

  network_interface {
    network_name = "default"
    wait_for_lease = true
  }

  disk {
    volume_id = libvirt_volume.vm_disk.id
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }
}

# Output VM information for Ansible inventory
output "vm_ip" {
  value = libvirt_domain.vm.network_interface[0].addresses[0]
}

output "vm_name" {
  value = libvirt_domain.vm.name
}

output "vm_info" {
  value = {
    name = libvirt_domain.vm.name
    ip   = libvirt_domain.vm.network_interface[0].addresses[0]
    id   = libvirt_domain.vm.id
  }
}
