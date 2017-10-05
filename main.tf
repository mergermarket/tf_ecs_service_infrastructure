module "dns" {
  source = "github.com/mergermarket/tf_route53_dns"

  domain = "${var.dns_domain}"
  name   = "${var.dns_name != "" ? var.dns_name : replace("${lookup(var.release, "component")}", "/-service$/", "")}"
  env    = "${var.env}"
  target = "${var.alb_dns_name}"
}

module "listener_rule_home" {
  source = "github.com/mergermarket/tf_alb_listener_rules"

  alb_listener_arn = "${var.alb_listener_arn}"
  target_group_arn = "${module.service.target_group_arn}"

  host_condition    = "${module.dns.fqdn}"
  starting_priority = "${var.alb_listener_rule_priority}"
}

module "ecs_update_monitor" {
  source = "github.com/mergermarket/tf_ecs_update_monitor"

  cluster = "${var.ecs_cluster}"
  service = "${module.service.name}"
  taskdef = "${module.taskdef.arn}"
}

module "service" {
  source = "github.com/mergermarket/tf_load_balanced_ecs_service"

  name            = "${var.env}-${lookup(var.release, "component")}"
  cluster         = "${var.ecs_cluster}"
  task_definition = "${module.taskdef.arn}"
  vpc_id          = "${var.platform_config["vpc"]}"
  container_name  = "${lookup(var.release, "component")}"
  container_port  = "${var.port}"
  desired_count   = "${var.desired_count}"
}

module "taskdef" {
  source = "github.com/mergermarket/tf_ecs_task_definition"

  family                = "${var.env}-${lookup(var.release, "component")}"
  container_definitions = ["${module.service_container_definition.rendered}"]
}

module "service_container_definition" {
  source = "github.com/mergermarket/tf_ecs_container_definition.git"

  name           = "${lookup(var.release, "component")}"
  image          = "${lookup(var.release, "image_id")}"
  cpu            = "${var.cpu}"
  memory         = "${var.memory}"
  container_port = "${var.port}"

  container_env  = "${merge(
    map(
      "LOGSPOUT_CLOUDWATCHLOGS_LOG_GROUP_STDOUT", "${var.env}-${lookup(var.release, "component")}-stdout",
      "LOGSPOUT_CLOUDWATCHLOGS_LOG_GROUP_STDERR", "${var.env}-${lookup(var.release, "component")}-stderr",
      "STATSD_HOST", "172.17.42.1",
      "STATSD_PORT", "8125",
      "STATSD_ENABLED", "true",
      "ENV_NAME", "${var.env}",
      "COMPONENT_NAME",  "${lookup(var.release, "component")}",
      "VERSION",  "${lookup(var.release, "version")}"
    ),
    var.common_application_environment,
    var.application_environment,
    var.secrets
  )}"

  labels {
    component        = "${lookup(var.release, "component")}"
    env              = "${var.env}"
    team             = "${lookup(var.release, "team")}"
    version          = "${lookup(var.release, "version")}"
    logentries_token = "${var.logentries_token}"
  }
}

resource "aws_cloudwatch_log_group" "stdout" {
  name              = "${var.env}-${lookup(var.release, "component")}-stdout"
  retention_in_days = "7"
}

resource "aws_cloudwatch_log_group" "stderr" {
  name              = "${var.env}-${lookup(var.release, "component")}-stderr"
  retention_in_days = "7"
}
