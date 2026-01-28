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
- Assigned **AmazonEC2FullAccess** and **PowerUserAccess** policies to 

