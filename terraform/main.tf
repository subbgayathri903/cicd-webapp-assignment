
# --------------------------------------------------
# 1. TERRAFORM AND AWS PROVIDER CONFIGURATION
# --------------------------------------------------

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.23.0, < 7.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}


# --------------------------------------------------
# 2. AWS ECR - PRIVATE DOCKER IMAGE REGISTRY
# --------------------------------------------------

resource "aws_ecr_repository" "webapp" {
  name                 = "cicd-webapp"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "cicd-webapp"
  }
}


# --------------------------------------------------
# 3. VPC AND NETWORKING
# --------------------------------------------------

# Get available availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Create VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "cicd-webapp-vpc"
  }
}

# Create public subnet
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "cicd-webapp-public-subnet"
  }
}

# Create Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "cicd-webapp-igw"
  }
}

# Create public route table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "cicd-webapp-public-rt"
  }
}

# Associate route table with public subnet
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}


# --------------------------------------------------
# 4. SECURITY GROUP
# --------------------------------------------------

resource "aws_security_group" "webapp" {
  name        = "cicd-webapp-sg"
  description = "Allow HTTP traffic to the application"
  vpc_id      = aws_vpc.main.id

  # Allow HTTP traffic on port 80
  ingress {
    description = "Allow HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "cicd-webapp-sg"
  }
}


# --------------------------------------------------
# 5. IAM ROLE AND PERMISSIONS
# --------------------------------------------------

# Allow EC2 to assume this role
resource "aws_iam_role" "ec2_role" {
  name = "cicd-webapp-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"

      Principal = {
        Service = "ec2.amazonaws.com"
      }

      Action = "sts:AssumeRole"
    }]
  })
}

# Allow EC2 to pull images from ECR
resource "aws_iam_role_policy_attachment" "ecr_read" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Allow EC2 to communicate with Systems Manager
resource "aws_iam_role_policy_attachment" "ssm_access" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Create IAM instance profile
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "cicd-webapp-ec2-profile"
  role = aws_iam_role.ec2_role.name
}


# --------------------------------------------------
# 6. AMAZON LINUX 2023 AMI
# --------------------------------------------------

data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}


# --------------------------------------------------
# 7. EC2 INSTANCE
# --------------------------------------------------

resource "aws_instance" "webapp" {
  ami                         = data.aws_ssm_parameter.al2023_ami.value
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.webapp.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  associate_public_ip_address = true

  # Install Docker during instance startup
  user_data = <<-EOF
    #!/bin/bash
    dnf update -y
    dnf install -y docker
    dnf install -y docker-compose-plugin
    systemctl enable docker
    systemctl start docker
    usermod -aG docker ec2-user
  EOF

  # Require IMDSv2
  metadata_options {
    http_tokens = "required"
  }

  # Encrypt root storage
  root_block_device {
    encrypted = true
  }

  tags = {
    Name = "cicd-webapp-server"
  }

  depends_on = [
    aws_route_table_association.public
  ]
}
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]
}

resource "aws_iam_role" "github_actions" {
  name = "cicd-webapp-github-actions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }

        Action = "sts:AssumeRoleWithWebIdentity"

        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"

            "token.actions.githubusercontent.com:sub" = "repo:subbgayathri903@360585437/cicd-webapp-assignment@1469868876:ref:refs/heads/main"
          }
        }
      }
    ]
  })

  tags = {
    Name = "cicd-webapp-github-actions-role"
  }
}
resource "aws_iam_role_policy" "github_actions_deploy" {
  name = "cicd-webapp-github-actions-deploy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "ECRAuthentication"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Sid    = "PushToSpecificECRRepository"
        Effect = "Allow"
        Action = [
            "ecr:BatchCheckLayerAvailability",
            "ecr:BatchGetImage",
            "ecr:CompleteLayerUpload",
            "ecr:InitiateLayerUpload",
            "ecr:PutImage",
            "ecr:UploadLayerPart"
        ]
        Resource = aws_ecr_repository.webapp.arn
      },
      {
        Sid    = "DeployToSpecificEC2Instance"
        Effect = "Allow"
        Action = [
          "ssm:SendCommand"
        ]
        Resource = [
          aws_instance.webapp.arn,
          "arn:aws:ssm:${var.aws_region}::document/AWS-RunShellScript"
        ]
      },
      {
        Sid    = "CheckDeploymentStatus"
        Effect = "Allow"
        Action = [
          "ssm:GetCommandInvocation",
          "ssm:ListCommandInvocations"
        ]
        Resource = "*"
      }
    ]
  })
}