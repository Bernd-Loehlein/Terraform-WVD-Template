variable "availability_set" {
    description     = "Create an availability set for the session hosts"
    type            = bool
    default         = false
}

variable "session_host_prefix" {
    description     = "Prefix for the session host name"
    type            = string
    default         = "wvd-sh"
}

variable "session_host_count" {
    description     = "Number of session hosts deployed"
    type            = number
    default         = 1
}

variable "session_host_size" {
    description     = "VM size of the session host"
    type            = string
    default         = "Standard_D4s_v3"
}

variable "os_disk_type" {
    description     = "Storage-Type to use for os-disk"
    default         = "Premium_LRS"
}

variable "resource_group" {
    description     = "Resource group for session host"
    type            = object({
        name        = string
        location    = string
    })
}

variable "subnet" {
    description     = "Subnet for session host"
    type            = object({
        id          = string
    })
}

variable "admin_username" {
    description     = "Username for local admin user"
    type            = string
}

variable "admin_password" {
    description     = "Password for local admin user"
    type            = string
}

variable "domain_fqdn" {
    description     = "Fully-Qualified Domain-Name of the Active Directory Domain"
    type            = string
}

variable "domain_oupath" {
    description     = "Path to the OU where the computer account will be created"
    type            = string
}

variable "domain_username" {
    description     = "Username used for domain join"
    type            = string
}

variable "domain_password" {
    description     = "Password used for domain join"
    type            = string
}

variable "workspace" {
    description     = "ID for the Log Analytics workspace"
    type            = object({
        workspace_id       = string,
        primary_shared_key = string
    })
}

variable "hostpool_name" {
    description     = "Name of the WVD Hostpool"
    type            = string
}

variable "hostpool_token" {
    description     = "Registration-Token for the WVD Hostpool"
    type            = string
}

variable "source_image_id" {
    description     = "ID of the image to use for the hosts"
    default         = null
}

variable "image_publisher" {
    description     = "Publisher for the image"
    default         = null
}

variable "image_offer" {
    description     = "Offer for the image"
    default         = null
}

variable "image_sku" {
    description     = "SKU for the image"
    default         = null
}

variable "image_version" {
    description     = "Version for the image"
    default         = "latest"
}

variable "gpu_vendor" {
    description     = "Vendor of the utilized GPU"
    default         = null
}