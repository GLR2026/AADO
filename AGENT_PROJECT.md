# AGENT_PROJECT.md

Project: AADO
Full name: Agente Autónomo de Desarrollo y Operaciones
Manifest version: 1.0.0
Status: F1 - Infraestructura mínima

---

## Purpose

AADO is an autonomous development and operations agent.

Its objective is to receive natural-language tasks, understand project
context, plan work, modify files, execute tools, test results, diagnose
failures, self-correct, preserve rollback capability and escalate difficult
problems when local reasoning is insufficient.

AADO is an independent project.

---

## Source of truth

Durable architectural decisions, requirements, risks and roadmap are defined
in the current AADO_MAESTRO document.

This file is the compact operational manifest for the AADO repository.

If this manifest conflicts with AADO_MAESTRO, the conflict must be reported
before changing durable project policy.

---

## Current phase

F1 - Infraestructura mínima

Immediate objectives:

1. Establish repository structure.
2. Establish private runtime storage outside Git.
3. Establish initial policy configuration.
4. Establish backup and rollback.
5. Prepare the operational host.
6. Install local runtime only after host/resource decision.
7. Execute smoke test.

---

## Paths

Repository:

C:\AADO

Private runtime:

C:\AADO_PRIVATE

The private runtime directory MUST NOT be committed to Git.

---

## Repository directories

config/
    Versioned configuration and policy files.

docs/
    Technical and bootstrap documentation.

scripts/
    Installation, diagnostics and maintenance scripts.

src/
    AADO source code.

tests/
    Tests and synthetic workloads.

---

## Private runtime directories

C:\AADO_PRIVATE\state
    Persistent task/session state.

C:\AADO_PRIVATE\logs
    Runtime logs.

C:\AADO_PRIVATE\outbox
    External consultation packages.

C:\AADO_PRIVATE\tmp
    Temporary files.

C:\AADO_PRIVATE\dumps
    Authorized diagnostic/data dumps.

C:\AADO_PRIVATE\backups
    Private backup artifacts.

---

## Safety

AADO must not:

- modify production without explicit authorization;
- spend money without explicit authorization;
- enable pay-as-you-go services without explicit authorization;
- modify credentials without explicit authorization;
- destroy data without rollback;
- modify the only working copy of code directly;
- commit secrets, dumps or runtime state;
- bypass watchdog limits;
- declare success without evidence.

---

## Git workflow

Main branch must not be modified directly by autonomous tasks.

Task work must use:

- task branches;
- worktrees;
- or another explicitly isolated workspace.

Suggested naming:

aado/task-<task-id>

---

## Verification

Possible evidence includes:

- tests;
- build results;
- command exit codes;
- browser verification;
- logs;
- screenshots;
- diffs;
- rollback verification.

Generated code alone is not proof of success.

---

## External AI

Strategy: local-first.

Commercial APIs with variable usage billing are disabled by default.

External recommendations are hypotheses and must be tested.

---

## Current Rabisu host

Baseline confirmed:

- Windows Server 2022 Datacenter Evaluation
- 2 vCPU
- 4 GB RAM
- approximately 40 GB disk
- Git for Windows 2.55.0.windows.5 installed
- candidate for upgrade/reinstallation

Do not assume this is the final hardware configuration.

---

## Sensitive information

Do not expose externally without sanitization:

- passwords;
- API keys;
- credentials;
- cookies;
- session tokens;
- private keys;
- .env files;
- database dumps;
- personal/customer data;
- C:\AADO_PRIVATE\dumps

---

## Runtime checklist

Before every task:

1. Correct project and objective?
2. Correct mode, permissions and rollback?
3. Enough context and sensitive paths known?
4. Exact evidence required for success?

---

## Improvement mandate

AADO should proactively identify worthwhile improvements even when a task
already succeeds.

Separate mandatory corrections from optional improvements.
