terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
    random = {
      source = "hashicorp/random"
    }
    template = {
      source = "hashicorp/template"
    }
  }
}

provider "azurerm" {
  environment     = "public"
  features {
    virtual_machine {
      delete_os_disk_on_deletion = true
    }
  }
}

# Ressource-Group
resource "azurerm_resource_group" "wvd" {
    name     = "rg-wvd"
    location = "westeurope"
}

# Networking
resource "azurerm_virtual_network" "wvd" {
  name                = "vnet-wvd"
  resource_group_name = azurerm_resource_group.wvd.name
  location            = azurerm_resource_group.wvd.location
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "wvd" {
  name                 = "subnet-wvd"
  resource_group_name  = azurerm_resource_group.wvd.name
  virtual_network_name = azurerm_virtual_network.wvd.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Windows Virtual Desktop objects
resource "azurerm_virtual_desktop_host_pool" "hostpool" {
  location            = azurerm_resource_group.wvd.location
  resource_group_name = azurerm_resource_group.wvd.name

  name                     = "HostPool"
  friendly_name            = "My new HostPool"
  validate_environment     = true
  description              = "HostPool: Pooled with max 50 sessions per host"
  type                     = "Pooled"
  maximum_sessions_allowed = 50
  load_balancer_type       = "DepthFirst"
  registration_info {
    expiration_date = timeadd(timestamp(), "24h")
  }
}

resource "azurerm_virtual_desktop_application_group" "applicationgroup" {
  name                = "AppGroup"
  location            = azurerm_resource_group.wvd.location
  resource_group_name = azurerm_resource_group.wvd.name

  type          = "Desktop"
  host_pool_id  = azurerm_virtual_desktop_host_pool.hostpool.id
  friendly_name = "Full Desktop"
  description   = "Published Desktop"
}

# Log Analytics
resource "azurerm_log_analytics_workspace" "wvd" {
    name                = "log-wvd"
    location            = azurerm_resource_group.wvd.location
    resource_group_name = azurerm_resource_group.wvd.name
    sku                 = "PerGB2018"
    retention_in_days   = 30
}

resource "azurerm_log_analytics_solution" "vminsights" {
    solution_name         = "VMInsights"
    location              = azurerm_resource_group.wvd.location
    resource_group_name   = azurerm_resource_group.wvd.name
    workspace_resource_id = azurerm_log_analytics_workspace.wvd.id
    workspace_name        = azurerm_log_analytics_workspace.wvd.name

    plan {
        publisher = "Microsoft"
        product   = "OMSGallery/VMInsights"
    }
}

# Session-Hosts
resource "random_password" "local" {
  length = 16
  special = true
  override_special = "_%@"
}

module "session_host" {
    source              = "./modules/session_host"
    availability_set    = false
    session_host_prefix = "WVD-SH"
    session_host_count  = 2
    session_host_size   = "Standard_Daas_v4"
    os_disk_type        = "Standard_LRS"
    resource_group      = azurerm_resource_group.wvd
    subnet              = azurerm_subnet.wvd
    admin_username      = "LocalAdmin"
    admin_password      = random_password.local.result
    domain_fqdn         = "domain.wvd"
    domain_oupath       = "OU=Computers,DC=domain,DC=wvd"
    domain_username     = "vmjoiner@domain.wvd"
    domain_password     = "YourHighSecurePassword"
    workspace           = azurerm_log_analytics_workspace.wvd
    hostpool_name       = azurerm_virtual_desktop_host_pool.hostpool.name
    hostpool_token      = replace(azurerm_virtual_desktop_host_pool.hostpool.registration_info[0].token != null ? azurerm_virtual_desktop_host_pool.hostpool.registration_info[0].token : "",azurerm_virtual_desktop_host_pool.hostpool.registration_info[0].expiration_date,"")
    image_publisher     = "MicrosoftWindowsDesktop"
    image_offer         = "office-365"
    image_sku           = "20h1-evd-o365pp"
    image_version       = "latest"
}