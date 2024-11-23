// the aws region everything will be created in
variable "aws_region" {
    default = "us-east-1"
} 

// CIDR block for vpc (chunk of IP addresses for routing within the vpc)
variable "vpc_cidr_block" {
    description = "CIDR block for VPC"
    type = string
    default = "10.0.0.0/16"
}

// number of public and private subnets
variable "subnet_count" {
    description = "Number of subnets"
    type = map(number)
    default = {
        public = 1,
        private = 2
    }
}

// settings for EC2 and RDS instances
variable "settings" {
    description = "Configuration settings"
    type = map(any)
    default = {
        "database" = {
            allocated_storage = 5
            engine = "postgres"
            engine_version = "16.3"
            instance_class = "db.t3.micro"
            db_name = "postgres"
            skip_final_snapshot = true
        },
        "bastion" = {
            count = 1
            instance_type = "t2.micro"
        }
    }
}

// CIDR block for public subnet
variable "public_subnet_cidr_blocks" {
    description = "Available CIDR blocks for public subnets"
    type = list(string)
    default = [
        "10.0.1.0/24",
        "10.0.2.0/24",
        "10.0.3.0/24",
        "10.0.4.0/24"
    ]
}

// CIDR block for private subnet
variable "private_subnet_cidr_blocks" {
    description = "Available CIDR blocks for private subnets"
    type = list(string)
    default = [
        "10.0.101.0/24",
        "10.0.102.0/24",
        "10.0.103.0/24",
        "10.0.104.0/24"
    ]
}

// IP address of client machine, used for setting up SSH rule for security group
variable "my_ip" {
    description = "Client IP Address"
    type = string
    default = "69.207.90.118"
}

// DB master user username
variable "db_username" {
    description = "Database master user"
    type = string
    default = "postgres"
}

// DB master user password
variable "db_password" {
    description = "Database master user password"
    type = string
    default = "roottoot"
}

