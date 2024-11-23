terraform {
  required_providers {
    aws = {
        source = "hashicorp/aws"
        version = "~> 5.0.0"
    }
  }
  required_version = "~> 1.9.8"
}

provider "aws" {
  profile = "bds"
  region = var.aws_region
}

data "aws_availability_zones" "available" {
  state = "available"
}

// create vpc
resource "aws_vpc" "warehouse_vpc" {
  cidr_block = var.vpc_cidr_block
  tags = {
    Name = "warehouse"
  }
}


// create internet gateway for vpc
resource "aws_internet_gateway" "warehouse_igw" {
  vpc_id = aws_vpc.warehouse_vpc.id
  tags = {
    Name = "warehouse_igw"
  }
}


// create a group of public subnets based on the variable subnet_count.public
resource "aws_subnet" "warehouse_public_subnet" {
  count = var.subnet_count.public
  vpc_id = aws_vpc.warehouse_vpc.id
  cidr_block = var.public_subnet_cidr_blocks[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name = "warehouse_public_subnet_${count.index}"
  }
}

// create a group of private subnets based on the variable subnet_count.private
resource "aws_subnet" "warehouse_private_subnet" {
  count = var.subnet_count.private
  vpc_id = aws_vpc.warehouse_vpc.id
  cidr_block = var.private_subnet_cidr_blocks[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name = "warehouse_private_subnet_${count.index}"
  }
}


// create public route table
resource "aws_route_table" "warehouse_public_rt" {
  vpc_id = aws_vpc.warehouse_vpc.id
  route  {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.warehouse_igw.id
  }
}

resource "aws_route_table_association" "public" {
  count = var.subnet_count.public
  route_table_id = aws_route_table.warehouse_public_rt.id
  subnet_id = aws_subnet.warehouse_public_subnet[count.index].id
}

// create private route table
resource "aws_route_table" "warehouse_private_rt" {
  vpc_id = aws_vpc.warehouse_vpc.id
}

resource "aws_route_table_association" "private" {
  count = var.subnet_count.private
  route_table_id = aws_route_table.warehouse_private_rt.id
  subnet_id = aws_subnet.warehouse_private_subnet[count.index].id
}

// create s3 vpc endpoint
resource "aws_vpc_endpoint" "s3" {
  vpc_id = aws_vpc.warehouse_vpc.id
  service_name = "com.amazonaws.${var.aws_region}.s3"
}

resource "aws_vpc_endpoint_route_table_association" "s3_route_table_association" {
  route_table_id = aws_route_table.warehouse_private_rt.id
  vpc_endpoint_id = aws_vpc_endpoint.s3.id
}

data "aws_prefix_list" "s3" {
  prefix_list_id = aws_vpc_endpoint.s3.prefix_list_id
}

// create security group for the EC2 instance
resource "aws_security_group" "warehouse_bastion_sg" {
  name = "warehouse_bastion_sg"
  description = "Security group for warehouse db bastion server"
  vpc_id = aws_vpc.warehouse_vpc.id
  ingress {
    description = "Allow SSH from client computer"
    from_port = "22"
    to_port = "22"
    protocol = "tcp"
    cidr_blocks = ["${var.my_ip}/32"]
  }
  egress{
    description = "Allow all outbound traffic"
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "warehouse_bastion_sg"
  }
}

// create security group for the lambda
resource "aws_security_group" "refresh_lambda_sg" {
  name = "refresh_lambda_sg"
  description = "Security group for warehouse db refresh lambda function"
  vpc_id = aws_vpc.warehouse_vpc.id
  egress{
    description = "Allow all outbound traffic"
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "refresh_lambda_sg"
  }
}

// create security group for the RDS instance
resource "aws_security_group" "warehouse_db_sg" {
  name = "warehouse_db_sg"
  description = "Security group for warehouse db"
  vpc_id = aws_vpc.warehouse_vpc.id
  ingress {
    description = "Allow postgres traffic only from the bastion sg"
    from_port = "5432"
    to_port = "5432"
    protocol = "tcp"
    security_groups = [aws_security_group.warehouse_bastion_sg.id, aws_security_group.refresh_lambda_sg.id]
  }
  egress{
    description = "Allow all outbound traffic to S3"
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = data.aws_prefix_list.s3.cidr_blocks
  }
  tags = {
    Name = "warehouse_db_sg"
  }
}

// create db subnet group
resource "aws_db_subnet_group" "warehouse_db_subnet_group" {
  name = "warehouse_db_subnet_group"
  description = "DB subnet group for warehouse"
  subnet_ids = [for subnet in aws_subnet.warehouse_private_subnet : subnet.id]
}

// create IAM role for RDS EC2 assumption
resource "aws_iam_role" "rds_ec2_s3_role" {
  assume_role_policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "sts:AssumeRole"
        ],
        "Principal": {
          "Service": [
            "rds.amazonaws.com"
          ]
        }
      }
    ]
  })
  tags = {
    Name = "rds_ec2_s3_iam_role"
  }
}

