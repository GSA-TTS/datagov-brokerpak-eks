
resource "aws_ssm_maintenance_window" "window" {
  name     = "${local.cluster_name}-maintenance-window"
  schedule = "cron(0 16 ? * * *)"
  duration = 3
  cutoff   = 1
}

resource "aws_ssm_maintenance_window_target" "owned-instances" {
  window_id     = aws_ssm_maintenance_window.window.id
  name          = "${local.cluster_name}-instances"
  description   = "The set of EC2 instances owned by ${local.cluster_name}"
  resource_type = "INSTANCE"

  targets {
    key    = "tag:kubernetes.io/cluster/${local.cluster_name}"
    values = ["owned"]
  }
}

resource "aws_ssm_maintenance_window_task" "patch-vulnerabilities" {
  name            = "${local.cluster_name}-patching"
  max_concurrency = 2
  max_errors      = 1
  priority        = 1
  task_arn        = "AWS-RunPatchBaseline"
  task_type       = "RUN_COMMAND"
  window_id       = aws_ssm_maintenance_window.window.id

  targets {
    key    = "WindowTargetIds"
    values = [aws_ssm_maintenance_window_target.owned-instances.id]
  }

  task_invocation_parameters {
    run_command_parameters {
      timeout_seconds      = 600

      parameter {
        name   = "Operation"
        values = ["Install"]
      }
    }
  }
}
