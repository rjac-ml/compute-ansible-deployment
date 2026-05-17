# Permissions for the Ansible-over-SSM workflow.
#
# Spec: specs/003-ansible-node-exporter/spec.md (FR-002, FR-007) +
#       research.md Finding 2 (IAM gaps that block the Ansible layer).
#
# The amazon.aws.aws_ssm connection plugin needs three buckets of perms
# from the role that the GitHub Actions runner assumes:
#
#   1. SSM session/command lifecycle (start, send, describe, terminate)
#   2. EC2 describe (used by the dynamic inventory plugin to enumerate
#      target hosts by tag — see ansible/inventories/aws/dynamic.aws_ec2.yml)
#   3. S3 read/write on the SSM staging bucket — already covered by the
#      existing `s3_data_buckets` policy in main.tf, which grants s3:* on
#      `arn:aws:s3:::${var.data_bucket_prefix}-*`. The SSM staging bucket
#      name follows the pattern `compute-ansible-<account>-<region>-ansible-ssm`,
#      which matches `compute-ansible-*`, so no new S3 grant is needed here.
#
# This file is intentionally NEW (not appended to main.tf) so the diff is
# easy to review and easy to revert. The added permissions are scoped to
# the same OIDC-assumable role created in main.tf via `role` reference.

resource "aws_iam_role_policy" "ansible_ssm" {
  name = "ansible-ssm"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # SSM session + command lifecycle — needed by amazon.aws.aws_ssm
      # connection plugin to open sessions and run commands on EC2.
      {
        Sid    = "SsmSessionAndCommand"
        Effect = "Allow"
        Action = [
          "ssm:StartSession",
          "ssm:TerminateSession",
          "ssm:ResumeSession",
          "ssm:SendCommand",
          "ssm:GetCommandInvocation",
          "ssm:ListCommandInvocations",
          "ssm:ListCommands",
          "ssm:CancelCommand",
          "ssm:DescribeInstanceInformation",
          "ssm:DescribeSessions",
          "ssm:GetConnectionStatus",
        ]
        # Scoping ssm:* by Resource is messy because session ARNs are
        # generated at call time and ec2:DescribeInstances doesn't accept
        # resource scoping. The actions above are read/operate-only on
        # instances in this account; further scoping is enforced by the
        # OIDC trust policy (branch + repo) in main.tf.
        Resource = "*"
      },

      # The SSM SendCommand path goes through a managed document.
      # Restricting to the documents Ansible actually uses keeps the blast
      # radius tight even if the role were ever assumed elsewhere.
      {
        Sid    = "SsmAllowedDocuments"
        Effect = "Allow"
        Action = ["ssm:GetDocument", "ssm:DescribeDocument"]
        Resource = [
          "arn:${local.partition}:ssm:${local.region}:${local.account_id}:document/AWS-RunShellScript",
          "arn:${local.partition}:ssm:${local.region}:${local.account_id}:document/AWS-StartInteractiveCommand",
          "arn:${local.partition}:ssm:*::document/AWS-RunShellScript",
          "arn:${local.partition}:ssm:*::document/AWS-StartInteractiveCommand",
        ]
      },

      # EC2 describe — used by the dynamic inventory plugin in
      # ansible/inventories/aws/dynamic.aws_ec2.yml to list which
      # instances match the tag selector. Read-only.
      {
        Sid    = "Ec2DescribeForDynamicInventory"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus",
          "ec2:DescribeTags",
          "ec2:DescribeRegions",
          "ec2:DescribeAvailabilityZones",
        ]
        Resource = "*"
      },
    ]
  })
}