// create IAM policy to allow required s3 actions
resource "aws_iam_policy" "rds_ec2_s3_policy" {
  name = "ec2-iam-s3-policy"
  path = "/"
  policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Action" : [
            "s3:GetObject", 
            "s3:ListBucket"
          ],
          "Effect" : "Allow",
          "Resource" : [
            "${aws_s3_bucket.s3_bucket.arn}",
            "${aws_s3_bucket.s3_bucket.arn}/*"
          ]
        },
      ]
    }
  )
  tags = {
    Name = "rds_ec2_s3_policy"
  }
}

// attach IAM policy to the role
resource "aws_iam_policy_attachment" "rds_ec2_s3_role_policy" {
  policy_arn = aws_iam_policy.rds_ec2_s3_policy.arn
  roles = [aws_iam_role.rds_ec2_s3_role.name]
  name = "rds_ec2_s3_policy_att"
}


// create warehouse db instance
resource "aws_db_instance" "warehouse_database" {
  allocated_storage = var.settings.database.allocated_storage
  engine = var.settings.database.engine
  engine_version = var.settings.database.engine_version
  instance_class = var.settings.database.instance_class
  db_name = var.settings.database.db_name
  username = var.db_username
  password = var.db_password
  db_subnet_group_name = aws_db_subnet_group.warehouse_db_subnet_group.id
  vpc_security_group_ids = [aws_security_group.warehouse_db_sg.id]
  skip_final_snapshot = var.settings.database.skip_final_snapshot
}

// assosicate S3 role with warehouse db instance
resource "aws_db_instance_role_association" "rds_s3_role_ass" {
  db_instance_identifier = aws_db_instance.warehouse_database.identifier
  feature_name = "s3Import"
  role_arn = aws_iam_role.rds_ec2_s3_role.arn
}


// create a keypair for warehouse bastion
resource "aws_key_pair" "warehouse_kp" {
  key_name = "warehouse_kp"
  public_key = file("warehouse_kp.pub")
}

// create aws linux data object
data "aws_ami" "amazonlinux" {
  most_recent      = true
  owners           = ["amazon"]
 
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
 
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
 
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
 
}


// create EC2 bastion instance
resource "aws_instance" "warehouse_bastion" {
  count = var.settings.bastion.count
  ami = data.aws_ami.amazonlinux.id
  instance_type = var.settings.bastion.instance_type
  subnet_id = aws_subnet.warehouse_public_subnet[count.index].id
  key_name = aws_key_pair.warehouse_kp.key_name
  vpc_security_group_ids = [aws_security_group.warehouse_bastion_sg.id]
  tags = {
    Name = "warehouse_bastion_${count.index}"
  }
}

// create elastic IP for EC2 instance
resource "aws_eip" "warehouse_bastion_eip" {
  count = var.settings.bastion.count
  instance = aws_instance.warehouse_bastion[count.index].id
  vpc = true
  tags = {
    Name = "warehouse_bastion_eip_${count.index}"
  }
}

// create an S3 bucket
resource "aws_s3_bucket" "s3_bucket" {
  bucket = "s3-test-bucket-ct"
  tags = {
    Name = "s3_bucket"
  }
}



data "aws_iam_policy_document" "AWSLambdaTrustPolicy" {
  version = "2012-10-17"
  statement {
    actions = ["sts:AssumeRole"]
    effect = "Allow"
    principals {
      type = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "refresh_lambda_role" {
  assume_role_policy = data.aws_iam_policy_document.AWSLambdaTrustPolicy.json
  name = "refresh_lambda_role"
}

resource "aws_iam_role_policy_attachment" "refresh_lambda_role_basic_policy_attachment" {
  role = aws_iam_role.refresh_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "refresh_lambda_role_vpc_policy_attachment" {
  role = aws_iam_role.refresh_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_lambda_function" "refresh_lambda" {
  code_signing_config_arn = ""
  description = ""
  filename = "./lambda/the_package.zip"
  function_name = "refresh-lambda"
  role = aws_iam_role.refresh_lambda_role.arn
  handler = "refresh.lambda_handler"
  runtime = "python3.8"
  //source_code_hash = filebase64sha256(data.archive_file.refresh_lambda.output_path)
  vpc_config {
    subnet_ids = [for subnet in aws_subnet.warehouse_public_subnet : subnet.id]
    security_group_ids = [aws_security_group.refresh_lambda_sg.id]
  }
  environment {
    variables = {
      RDS_HOST = aws_db_instance.warehouse_database.address
      RDS_PORT = aws_db_instance.warehouse_database.port
      RDS_ETL_USER = "etluser"
      RDS_ETL_PASS = "warehouse"
      RDS_DB_NAME = "warehouse"
    }
  }
}

resource "aws_cloudwatch_event_rule" "warehouse_refresh_schedule" {
  name = "warehouse-refresh-schedule"
  description = "Refresh the warehouse raw database every five minutes"
  schedule_expression = "cron(30 18 ? * 2 *)"
}

resource "aws_cloudwatch_event_target" "warehouse_refresh_target" {
  rule = aws_cloudwatch_event_rule.warehouse_refresh_schedule.name
  target_id = "refresh_lambda"
  arn = aws_lambda_function.refresh_lambda.arn
}

resource "aws_lambda_permission" "allow_cloud_watch_to_call_refresh" {
  statement_id = "AllowExecutionFromCloudWatch"
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.refresh_lambda.function_name
  principal = "events.amazonaws.com"
  source_arn = aws_cloudwatch_event_rule.warehouse_refresh_schedule.arn
}