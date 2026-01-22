provider "aws" {
  region = "us-east-1"
}

resource "aws_key_pair" "mykey" {
  key_name = "mykey"
  public_key = file("~/.ssh/terraform.pub")
}

data "aws_ssm_parameter" "al2023_standard" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_instance" "my-first-server" {
  ami = data.aws_ssm_parameter.al2023_standard.value
  instance_type = "t3.micro"
  availability_zone = "us-east-1a"
  key_name = aws_key_pair.mykey.key_name

  network_interface {
    network_interface_id = aws_network_interface.eni1.id
    device_index = 0
  }  
  
  tags = {
    Name = "al2023_standard"
  }
}

resource "aws_vpc" "my_network" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support = true

  tags={
    Name = "Simeon's Network"
  }
}

resource "aws_subnet" "public_subnet" {
  vpc_id = aws_vpc.my_network.id
  cidr_block = "10.0.0.0/24"
  availability_zone = "us-east-1a"
  tags={
    Name = "Public Subnet"
  }
}

resource "aws_network_interface" "eni1" {
  subnet_id = aws_subnet.public_subnet.id
  private_ips = ["10.0.0.50"]
  security_groups = [ aws_security_group.ssh_sg.id ]

  depends_on = [ 
    aws_vpc.my_network,
    aws_subnet.public_subnet,
    aws_internet_gateway.my_gateway,
    aws_route_table.my_route_table,
    aws_route_table_association.public_association
  ]

  tags = {
    Name= "Public Interface"
  }
}

resource "aws_eip" "public_ip" {
  network_interface = aws_network_interface.eni1.id
  associate_with_private_ip = "10.0.0.50"

  depends_on = [ 
    aws_instance.my-first-server,
    aws_subnet.public_subnet,
    aws_internet_gateway.my_gateway,
    aws_route_table.my_route_table,
    aws_route_table_association.public_association
  ]

  tags = {
    Name = "Public/Elastic IP"    
  }
}

resource "aws_route_table" "my_route_table" {
  vpc_id = aws_vpc.my_network.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.my_gateway.id
  }

  tags = {
    Name = "public-route-table"
  }
}

resource "aws_route_table_association" "public_association" {
  subnet_id = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.my_route_table.id
}

variable "allowed_ports" {
  type    = list(number)
  default = [22, 80, 443]
}

resource "aws_security_group" "ssh_sg" {
  name        = "allow_ssh"
  description = "Allow SSH inbound"
  vpc_id      = aws_vpc.my_network.id

  dynamic "ingress" {
    for_each = var.allowed_ports
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]  # or 0.0.0.0/0 for testing
    }
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_internet_gateway" "my_gateway" {
  vpc_id = aws_vpc.my_network.id
  tags={
    Name = "Internet Gateway"
  }
}

