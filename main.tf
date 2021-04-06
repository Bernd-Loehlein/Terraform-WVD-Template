terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
    random = {
      source = "hashicorp/random"
    }
    template = {
      source = "hashicorp/azuread"
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

provider "azuread" {
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
  # This will update registration token on every terraform run
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

resource "azurerm_virtual_desktop_workspace" "workspace" {
  name                = "Windows Virtual Desktop Workspace"
  location            = azurerm_resource_group.wvd.location
  resource_group_name = azurerm_resource_group.wvd.name

  friendly_name = "Windows Virtual Desktop Workspace"
  description   = "Windows Virtual Desktop Workspace"
}

resource "azurerm_virtual_desktop_workspace_application_group_association" "applicationgroup" {
  workspace_id         = azurerm_virtual_desktop_workspace.workspace.id
  application_group_id = azurerm_virtual_desktop_application_group.applicationgroup.id
}

# User/Group assignment for application group
data "azuread_group" "wvd-access" {
  display_name = "WVD-Access"
}

resource "azurerm_role_assignment" "wvd-access" {
  scope                = azurerm_virtual_desktop_application_group.applicationgroup.id
  role_definition_name = "Desktop Virtualization User"
  principal_id         = data.azuread_group.wvd-access.object_id
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

# Log Analytics association for WVD objects
resource "azurerm_monitor_diagnostic_setting" "hostpool" {
  name                        = "log_analytics_all"
  target_resource_id          = azurerm_virtual_desktop_host_pool.hostpool.id
  log_analytics_workspace_id  = azurerm_log_analytics_workspace.wvd.id

  dynamic "log" {
    for_each = ["Checkpoint", "Error", "Management", "Connection", "HostRegistration", "AgentHealthStatus"]
    content {
      category = log.value
      enabled  = true
      retention_policy {
        enabled = false
        days    = 0
      }
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "applicationgroup" {
  name                        = "log_analytics_all"
  target_resource_id          = azurerm_virtual_desktop_application_group.applicationgroup.id
  log_analytics_workspace_id  = azurerm_log_analytics_workspace.wvd.id
  
  dynamic "log" {
    for_each = ["Checkpoint", "Error", "Management"]
    content {
      category = log.value
      enabled  = true
      retention_policy {
        enabled = false
        days    = 0
      }
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "workspace" {
  name                        = "log_analytics_all"
  target_resource_id          = azurerm_virtual_desktop_workspace.workspace.id
  log_analytics_workspace_id  = azurerm_log_analytics_workspace.wvd.id
  
  dynamic "log" {
    for_each = ["Checkpoint", "Error", "Management", "Feed"]
    content {
      category = log.value
      enabled  = true
      retention_policy {
        enabled = false
        days    = 0
      }
    }
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
    session_host_size   = "Standard_D2as_v4"
    os_disk_type        = "StandardSSD_LRS"
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
    # cryptic replace needed as extension would still use the old token prior to the update during terraform run
    hostpool_token      = replace(azurerm_virtual_desktop_host_pool.hostpool.registration_info[0].token != null ? azurerm_virtual_desktop_host_pool.hostpool.registration_info[0].token : "",azurerm_virtual_desktop_host_pool.hostpool.registration_info[0].expiration_date,"")
    image_publisher     = "MicrosoftWindowsDesktop"
    image_offer         = "office-365"
    image_sku           = "20h1-evd-o365pp"
    image_version       = "latest"
}