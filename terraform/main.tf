module "frontend" {
  source  = "terraform-aws-modules/ec2-instance/aws"
#   key_name = aws_key_pair.vpn.key_name  # we dont need key as we are using our own AMI
  name = "${var.project_name}-${var.environment}-${var.common_tags.Component}"

  instance_type          = "t3.micro"
  vpc_security_group_ids = [data.aws_ssm_parameter.frontend_sg_id.value]
  # convert StringList to list and get first element
  subnet_id = local.public_subnet_id
  ami = data.aws_ami.ami_info.id
  
  tags = merge(
    var.common_tags,
    {
        Name = "${var.project_name}-${var.environment}-${var.common_tags.Component}"
    }
  )
}

# to run remote execute we are suing null resource

resource "null_resource" "frontend" {
    triggers = {
      instance_id = module.frontend.id # this will be triggered everytime instance is created
    }
  # we establish connections
    connection {
      type     = "ssh"
      user     = "ec2-user"
      password = "DevOps321"
      host     = module.frontend.private_ip  
    }

    provisioner "file" {   #we use provisioner to copy the file
      source      = "${var.common_tags.Component}.sh"
      destination = "/tmp/${var.common_tags.Component}.sh"
    }

    provisioner "remote-exec" {   #after copying fie we use remote exec provisoner to run 
        inline = [
          "chmod +x /tmp/${var.common_tags.Component}.sh",  # we gave here exec permisiion
          "sudo sh /tmp/${var.common_tags.Component}.sh ${var.common_tags.Component} ${var.environment} ${var.app_version}"  # app vesrion added
        ]
    } 
}

# we use state to stop the server to take AMI

resource "aws_ec2_instance_state" "frontend" {
  instance_id = module.frontend.id
  state       = "stopped"  # check if you enables the env
  # stop the serever only when null resource provisioning is completed
  depends_on = [ null_resource.frontend ]
}

# we take AMI

resource "aws_ami_from_instance" "frontend" {
  name               = "${var.project_name}-${var.environment}-${var.common_tags.Component}"
  source_instance_id = module.frontend.id
  depends_on = [ aws_ec2_instance_state.frontend ]
}

# we terminate the server
resource "null_resource" "frontend_delete" {
    triggers = {
      instance_id = module.frontend.id # this will be triggered everytime instance is created
    }

    provisioner "local-exec" {  # we use provisoner to run and delete the instance
        command = "aws ec2 terminate-instances --instance-ids ${module.frontend.id}"
    } 

    depends_on = [ aws_ami_from_instance.frontend ]
}

# target group creation

resource "aws_lb_target_group" "frontend" {
  name     = "${var.project_name}-${var.environment}-${var.common_tags.Component}"
  port     = 80 
  protocol = "HTTP"
  vpc_id   = data.aws_ssm_parameter.vpc_id.value
  health_check {
    path                = "/"
    port                = 80
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200-299"
  }
}

resource "aws_launch_template" "frontend" {
  name = "${var.project_name}-${var.environment}-${var.common_tags.Component}"

  image_id = aws_ami_from_instance.frontend.id
  instance_initiated_shutdown_behavior = "terminate"
  instance_type = "t3.micro"
  update_default_version = true # sets the latest version to default

  vpc_security_group_ids = [data.aws_ssm_parameter.frontend_sg_id.value]

  tag_specifications {
    resource_type = "instance"

    tags = merge(
      var.common_tags,
      {
        Name = "${var.project_name}-${var.environment}-${var.common_tags.Component}"
      }
    )
  }
}

# auto sacling group 

resource "aws_autoscaling_group" "frontend" {
  name                      = "${var.project_name}-${var.environment}-${var.common_tags.Component}"
  max_size                  = 5
  min_size                  = 1
  health_check_grace_period = 60
  health_check_type         = "ELB"
  desired_capacity          = 1
  target_group_arns = [aws_lb_target_group.frontend.arn]
  launch_template {    # launch configuration is old we use laund template
    id      = aws_launch_template.frontend.id
    version = "$Latest"
  }
  vpc_zone_identifier       = split(",", data.aws_ssm_parameter.public_subnet_ids.value) # to launch in privat esubnet

  instance_refresh {
    strategy = "Rolling"  # 
    preferences {
      min_healthy_percentage = 50
    }
    triggers = ["launch_template"]  
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-${var.environment}-${var.common_tags.Component}"
    propagate_at_launch = true
  }

  timeouts {
    delete = "15m"
  }

  tag {
    key                 = "Project"
    value               = "${var.project_name}"
    propagate_at_launch = false
  }
}

# auto scaling policy

resource "aws_autoscaling_policy" "frontend" {
  name                   = "${var.project_name}-${var.environment}-${var.common_tags.Component}"
  policy_type            = "TargetTrackingScaling"
  autoscaling_group_name = aws_autoscaling_group.frontend.name

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"  # the metric is cpu utilization
    }

    target_value = 10.0  # we gave 10 to check and generate new instance 
  }
}


#add listner rule
resource "aws_lb_listener_rule" "frontend" {
  listener_arn = data.aws_ssm_parameter.web_alb_listener_arn_https.value  #
  priority     = 100 # less number will be first validated from the rules

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }

  condition {
    host_header {
      values = ["web-${var.environment}.${var.zone_name}"]
    }
  }
}