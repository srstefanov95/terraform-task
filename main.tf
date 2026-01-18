provider "aws" {
  region = "us-east-1"
}

resource "aws_instance" "my-first-server" {
  ami = "ami-059afa9e3a9c7af0c"
  instance_type = "t4g.micro"
  tags = {
    Name = "amazon-linux"
  }
}