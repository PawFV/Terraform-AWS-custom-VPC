terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "4.66.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# 1. Create vpc
resource "aws_vpc" "terra-vpc" {
  cidr_block = "10.0.0.0/16" 

  tags = {
    Name = "production"
  }
}

# 2. Create Internet Gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.terra-vpc.id

  tags = {
    Name = "main"
  }
}

# 3. Create Custom Route Table
resource "aws_route_table" "terra-rt" {
  vpc_id = aws_vpc.terra-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "production"
  }
}

# 4. Create a Subnet
resource "aws_subnet" "subnet-1" {
  vpc_id                  = aws_vpc.terra-vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1d"

  tags = {
   Name = "public" 
  }
}

# 5. Associate subnet with Route Table
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.subnet-1.id
  route_table_id = aws_route_table.terra-rt.id
}

# 6. Create Security Group to allow port 22,80,443
resource "aws_security_group" "allow-web" {
  name        = "terra-SG"
  description = "Allows TLS allow port inbound traffic on ports 22,80,443"
  vpc_id      = aws_vpc.terra-vpc.id

  ingress {
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }
  
  ingress {
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  ingress {
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_tls"
  }
}

# 7. Create a network interface with an ip in the subnet that was created in step 4
resource "aws_network_interface" "terra-network" {
  subnet_id       = aws_subnet.subnet-1.id
  private_ips     = ["10.0.1.50"]
  security_groups = [aws_security_group.allow-web.id]
}

# 8. Assign an elastic IP to the network interface created in step 7
resource "aws_eip" "one" {
  vpc                       = true
  network_interface         = aws_network_interface.terra-network.id
  associate_with_private_ip = "10.0.1.50"
  depends_on                = [aws_internet_gateway.gw, aws_instance.web-server-instance]
}

# 9. Create Ubuntu server and install/enable apache2
resource "aws_instance" "web-server-instance" {
  ami               = "ami-0889a44b331db0194"
  instance_type     = "t2.micro"
  availability_zone = "us-east-1d"
  key_name          = "main"

  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.terra-network.id
  }

  user_data = <<-EOF
                #!/bin/bash
                sudo yum update -y
                sudo yum install httpd -y
                sudo systemctl start httpd
                sudo systemctl enable httpd
                sudo bash -c 'echo your very first web server > /var/www/html/index.html'
                EOF
  tags = {
    Name = "web-server"
  }
}