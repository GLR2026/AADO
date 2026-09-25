# R0004 — Proposal

## Objeto de auditoría

Auditar el cambio real AADO-COMM-002 correspondiente al commit:

650c9d7bac735787f578e763405a65ffa41ce8f7

Branch:

aado/task-comm-002-po-governance

El cambio agrega gobernanza PO y metadata de publicación al Round Manager.

## Objetivos funcionales

1. Registrar branch, commit exacto, PR, mergeability y timestamp.
2. Impedir sobrescritura silenciosa de metadata de publicación.
3. Registrar una decisión PO separada de la acción de merge.
4. Vincular APPROVED_FOR_MERGE a un commit exacto.
5. Bloquear APPROVED_FOR_MERGE cuando mergeability no sea clean.
6. Mantener approved_commit = null para CHANGES_REQUESTED o REJECTED.
7. No ejecutar merge automáticamente.
8. Mantener separación de estados y no alterar fases no relacionadas.

## Evidencia ya ejecutada

- aprobación con commit incorrecto fue bloqueada;
- sobrescritura de publication fue bloqueada;
- aprobación con mergeability=conflicts fue bloqueada;
- CHANGES_REQUESTED dejó approved_commit=null;
- R0002 permaneció intacta durante tests negativos;
- branch remota del PR coincide exactamente con commit 650c9d7.

## Alcance de la auditoría

Buscar errores de lógica, transiciones de estado inseguras, regex demasiado amplias,
condiciones de carrera conceptuales, problemas de integridad, posibilidades de
aprobar el commit equivocado, inconsistencias entre YAML y archivos Markdown,
problemas de idempotencia, sobrescrituras silenciosas, fallos de validación,
problemas de seguridad y mejoras de arquitectura.

No asumir que los tests existentes son suficientes.
