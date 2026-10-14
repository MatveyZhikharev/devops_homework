output "nginx_url" {
  description = "URL to check with curl -i"
  value       = "http://${var.vm_host}:${var.external_port}"
}

output "container_name" {
  value = docker_container.nginx.name
}

output "network_name" {
  value = docker_network.nginx.name
}

output "volume_name" {
  value = docker_volume.nginx_html.name
}
