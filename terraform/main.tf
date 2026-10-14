terraform {
  required_version = ">= 1.6"

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 4.6"
    }
  }
}

# Talks to the Docker daemon on the VM over SSH as deployer (created by Ansible,
# member of the docker group), so no Docker API port is exposed to the network
provider "docker" {
  host     = "ssh://${var.ssh_user}@${var.vm_host}:22"
  ssh_opts = ["-i", pathexpand(var.ssh_private_key_path), "-o", "StrictHostKeyChecking=yes"]
}

# Dedicated network: this nginx is isolated from the Compose stack (stage 5),
# which lives in its own network
resource "docker_network" "nginx" {
  name   = var.network_name
  driver = "bridge"

  ipam_config {
    subnet  = var.network_subnet
    gateway = cidrhost(var.network_subnet, 1)
  }
}

# Named volume with the site content; survives container re-creation
resource "docker_volume" "nginx_html" {
  name = var.volume_name
}

resource "docker_image" "nginx" {
  name         = var.nginx_image
  keep_locally = true
}

resource "docker_container" "nginx" {
  name    = var.container_name
  image   = docker_image.nginx.image_id
  restart = "unless-stopped"

  networks_advanced {
    name = docker_network.nginx.name
  }

  volumes {
    volume_name    = docker_volume.nginx_html.name
    container_path = "/usr/share/nginx/html"
  }

  # Written into the volume before the container starts
  upload {
    file    = "/usr/share/nginx/html/index.html"
    content = file("${path.module}/files/index.html")
  }

  ports {
    internal = 80
    external = var.external_port
  }

  healthcheck {
    test     = ["CMD", "wget", "-q", "--spider", "http://127.0.0.1/"]
    interval = "30s"
    timeout  = "5s"
    retries  = 3
  }
}
