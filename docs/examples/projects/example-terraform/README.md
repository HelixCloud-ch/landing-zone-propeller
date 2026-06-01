# example-terraform

Minimal Terraform project. Reads one input from a sibling project
(`example-script`) and writes it to an SSM parameter. Demonstrates:

- The expected `terraform/` directory layout.
- Pipeline inputs as Terraform variables.
- A single output that downstream projects could consume.
- The standard backend convention from `project.yaml`.

Use this as a starting point for new Terraform-based projects.
