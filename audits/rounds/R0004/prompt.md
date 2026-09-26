# AADO-COMM — Blind audit

Estás actuando como auditor técnico independiente.

IMPORTANTE:
- No conocés la respuesta del otro auditor.
- No votes ni intentes coincidir con otro modelo.
- Buscá errores aunque los tests existentes hayan pasado.
- No asumas que el implementador tiene razón.
- Separá hechos, hipótesis y recomendaciones.
- Priorizá integridad del flujo y posibilidad de aprobar o mergear algo incorrecto.

## Cambio a auditar

Commit:
650c9d7bac735787f578e763405a65ffa41ce8f7

Componente:
AADO-COMM-002 — PO Governance and publication guards.

## Objetivo esperado

El sistema debe:

1. registrar metadata de publicación sin sobrescritura silenciosa;
2. vincular una aprobación PO al commit exacto publicado;
3. impedir APPROVED_FOR_MERGE si el commit no coincide;
4. impedir APPROVED_FOR_MERGE si mergeability != clean;
5. mantener approved_commit=null para CHANGES_REQUESTED y REJECTED;
6. mantener la decisión PO separada del acto real de merge;
7. no alterar estados de otras fases;
8. preservar evidencia suficiente para auditoría posterior.

## Archivos que vas a recibir

- RoundManagerCore.psm1
- R0002/round.yaml
- R0002/po-decision.md
- R0003/round.yaml
- R0003/po-decision.md

## Formato obligatorio de respuesta

Para cada hallazgo:

FINDING <ID>
Severity: BLOCKER | HIGH | MEDIUM | LOW | OPPORTUNITY
Type: bug | security | integrity | architecture | test-gap | usability
Evidence:
<qué parte concreta genera el hallazgo>
Impact:
<qué podría pasar>
Recommendation:
<corrección o test propuesto>

Al final agregá:

CONSULTING

- mejoras adicionales;
- tests que faltan;
- dudas que deberían resolverse antes del merge.

No escribas código completo salvo que sea indispensable para explicar un hallazgo.
