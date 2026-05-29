# Sub2API Terraform

This directory is the standalone Terraform root for the production Sub2API
service. It reuses shared Vega infrastructure through the existing Vega prod
remote state, including the VPC, ECS cluster, ECR repository, task roles,
security groups, log groups, and placeholder Secrets Manager secrets.

## State

The root uses its own state key:

```text
s3://vega-terraform-state-prod-us-west-1/sub2api/prod/terraform.tfstate
```

It reads shared Vega state from:

```text
s3://vega-terraform-state-prod-us-west-1/vega/prod/terraform.tfstate
```

## First Deployment

The current Sub2API resources were originally declared in the Vega backend
Terraform root. Before applying this root against existing prod resources,
migrate or import state so Terraform does not try to recreate resources with
the same names.

Typical workflow:

```sh
terraform init
terraform plan -var 'sub2api_image_tag=<immutable-image-tag>'
```

If prod resources already exist, move/import their state into this root before
`terraform apply`.

## GitHub Actions Deployment

`.github/workflows/deploy-aws.yml` deploys automatically after the `CI` workflow
succeeds on a push to `main`. It can also be run manually with
`workflow_dispatch`.

By default, the workflow uses this dedicated Sub2API deployment role:

```text
arn:aws:iam::939169265111:role/vega-prod-sub2api-github-actions-deploy
```

You can override it with the GitHub repository variable used by the Vega backend
prod deployment convention:

```text
AWS_PROD_DEPLOY_ROLE_ARN
```

Alternatively, set a repository/environment secret named `AWS_DEPLOY_ROLE_ARN`.

The role should trust GitHub Actions OIDC for this repository's `prod`
environment and have permission to push to the Sub2API ECR repository,
read/write the Terraform S3 state and lock table, read the shared Vega remote
state, and manage the AWS resources declared in this Terraform root.

Optional GitHub repository variables:

```text
AWS_REGION=us-west-1
SUB2API_ECR_REPOSITORY=vega-sub2api
```
