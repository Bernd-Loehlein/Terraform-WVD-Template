terraform {
    // Terraform 0.12 required for object variables
    required_version = ">= 0.12"
}

resource "azurerm_availability_set" "avset" {
  count               = var.availability_set ? 1 : 0
  name                = "avset-${var.session_host_prefix}"
  location            = var.resource_group.location
  resource_group_name = var.resource_group.name
}

resource "azurerm_network_interface" "NIC" {
    count               = var.session_host_count
    name                = "${var.session_host_prefix}-${count.index}-NIC-01"
    location            = var.resource_group.location
    resource_group_name = var.resource_group.name
    ip_configuration {
        name                            = "IP-Configuration-${var.session_host_prefix}-${count.index}"
        subnet_id                       = var.subnet.id
        private_ip_address_allocation   = "Dynamic"
    }  
}

resource "azurerm_windows_virtual_machine" "Session-Host" {
    count                       = var.session_host_count
    name                        = "${var.session_host_prefix}-${count.index}"
    location                    = var.resource_group.location
    resource_group_name         = var.resource_group.name
    network_interface_ids       = [element(azurerm_network_interface.NIC.*.id, count.index)]
    availability_set_id         = var.availability_set ? azurerm_availability_set.avset.0.id : null
    size                        = var.session_host_size
    enable_automatic_updates    = "true"
    admin_username              = var.admin_username
    admin_password              = var.admin_password
    license_type                = "Windows_Client"

    os_disk {
        name                    = "${var.session_host_prefix}-${count.index}-os-disk"
        caching                 = "ReadWrite"
        storage_account_type    = var.os_disk_type == null ? "StandardSSD_LRS" : var.os_disk_type
    }

    source_image_id             = var.source_image_id == null ? null : var.source_image_id

    dynamic "source_image_reference" {
        for_each = var.source_image_id == null ? [1] : []
        content {
            publisher             = var.image_publisher
            offer                 = var.image_offer
            sku                   = var.image_sku
            version               = var.image_version == null ? "latest" : var.image_version
        }
    }
}

resource "azurerm_virtual_machine_extension" "LogAnalytics" {
    count                       = var.session_host_count
    name                        = "${element(azurerm_windows_virtual_machine.Session-Host.*.name, count.index)}-LogAnalytics"
    virtual_machine_id          = element(azurerm_windows_virtual_machine.Session-Host.*.id, count.index)
    publisher                   = "Microsoft.EnterpriseCloud.Monitoring"
    type                        = "MicrosoftMonitoringAgent"
    type_handler_version        = "1.0"
    auto_upgrade_minor_version  = true
    settings                    = <<SETTINGS
    {
        "workspaceId": "${var.workspace.workspace_id}"
    }
SETTINGS

    protected_settings          = <<PROTECTED_SETTINGS
    {
        "workspaceKey": "${var.workspace.primary_shared_key}"
    }
PROTECTED_SETTINGS
}

resource "azurerm_virtual_machine_extension" "DomainJoin" {
    count                       = var.session_host_count
    name                        = "${element(azurerm_windows_virtual_machine.Session-Host.*.name, count.index)}-domainJoin"
    virtual_machine_id          = element(azurerm_windows_virtual_machine.Session-Host.*.id, count.index)
    publisher                   = "Microsoft.Compute"
    type                        = "JsonADDomainExtension"
    type_handler_version        = "1.3"
    auto_upgrade_minor_version  = true
    depends_on                  = [azurerm_virtual_machine_extension.LogAnalytics]
    lifecycle {
      ignore_changes = [ 
          settings,
          protected_settings
       ]
    }
    settings                = <<SETTINGS
    {
        "Name": "${var.domain_fqdn}",
        "User": "${var.domain_username}",
        "OUPath": "${var.domain_oupath}",
        "Restart": "true",
        "Options": "3"
    }
SETTINGS

    protected_settings      = <<PROTECTED_SETTINGS
    {
        "Password": "${var.domain_password}"
    }
PROTECTED_SETTINGS
}

resource "azurerm_virtual_machine_extension" "WVD-DSC" {
    lifecycle {
      ignore_changes = [settings]
    }
    count                       = var.session_host_count
    name                        = "${element(azurerm_windows_virtual_machine.Session-Host.*.name, count.index)}-WVD-DSC"
    virtual_machine_id          = element(azurerm_windows_virtual_machine.Session-Host.*.id, count.index)
    publisher                   = "Microsoft.Powershell"
    type                        = "DSC"
    type_handler_version        = "2.80"
    auto_upgrade_minor_version  = true
    depends_on                  = [azurerm_virtual_machine_extension.LogAnalytics, azurerm_virtual_machine_extension.DomainJoin]
    settings                    = <<-SETTINGS
    {
        "configuration" : {
            "url": "https://wvdportalstorageblob.blob.core.windows.net/galleryartifacts/Configuration.zip",
            "script": "Configuration.ps1",
            "function": "AddSessionHost"
        },
        "configurationArguments": {
            "HostPoolName": "${var.hostpool_name}"
        }
    }
    SETTINGS
    protected_settings = <<-PROTECTED_SETTINGS
    {
        "configurationArguments" : {
            "registrationInfoToken": "${var.hostpool_token}" 
        }
    }
    PROTECTED_SETTINGS
}

resource "azurerm_virtual_machine_extension" "GPU-Drivers" {
    count                       = var.gpu_vendor != null ? var.session_host_count : 0
    name                        = "${element(azurerm_windows_virtual_machine.Session-Host.*.name, count.index)}-GPU-Driver"
    virtual_machine_id          = element(azurerm_windows_virtual_machine.Session-Host.*.id, count.index)
    publisher                   = "Microsoft.HpcCompute"
    type                        = var.gpu_vendor == "nvidia" ? "NvidiaGpuDriverWindows" : var.gpu_vendor == "amd" ? "AmdGpuDriverWindows" : ""
    type_handler_version        = var.gpu_vendor == "nvidia" ? "1.3" : var.gpu_vendor == "amd" ? "1.0" : ""
    auto_upgrade_minor_version  = true
    depends_on                  = [azurerm_virtual_machine_extension.LogAnalytics, azurerm_virtual_machine_extension.DomainJoin, azurerm_virtual_machine_extension.WVD-DSC]
    settings                    = ""
}