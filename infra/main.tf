terraform {
  required_providers {
     aws = {
           source =""
           version =""
    
    }
  }
}


resource "aws_vpc" "myvpc" {
    
    cidr_block = var.vpc_cidr
}
resource "aws_subnet" "pubsub1" {
    
    vpc_id = aws_vpc.myvpc.id
    cidr_block = var.pubsub1_cidr
    availability_zone = var.pubsub1_availability_zone

}
resource "aws_subnet" "pubsub2" {
     vpc_id= aws_vpc.myvpc.id
     cidr_block = var.pubsub2_cidr
     availability_zone = var.pubsub2_availability_zone
}
resource "aws_subnet" "privatesub1" {
    
    vpc_id = aws_vpc.myvpc.id
    cidr_block = var.privatesub1_cidr
    availability_zone = var.privatesub1_availability_zone

}
resource "aws_subnet" "privatesub2" {
     vpc_id= aws_vpc.myvpc.id
     cidr_block = var.privatesub2_cidr
     availability_zone = var.privatesub2_availability_zone
}

resource "aws_internet_gateway" "igw" {
    vpc_id= aws_vpc.myvpc.id
}
resource "aws_route_table" "rt" {
    vpc_id =aws_vpc.myvpc.id

    route {

        cidr_block ="0.0.0.0/0"
        gateway_id =aws_internet_gateway.igw.id
    }

}
resource "aws_route_table_association" "rta" {
    route_table_id = aws_route_table.rt.id
    subnet_id =  aws_subnet.pubsub1.id

}
resource "aws_route_table_association" "rta1" {
    route_table_id = aws_route_table.rt.id
    subnet_id=  aws_subnet.pubsub1.id

}
# private route table
resource "aws_route_table" "prt" {
  vpc_id = aws_vpc.myvpc.id
  #depends_on = [aws_nat_gateway.nat_gateway]
  tags = {
    Name = "rivateroutetable"
  }
}
resource "aws_route_table_association" "prtba" {

    route_table_id = aws_route_table.prt.id
    subnet_id = aws_subnet.privatesub1.id
  
}
resource "aws_route_table_association" "prtba1" {

    route_table_id = aws_route_table.prt.id
    subnet_id = aws_subnet.privatesub2.id
  
}
resource "aws_security_group" "sg" {

    vpc_id=aws_vpc.myvpc.id

    ingress {
        description = "SSH from VPC"
        cidr_blocks=["0.0.0.0/0"]
        from_port= "22"
        to_port  ="22"
        protocol ="tcp"

    }
    ingress {
       description = "HTTP from VPC"
       cidr_blocks=["0.0.0.0/0"]
        from_port= "80"
        to_port  ="80"
        protocol ="tcp" 
    }
    ingress {
    description = "Allow HTTP request from anywhere"
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
  }

    
     egress  {
        from_port = "0"
        to_port = "0"
        protocol = "-1"
     }
}



resource "aws_security_group" "rds_mysql_sg" {
  name        = "rds_mysql_sg"
  description = "Allow access to RDS from EC2 present in public subnet"
  vpc_id      = aws_vpc.myvpc.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [aws_subnet.pubsub1.id]# replace with your EC2 instance security group CIDR block
  }
}

resource "aws_security_group" "ec2_sg_python_api" {
  name        = "ec2_sg_name_for_python_api"
  description = "Enable the Port 5000 for python api"
  vpc_id      = aws_vpc.myvpc.id

  # ssh for terraform remote exec
  ingress {
    description = "Allow traffic on port 5000"
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
  }

  tags = {
    Name = "Security Groups to allow traffic on port 5000"
  }
}
resource "aws_instance" "jenkins" {

     ami="ami-08b5b3a93ed654d19"
     vpc_security_group_ids  = [aws_security_group.sg.id,aws_security_group.ec2_sg_python_api.id]
     instance_type= "t2.micro"
     subnet_id = aws_subnet.pubsub1.id
     associate_public_ip_address ="true"
     user_data = templatefile("./template/ec2_install_apache.sh", {})
}

resource "aws_lb_target_group" "TG" {
    vpc_id = aws_vpc.myvpc.id
    port="5000"
    protocol = "HTTP"

    health_check {
      path ="/health"
      port = "5000"
      healthy_threshold ="6"
      unhealthy_threshold = "2"
      timeout = "2"
      interval = "5"
      matcher = "200"

    }
  
}


resource "aws_lb_target_group_attachment" "tga" {
   target_group_arn = aws_lb_target_group.TG.arn
   target_id = aws_instance.jenkins.id
   port="5000"
  
}


resource "aws_lb" "mylb" {
    name= "myloadbalancer"
    internal = "false"
    load_balancer_type = "application"
    security_groups = [aws_security_group.sg.id]
    subnets =[aws_subnet.pubsub1.id,aws_subnet.pubsub2.id]
  
}



resource "aws_lb_listener" "listener" {

    load_balancer_arn = aws_lb.mylb.arn
    port = "80"
    protocol ="HTTP"


    default_action {
       type ="forward"
       target_group_arn = aws_lb_target_group.TG.arn
    }
  
}

resource "aws_db_subnet_group" "dev_proje_1_db_subnet_group" {
  name       = "mysubnetgroup"
  subnet_ids = [aws_subnet.privatesub1.id,aws_subnet.privatesub2.id] # replace with your private subnet IDs
}
resource "aws_db_instance" "default" {
  allocated_storage       = 10
  storage_type            = "gp2"
  engine                  = "mysql"
  engine_version          = "5.7"
  instance_class          = "db.t2.micro"
  identifier              = var.mysql_db_identifier
  username                = var.mysql_username
  password                = var.mysql_password
  vpc_security_group_ids  = [aws_security_group.rds_mysql_sg.id]
  db_subnet_group_name    = aws_db_subnet_group.dev_proje_1_db_subnet_group.name
  db_name                 = var.mysql_dbname
  skip_final_snapshot     = true
  apply_immediately       = true
  backup_retention_period = 0
  deletion_protection     = false
}
