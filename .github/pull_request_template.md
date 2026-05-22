## Summary
<!-- What does this change do and why? -->

## Type of change
- [ ] New module or feature
- [ ] Bug fix
- [ ] Variable / config update
- [ ] PowerShell runbook change
- [ ] Documentation only

## Checklist
- [ ] `terraform fmt -recursive` has been run locally
- [ ] `terraform validate` passes locally
- [ ] Plan output in the bot comment looks correct (no unintended destroys)
- [ ] Sensitive values are NOT hardcoded — secrets go in GitHub Secrets or Automation Variables
- [ ] Any new resources have `tags = var.tags` applied
- [ ] PowerShell scripts tested manually on the Hybrid Worker before merging
