
resource "aws_ssm_maintenance_window" "window" {
  name     = "maintenance-window-webapp"
  schedule = "cron(0 16 ? * * *)"
  duration = 3
  cutoff   = 1
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
    key    = "tag:eks:cluster-name"
    values = [local.cluster_name]
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
