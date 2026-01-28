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

resource "aws_subnet" "private_subnet_isolated" {
  vpc_id = aws_vpc.my_network.id
  cidr_block = "10.0.1.0/25"
  availability_zone = "us-east-1a"
  tags={
    Name = "Isolated Subnet"
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
    aws_instance.prod-server,
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

resource "aws_route_table" "private_route_table_isolated" {
  vpc_id = aws_vpc.my_network.id
}

resource "aws_route_table_association" "public_association" {
  subnet_id = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.my_route_table.id
}

resource "aws_route_table_association" "private_association_isolated" {
  subnet_id = aws_subnet.private_subnet_isolated.id
  route_table_id = aws_route_table.private_route_table_isolated.id
}

resource "aws_internet_gateway" "my_gateway" {
  vpc_id = aws_vpc.my_network.id
  tags={
    Name = "Internet Gateway"
  }
}