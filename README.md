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
I have created the `set_keys.sh` bash script to load the variables from .env file to session without manually running multiple commands in terminal:

```
#!/usr/bin/bash
dos2unix.exe .env
set -o allexport
source .env
set +o allexport
```

### Terraform instances


