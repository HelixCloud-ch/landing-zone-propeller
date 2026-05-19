---
inclusion: auto
---

# LLM Wiki — Steering Instructions

## Knowledge Base Location

The project knowledge base lives in `var/kiro/`. Before making architectural
decisions or writing infrastructure code, consult the wiki:

- **Index**: `var/kiro/index.md` — find relevant pages
- **Schema**: `var/kiro/schema.md` — wiki conventions and workflows
- **Log**: `var/kiro/log.md` — recent operations

## Workflow Rules

1. **Before writing IaC**: check relevant wiki pages for established patterns and decisions
2. **After learning something new**: update or create wiki pages
3. **When making decisions**: create an ADR in `var/kiro/wiki/decisions/`
4. **When ingesting new sources**: follow the ingest workflow in schema.md
5. **Periodically**: lint the wiki for consistency

## Validation Requirements

Before any Terraform code enters the repository:
- Validate AWS resource configurations against AWS documentation (aws-docs MCP)
- Validate Terraform resource/attribute names against the registry (terraform-docs MCP)
- Ensure alignment with patterns documented in the wiki

## Public Repository Discipline

This is a public repository. Every commit must be:
- Free of secrets, account IDs, and internal URLs
- Well-documented with clear commit messages
- Consistent with established project conventions
- Reviewed for security implications

## Language

All code, documentation, variable names, function names, comments, wiki content,
and commit messages MUST be written in English regardless of the language used
in conversation.
