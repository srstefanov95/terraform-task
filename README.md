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

First, I created a VPC with range of `10.0.0.0/16`, a Public Subnet within this VPC with range of `10.0.0.0/24` and a private isolated subnet of `10.0.1.0/25.

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

resource "aws_subnet" "private_subnet_isolated" {
  vpc_id = aws_vpc.my_network.id
  cidr_block = "10.0.1.0/25"
  availability_zone = "us-east-1a"
  tags={
    Name = "Isolated Subnet"
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
Then I created an elastic (public) IP which will be exposed to the internet and will be used to connect to the public instance through my local machine. The EIP is associated with the ENI (named `eni1`) and its private  ip of `10.0.0.50`.

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

For the private subnet, we only need to provide connection to the public subnet in the same VPC. To achieve this we need to again provision a route table and route table association. Notice that we do neet to describe a specific route, providing the vpc id is enough.

```
resource "aws_route_table" "private_route_table_isolated" {
  vpc_id = aws_vpc.my_network.id
}

resource "aws_route_table_association" "private_association_isolated" {
  subnet_id = aws_subnet.private_subnet_isolated.id
  route_table_id = aws_route_table.private_route_table_isolated.id
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

And a separate instance for the private subnet is created too. Notice that the security group is attached here, because this instance has no ENI attached to it.
```
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
<img width="580" height="187" alt="image" src="https://github.com/user-attachments/assets/f4124bc7-204d-43c2-88b7-64379abc9c97" />


### Testing connectivity
Once we have ran `terraform apply` and resource have been created, we can now test our infrastructe.
We will do this in 2 steps.
1. SSH to public instance via its EIP, using the private key from the provided `aws_key_pair` resource which is named `mykey`. The private key is located on my local machine. Once inside the public instance we will run the httpd service, hosting a simple web page. Additionally, we will use the ping command.

<img width="594" height="161" alt="image" src="https://github.com/user-attachments/assets/c2b4b4ee-26df-40c8-b5db-d8ac0b87da1b" />
<img width="797" height="511" alt="image" src="https://github.com/user-attachments/assets/4b2cab89-5821-4c5d-9f51-c1540bdc7b80" />

2. Once SSH inside the public instance we can test connectivity to the private isolated instance.
   <img width="580" height="243" alt="image" src="https://github.com/user-attachments/assets/1dce3fc5-514f-4a39-9765-01608ba1cc08" />

2.1. Now, in order to jump from public instance to private one, we will once again need the private RSA key (copy it from local machine to EC2). To avoid doing this manually each time I have provisioned this simple bash script. It stores the terraform output of public EC2 EIP as variable and first copies the key, then connects into the instance via SSH. In this way we are already setup.

```
#!/usr/bin/bash
SERVER=$(terraform output -raw prod_ip_public)
KEY=~/.ssh/terraform

scp -i  $KEY $KEY ec2-user@$SERVER:/home/ec2-user/.ssh/
ssh -i $KEY ec2-user@$SERVER
```
When connected to public EC2, we can verify that key is there.
<img width="601" height="141" alt="image" src="https://github.com/user-attachments/assets/509bd006-0261-43da-89ff-1af40d41e0a4" />

> [!IMPORTANT]
> The above screenshot shows that everyone has read permissions to this private key, making it insecure. Running the SSH command with this key resulted in error. I had to run `chmod 400 ~/.ssh/terraform` to make it accessible only to ec2-user.

2.2. Now we connect to private instance in the same way and test:

<img width="1101" height="711" alt="image" src="https://github.com/user-attachments/assets/1af9eeb4-5dc9-4466-9910-a6e897314837" />







