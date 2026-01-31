# Terraform AWS Practice Project

## Task Overview:

1. Create vpc
2. Create Internet Gateway
3. Create Custom Route Table
4. Create a Public Subnet and route to Internet Gateway
5. Associate public subnet with Route Table
6. Create Security Group to allow port 22,80,443, ICMP
7. Create a network interface with a static private ip in the subnet that was created in step 4
8. Assign an elastic IP to the network interface created in step 7
9. Create Amazon Linux server instance and install/enable httpd to host a simple page
10. Attach network interface to instance and test internet connectivity, visit host page

## Bonus Task:
Create a private subnet with dynamic local IP with connectivity to instance in public subnet, but no connectivity to internet.

## Walktrough:
### Terraform setup and AWS connection
Before starting work on the project I have gone through these prerequisites:
- Created an AWS account and a user named `terraform` from which I will operate through.
- Assigned **AmazonEC2FullAccess** and **PowerUserAccess** policies to this user to be able to create and destroy resources.
> [!WARNING]
> These policies probably give broader permissions than needed for the purpose of IaC. A realistic policy configuration would have more granular and specific permissions, consider researching further.
- Generated a 4096 bit RSA key pair with `ssh-keygen -t rsa -b 4096 -f ~/.ssh/terraform`
- Changed the permission of private key to read only to prevent ssh errors `chmod 400 ~/.ssh/terraform`
- Assigned the RSA public key to the `terraform` user which will be used for terraform authentication
- Installed terraform locally and initiated the project with `terraform init` command

### Terraform configurations
I've created an AWS **provider** and specified the region. Also provided my public RSA key named `mykey`
```
provider "aws" {
  region = "us-east-1"
}

resource "aws_key_pair" "mykey" {
  key_name = "mykey"
  public_key = file("~/.ssh/terraform.pub")
}
```

> [!NOTE]
> I store my AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY in an .env file. A better approach would be to use AWS Secrets Manager.

Before running any terraform commands we have to provide the AWS session environment variables for the terraform API authentication.
I have created the `set_keys.sh` bash script to load the variables from .env file to session without manually running multiple commands in the terminal:

```
#!/usr/bin/bash
dos2unix.exe .env
set -o allexport
source .env
set +o allexport
```

### Network
<img width="1045" height="722" alt="image" src="https://github.com/user-attachments/assets/7c8560b6-67fa-4992-9f24-e5bdf7b87e63" />

First, I created a VPC with range of `10.0.0.0/16`, a Public Subnet within this VPC with range of `10.0.0.0/24`

```
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
```

Then I created an EIN resource which would later be attached to the EC2 instance in the public subnet. It is within the public subnet with a static private IP of `10.0.0.50` and a security group which will be described later on. 

> [!NOTE]
> I have added the `depends_on` property, ensuring that the described resources are created before the ENI. Otherwise, the ENI would sometimes be created before the vpc and subnet, resulting in a dynamic private ip different from the specified `10.0.0.50`.

```
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
```
Then I created an elastic (public) IP which will be exposed to the internet and will be used to connect to the instance through my local machine. The EIP is associated with the ENI (named `eni1`) and its private  ip of `10.0.0.50`.

```
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
```

Now we need an Internet Gateway which will expose our VPC and public subnet to the internet, making it accessible from the outside. Once the IGW is created, a route table is needed to route the traffic through the IGW. Finally, a route table association resource is linking the route table with the public subnet.

```
resource "aws_internet_gateway" "my_gateway" {
  vpc_id = aws_vpc.my_network.id
  tags={
    Name = "Internet Gateway"
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
``` 
### Security Group
We have to enable the following ports for the purpose of our task, otherwise the instances would be created but not reachable:
- Port 22 - for SSh
- Port 80, 443 - for HTTP/HTTPS and to host a simple httpd server
- ICMP to test internet connectivity with ping command

```
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
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

### Instance
Once we have our infrastructure setup, we can now create our EC2 instance. I am using the aws_ssm_parameter data source type to get the latest Amazon Linux image version.

```
data "aws_ssm_parameter" "al2023_standard" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}
```

Then I create the EC2. With the aws_ssm_parameter AMI, instance type is `t3.micro`, provide the key name for authentication and ssh connection. Then I attach my ENI to the EC2 and set it as default interface (index 0). Finally, I provide an `user_data` attribute which upon instance start:
- Updates packages
- Installs httpd
- Enables and starts the httpd process
- Runs a simple Hello HTML page in httpd
  
```
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

      echo "<h1>Hello from ${aws_eip.public_ip.public_ip}</h1>" > /var/www/html/index.html
    EOF
  
  tags = {
    Name = "Simeon's Server"
  }
}
```
### Outputs
I output my instances IPs for visibility. One of the outputs (prod_ip_public) is used in a bash script to connect via ssh.
```
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
```
<img width="575" height="279" alt="image" src="https://github.com/user-attachments/assets/24942c57-1abc-412c-99f3-e136ed3f2605" />

### Testing connectivity
Once we have ran `terraform apply` and resource have been created, we can now test our infrastructe.
Before




