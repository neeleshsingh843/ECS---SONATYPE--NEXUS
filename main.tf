data "aws_ami" "ecs_optimized" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-hvm-*-x86_64-ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["591542846629"]
}


resource "aws_efs_file_system" "nexus" {
  creation_token = "nexus-efs"
  encrypted      = true
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }
  tags = {
    Name = "nexus-efs"
  }
}

resource "aws_efs_mount_target" "nexus_az1" {
  file_system_id  = aws_efs_file_system.nexus.id
  subnet_id       = "subnet-0eaa90ec7079cd292" 
  security_groups = ["sg-047eb4330b6432247"]  
}

resource "aws_efs_mount_target" "nexus_az2" {
  file_system_id  = aws_efs_file_system.nexus.id
  subnet_id       = "subnet-0ffb81b3708cbb406"
  security_groups = ["sg-047eb4330b6432247"]
}

resource "aws_efs_access_point" "nexus_data" {
  file_system_id = aws_efs_file_system.nexus.id

  posix_user {
    uid = 200
    gid = 200
  }

  root_directory {
    path = "/data"
    creation_info {
      owner_gid = 200
      owner_uid = 200
      permissions = "770"
    }
  }
}

resource "aws_efs_access_point" "nexus_logs" {
  file_system_id = aws_efs_file_system.nexus.id

  posix_user {
    uid = 200
    gid = 200
  }

  root_directory {
    path = "/logs"
    creation_info {
      owner_gid = 200
      owner_uid = 200
      permissions = "770"
    }
  }
}

resource "aws_iam_instance_profile" "instance-profile" {
  name = "demo-instance_profile"
  role = aws_iam_role.role.name
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "role" {
  name                = "demo-ecs_role"
  path                = "/"
  assume_role_policy  = data.aws_iam_policy_document.assume_role.json
  managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role", "arn:aws:iam::aws:policy/AmazonElasticFileSystemClientReadWriteAccess", "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"]
}


resource "aws_ecs_cluster" "tst-cluster" {
  name = "demo-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_launch_template" "foobar" {
  name_prefix   = "test-lt"
  image_id      = data.aws_ami.ecs_optimized.id
  instance_type = "t3.large"
  iam_instance_profile {
    name = aws_iam_instance_profile.instance-profile.name
  }
  user_data = filebase64("${path.module}/user_data.sh")
}

resource "aws_autoscaling_group" "bar" {
  depends_on         = [aws_launch_template.foobar]
  availability_zones = ["ap-south-1a", "ap-south-1b"]
  desired_capacity   = 1
  max_size           = 1
  min_size           = 1

  launch_template {
    id      = aws_launch_template.foobar.id
    version = "$Latest"
  }
}

resource "aws_ecs_task_definition" "nexus" {
  family                   = "nexus-tdef"
  requires_compatibilities = ["EC2"]
  network_mode             = "bridge"
  cpu                      = "1524"
  memory                   = "4048"
  execution_role_arn       = "arn:aws:iam::194722397195:role/ecsTaskExecutionRole"
  task_role_arn            = "arn:aws:iam::194722397195:role/ecsTaskExecutionRole"

  container_definitions = jsonencode([
    {
      name      = "nexus"
      image     = "194722397195.dkr.ecr.ap-south-1.amazonaws.com/nexus:3.76.0"
      essential = true
      cpu       = 1524
      memory    = 4048

      portMappings = [
        {
          containerPort = 8081
          hostPort      = 8081
          protocol      = "tcp"
        }
      ]

      mountPoints = [
        {
          sourceVolume  = "nexus-efs-data"
          containerPath = "/opt/nexus/data"
          readOnly      = false
        },
        {
          sourceVolume  = "nexus-efs-logs"
          containerPath = "/opt/nexus/logs"
          readOnly      = false
        }
      ]
    }
  ])

  volume {
  name = "nexus-efs-data"

  efs_volume_configuration {
    file_system_id     = aws_efs_file_system.nexus.id
    root_directory     = "/"
    transit_encryption = "ENABLED"

    authorization_config {
      access_point_id = aws_efs_access_point.nexus_data.id
      iam             = "DISABLED"
    }
  }
}

volume {
  name = "nexus-efs-logs"

  efs_volume_configuration {
    file_system_id     = aws_efs_file_system.nexus.id
    root_directory     = "/"
    transit_encryption = "ENABLED"

    authorization_config {
      access_point_id = aws_efs_access_point.nexus_logs.id
      iam             = "DISABLED"
    }
  }
}
}

resource "aws_ecs_service" "demo-service" {
  name            = "nexus-service"
  cluster         = aws_ecs_cluster.tst-cluster.id
  task_definition = aws_ecs_task_definition.nexus.arn
  desired_count   = 1
}
