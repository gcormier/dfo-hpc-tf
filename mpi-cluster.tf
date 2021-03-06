variable instance_count {
	description = "Defines the number of VMs to be provisioned."
	default     = "2"
}
variable app_name {
	description = "Application Name"
	default = "fvcom"
}

variable location {
	description = "Location of the infrastructure"
	#default = "South Central US"
	default = "East US"
}

variable instance_size {
	description = "Size of the instance"
	#default = "Standard_F64s_v2"
	#default = "Standard_F4s_v2"
	#default = "Standard_H16r"
	default = "Standard_Hc44rs"
	#default = "Standard_Hb60rs"
}

variable accelerated {
	description = "List of accelerated instance sizes"
	default=[ "Standard_F4s_v2",
						"Standard_F8s_v2",
						"Standard_F16s_v2",
						"Standard_F32s_v2",
						"Standard_F64s_v2",
						#"Standard_Hc44rs",
						#"Standard_Hb60rs"
					]
}

resource "azurerm_resource_group" "RG" {  
	name     = "HPC-${upper(var.app_name)}-RG"
	location = var.location
}

resource "azurerm_virtual_network" "vnet" {
	name                = "HPC-${upper(var.app_name)}-VNET"
	address_space       = ["10.0.0.0/16"]
	location            = azurerm_resource_group.RG.location
	resource_group_name = azurerm_resource_group.RG.name
}

resource "azurerm_subnet" "subnet" {
	name                 = "acctsub"
	resource_group_name  = azurerm_resource_group.RG.name
	virtual_network_name = azurerm_virtual_network.vnet.name
	address_prefix       = "10.0.0.0/20"
}

resource "azurerm_public_ip" "pip" {
	name                = "${lower(var.app_name)}-vm${count.index+1}-pip"
	location            = azurerm_resource_group.RG.location
	resource_group_name = azurerm_resource_group.RG.name
	allocation_method   = "Static"
	count               = var.instance_count
}

resource "azurerm_network_interface" "vnic" {
	count               = var.instance_count
	name                = "hpc-${lower(var.app_name)}-nic${count.index+1}"
	location            = azurerm_resource_group.RG.location
	resource_group_name = azurerm_resource_group.RG.name
	enable_accelerated_networking = "${contains(var.accelerated, var.instance_size) ? true : false}"

	ip_configuration {
		name                          = "testConfiguration"
		subnet_id                     = azurerm_subnet.subnet.id
		private_ip_address_allocation = "dynamic"
		public_ip_address_id          = element(azurerm_public_ip.pip.*.id, count.index)
	}
}

resource "azurerm_availability_set" "avset" {
	name                         = "${lower(var.app_name)}-avset"
	location                     = azurerm_resource_group.RG.location
	resource_group_name          = azurerm_resource_group.RG.name
	platform_fault_domain_count  = 1
	platform_update_domain_count = 1
	managed                      = true
}

resource "azurerm_virtual_machine" "vm" {
	count                 = var.instance_count
	name                  = "hpc-${lower(var.app_name)}-vm${count.index+1}"
	location              = azurerm_resource_group.RG.location
	availability_set_id   = azurerm_availability_set.avset.id
	resource_group_name   = azurerm_resource_group.RG.name
	network_interface_ids = ["${element(azurerm_network_interface.vnic.*.id, count.index)}"]
	vm_size               = var.instance_size

	

	# Uncomment this line to delete the OS disk automatically when deleting the VM
	delete_os_disk_on_termination = true

	# Uncomment this line to delete the data disks automatically when deleting the VM
	delete_data_disks_on_termination = true

#	storage_image_reference {
#		publisher = "OpenLogic"
#		offer     = "CentOS-HPC"
#		sku       = "7.6"
#		version   = "latest"
#	}

	storage_image_reference {
		publisher = "Canonical"
		offer     = "UbuntuServer"
		sku       = "18.04-LTS"
		version   = "latest"
	}


	storage_os_disk {
		name              = "osdisk${count.index+1}"
		caching           = "ReadWrite"
		create_option     = "FromImage"
		managed_disk_type = "StandardSSD_LRS"
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
		computer_name  = "hpc-${lower(var.app_name)}-vm${count.index+1}"
		admin_username = "ansible"
	}
	os_profile_linux_config {
		disable_password_authentication = "true"

		ssh_keys {
			path     = "/home/ansible/.ssh/authorized_keys"
			key_data = "${file("~/ansible.key.pub")}"
		}
	}
	
}

resource "null_resource" "prep_ansible" {
	triggers = {
		build_number = "${timestamp()}"
	}
	depends_on = ["azurerm_virtual_machine.vm"]

	provisioner "local-exec" {
		command = "echo [all] ${join(" ", azurerm_public_ip.pip.*.ip_address)} | tr \" \" \"\n\" > ansible.hosts"
	}
}

output "pips_for_ansible_hosts" {
	value = "${azurerm_public_ip.pip.*.ip_address}"
}

output "ime" {
	value = "${formatlist("%s", azurerm_public_ip.pip.*.ip_address)}"
}

# ssh -i ~/ansible.key ansible@1.2.3.4
# ansible-playbook hpc-fvcom.yml -i ansible.hosts