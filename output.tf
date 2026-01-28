output "prod_ip_public" {
  value = aws_eip.public_ip.public_ip
  description = "Prod Server's Public IP address"
}

output "prod_ip_private" {
  value = aws_network_interface.eni1.private_ip
  description = "Prod Server's Private IP address"
}

output "isolated_ip" {
    value = aws_instance.private-isolated-server.private_ip
    description = "Isolated Server private IP address"
}