output "instance_public_ip" {
  description = "Public IP address of the Flask app EC2 instance"
  value       = aws_instance.flask_app.public_ip
}

output "app_url" {
  description = "URL to access the application through nginx on port 80"
  value       = "http://${aws_instance.flask_app.public_ip}"
}

output "flask_direct_url" {
  description = "Direct URL to Flask bypassing nginx (port 5000)"
  value       = "http://${aws_instance.flask_app.public_ip}:5000"
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "ssh -i ~/.ssh/${var.key_pair_name}.pem ec2-user@${aws_instance.flask_app.public_ip}"
}
