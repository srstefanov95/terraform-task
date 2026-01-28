data "aws_ssm_parameter" "al2023_standard" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_instance" "prod-server" {
  ami = data.aws_ssm_parameter.al2023_standard.value
  instance_type = "t3.micro"
  availability_zone = "us-east-1a"
  key_name = aws_key_pair.mykey.key_name

  network_interface {
    network_interface_id = aws_network_interface.eni1.id
    device_index = 0
  }

  user_data = <<-EOF
      #!/usr/bin/bash
      dnf update -y
      dnf install -y httpd

      systemctl enable httpd
      systemctl start httpd

      echo "<h1>Ralitsa, I Love You <3 </h1><br/><p>I want to spend the rest of my life with you here</p><img src='https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcQVdwgRGAlflxXkYNktyfXJEv76lIa-31CI4w&s' />" > /var/www/html/index.html
    EOF
  
  tags = {
    Name = "al2023_standard"
  }
}

resource "aws_instance" "private-isolated-server" {
  ami = data.aws_ssm_parameter.al2023_standard.value
  instance_type = "t3.micro"
  availability_zone = "us-east-1a"
  key_name = aws_key_pair.mykey.key_name
  subnet_id = aws_subnet.private_subnet_isolated.id
  security_groups = [ aws_security_group.ssh_sg.id ]
  
  tags = {
    Name="Private Isolated Server"
    description="Connects only to public subnet and vice versa."
  }
}