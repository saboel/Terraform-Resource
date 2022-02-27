//define a provider: A plugin that allows us to talk to a 
//specific set of API's EX: AWS 

# Configure the AWS Provider
provider "aws" {
  region = "us-east-2"
   access_key = "secret"
   secret_key = "secret"
}

//creating an instance || vpc 
resource "aws_vpc" "my_vpc" {
  cidr_block = "172.16.0.0/16"

  tags = {
    Name = "production"
  }
}

#2. Create Internet Gateway 

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.my_vpc.id 
}

#3. Create Custom Route Table 

resource "aws_route_table" "prod-route-table" {
  vpc_id = aws_vpc.my_vpc.id

  route {
    cidr_block = "0.0.0.0/0" //default route (all traffic(ipv4) will be sent here)
    gateway_id = aws_internet_gateway.gw.id
  }

  route {
    ipv6_cidr_block        = "::/0"
    gateway_id =  aws_internet_gateway.gw.id
  }

  tags = {
    Name = "prod"
  }
}

#4. Create a Subnet 

//referencing vpc id 
resource "aws_subnet" "my_subnet" {
  vpc_id            = aws_vpc.my_vpc.id //this value will get the ID of the vpc that gets created from line above
  cidr_block        = "172.16.10.0/24"
  availability_zone = "us-east-2a"

  tags = {
    Name = "prod-subnet"
  }
}

#5. Associate subnet with Route Table 

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.my_subnet.id
  route_table_id = aws_route_table.prod-route-table.id
}

#6. Create a Security Group to allow ports: 22,80,443 

resource "aws_security_group" "allow_web" {
  name        = "allow_web_traffic"
  description = "Allow web inbound traffic"
  vpc_id      = aws_vpc.my_vpc.id

  ingress { //allow tcp on port 443.
    description      = "HTTPS"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"] //what subnets can reach this block 
  }
  ingress { //allow tcp on port 80.
    description      = "HTTP"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp" //All web-traffic is TCP 
    cidr_blocks      = ["0.0.0.0/0"] //what subnets can reach this block 
  }
  ingress { //allow tcp on port 22.
    description      = "SSH"
    from_port        = 22
    to_port          = 22 
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"] //what subnets can reach this block 
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1" //Any protocol
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "allow_web"
  }
}

#7. Create a Network Interface with an IP in the subnet that was created in step 4 

resource "aws_network_interface" "web-server-sab" {
  subnet_id       = aws_subnet.my_subnet.id
  private_ips     = ["172.16.10.50"] //what IP do we want to give our server? 
  security_groups = [aws_security_group.allow_web.id]


}

#8. Assign an elastic IP to the network interface created in step 7 (requires deploying internet gateway 1st)

resource "aws_eip" "one" {
  vpc                       = true
  network_interface         = aws_network_interface.web-server-sab.id
  associate_with_private_ip = "172.16.10.50"
  depends_on = [aws_internet_gateway.gw] //ref the whole object not ID 
}


#9. Create Ubuntu Server and Install/enable apache2 


resource "aws_instance" "web-server-instance" {
    ami = "ami-0fb653ca2d3203ac1"
    instance_type = "t2.micro"
    availability_zone = "us-east-2a"
    key_name = "main-key"

    network_interface {
      device_index = 0 
      network_interface_id = aws_network_interface.web-server-sab.id
    }

    user_data =<<-EOF
        #!/bin/bash
        sudo apt update -y 
        sudo apt install apache2 -y
        sudo systemctl start apache2
        sudo bash -c 'echo demon on > /var/www/html/index.html'
        EOF
    
    tags = {
        Name = "web-server"
    }
    
}

