variable "project_name" {
  default = "expense"
}

variable "environment" {
  default = "dev"
}

variable "common_tags" {
  default = {
    Project = "expense"
    Environment = "dev"
    Terraform = "true"
    Component = "frontend"  #for billing purpose we give mandotry tag, #extra tag
  }
}

variable "zone_name" {
  default = "devopsme.online"
}

# created this as part of jenkins CD
variable "app_version" {
  
}