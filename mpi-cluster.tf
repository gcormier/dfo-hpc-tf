variable instance_count {
  description = "Defines the number of VMs to be provisioned."
  default     = "2"
}

resource "azurerm_resource_group" "RG" {
  name     = "HPC-TF-RG"
  location = "East US"
}

resource "azurerm_virtual_network" "vnet" {
  name                = "HPC-TF-VNET"
  address_space       = ["10.0.0.0/16"]
  location            = "${azurerm_resource_group.RG.location}"
  resource_group_name = "${azurerm_resource_group.RG.name}"
}

resource "azurerm_subnet" "subnet" {
  name                 = "acctsub"
  resource_group_name  = "${azurerm_resource_group.RG.name}"
  virtual_network_name = "${azurerm_virtual_network.vnet.name}"
  address_prefix       = "10.0.0.0/20"
}

resource "azurerm_public_ip" "pip" {
  name                = "hpc-vm${count.index}-pip"
  location            = "${azurerm_resource_group.RG.location}"
  resource_group_name = "${azurerm_resource_group.RG.name}"
  allocation_method   = "Static"
  count               = "${var.instance_count}"
}

resource "azurerm_network_interface" "vnic" {
  count               = "${var.instance_count}"
  name                = "hpc-nic${count.index}"
  location            = "${azurerm_resource_group.RG.location}"
  resource_group_name = "${azurerm_resource_group.RG.name}"

  ip_configuration {
    name                          = "testConfiguration"
    subnet_id                     = "${azurerm_subnet.subnet.id}"
    private_ip_address_allocation = "dynamic"
    public_ip_address_id          = "${element(azurerm_public_ip.pip.*.id, count.index)}"
  }
}

resource "azurerm_availability_set" "avset" {
  name                         = "avset"
  location                     = "${azurerm_resource_group.RG.location}"
  resource_group_name          = "${azurerm_resource_group.RG.name}"
  platform_fault_domain_count  = 1
  platform_update_domain_count = 1
  managed                      = true
}

resource "azurerm_virtual_machine" "vm" {
  count                 = "${var.instance_count}"
  name                  = "hpc-vm${count.index}"
  location              = "${azurerm_resource_group.RG.location}"
  availability_set_id   = "${azurerm_availability_set.avset.id}"
  resource_group_name   = "${azurerm_resource_group.RG.name}"
  network_interface_ids = ["${element(azurerm_network_interface.vnic.*.id, count.index)}"]
  vm_size               = "Standard_B4ms"

  # Uncomment this line to delete the OS disk automatically when deleting the VM
  delete_os_disk_on_termination = true

  # Uncomment this line to delete the data disks automatically when deleting the VM
  delete_data_disks_on_termination = true

  storage_image_reference {
    publisher = "OpenLogic"
    offer     = "CentOS"
    sku       = "7.4"
    version   = "latest"
  }

  storage_os_disk {
    name              = "osdisk${count.index}"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  # Optional data disks
  #storage_data_disk {
  #name              = "datadisk_new_${count.index}"
  #managed_disk_type = "Standard_LRS"
  #create_option     = "Empty"
  #lun               = 0
  #disk_size_gb      = "256"
  #}

  os_profile {
    computer_name  = "hpc-vm${count.index}"
    admin_username = "ansible"
  }
  os_profile_linux_config {
    disable_password_authentication = "true"

    ssh_keys {
      path     = "/home/ansible/.ssh/authorized_keys"
      key_data = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCyeslZL7rYdXx9LseK6Uur9jNR5Ed7Tjg3dgP4+v/DcYH/cQvV8RMY4FDJA/t6RKDcN91CMPnc05XCTjcP1hmKOyLUeJXvAzbAtQWcorGmiHwMpXkSkRBuOxTnkOcAVbEDXwnXWUCo2GJq0am2KtVD8L031qBDlJwwNrzjKBr6QP0ApJs0fGcjDUD8j9szFr3xx4NyeDhkCHMtPGqCxNVeUR7JHjUQBHvTHaSLtQuChW/BpjnQysKIWUkjflvprClUH28UXHFS1C+O0+N+W5wrfJ9UbqgjN/BPT2vWAs3fyZjT1RUrrzuGFil5Z9hvJm35U0IoJ0RYUazJ7lE69bqiFEBqUMSBHFuAloXjp22odMtk0+mhGKpckXXg19zQtwIz6LQEHokawNI1+e6y7041FCDU8HvozN5fz+lJx2rkIDHSk6vO3Nroci02DGGlV6QEzI4BRd1prj6tE71MZ8k7/KQMrubfxtXuzBsozjp+LPB62MZj/ex9tApYg+TmwFcluHF+6LHOuk+Ubq03tMlGSymcKn6km2s9sGqQ6X7WY+55g+V4JcdnFjeNyzIX+T4kMAVl6nM0gWUrSlrc5Y95MA7pFNQJMyA0MUPp3FRX7Z25jDuqZcgmTrd0YLL63bxjgSSd0sV7prPEo6ho3vWKKyZo9L3UPIEWpm/X/MD89Q== greg"
    }
  }
  
  tags {
    environment = "hpc"
  }
}

output "Private_IP_Addresses" {
  value = "${azurerm_network_interface.vnic.*.private_ip_addresses}"
}

output "pips" {
  value = "${azurerm_public_ip.pip.*.ip_address}"
}
