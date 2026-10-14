variable "vm_host" {
  description = "Public IP or hostname of the VM running Docker"
  type        = string
}

variable "ssh_user" {
  description = "SSH user with access to the Docker socket (created by Ansible)"
  type        = string
  default     = "deployer"
}

variable "ssh_private_key_path" {
  description = "Private key used to reach the VM over SSH"
  type        = string
  default     = "~/.ssh/ansible_key"
}

variable "nginx_image" {
  description = "nginx image with a pinned tag"
  type        = string
  default     = "nginx:1.27-alpine"
}

variable "container_name" {
  description = "Name of the nginx container"
  type        = string
  default     = "tf-nginx"
}

variable "network_name" {
  description = "Name of the dedicated Docker network"
  type        = string
  default     = "tf-nginx-net"
}

variable "network_subnet" {
  description = "Subnet of the dedicated Docker network"
  type        = string
  default     = "172.30.0.0/24"

  validation {
    condition     = can(cidrhost(var.network_subnet, 1))
    error_message = "network_subnet must be a valid CIDR, e.g. 172.30.0.0/24."
  }
}

variable "volume_name" {
  description = "Name of the volume holding the site content"
  type        = string
  default     = "tf-nginx-html"
}

variable "external_port" {
  description = "Non-standard host port published for nginx"
  type        = number
  default     = 8080

  validation {
    condition     = var.external_port >= 1024 && var.external_port <= 65535
    error_message = "external_port must be a non-standard unprivileged port (1024-65535)."
  }
}
