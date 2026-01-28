#!/usr/bin/bash
SERVER=$(terraform output -raw prod_ip_public)
KEY=~/.ssh/terraform

scp -i  $KEY $KEY ec2-user@$SERVER:/home/ec2-user/.ssh/
ssh -i $KEY ec2-user@$SERVER