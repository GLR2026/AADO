# R0001 — Proposal

## Objetivo

Implementar AADO-COMM-001 como circuito determinístico de revisión,
auditoría y consultoría reutilizable posteriormente por AADO.

## Arquitectura aprobada para esta ronda

El flujo objetivo es:

1. IMPLEMENTADOR
   - genera una propuesta versionada.

2. BLIND REVIEW
   - Claude y Gemini reciben la misma propuesta.
   - trabajan de forma independiente.
   - ninguno ve inicialmente la respuesta del otro.
   - las respuestas originales quedan preservadas e inmutables.

3. CROSS REVIEW
   - Claude recibe la auditoría original de Gemini.
   - Gemini recibe la auditoría original de Claude.
   - no se busca consenso por votación.
   - cada auditor puede responder:
     AGREE
     DISAGREE
     PARTIAL
     NEW_FINDING
     CHANGED_POSITION
   - un cambio de posición debe identificar la evidencia que lo motivó.

4. IMPLEMENTER RESPONSE
   - el implementador responde a cada finding.
   - cada finding debe recibir una disposición:
     ACCEPTED
     REJECTED
     DEFERRED
     NEEDS_PO
     NEEDS_TEST

5. OBJECTIVE CHECK
   - cuando un desacuerdo pueda resolverse objetivamente,
     se usa test, verifier, experimento o evidencia externa.

6. PO DIGEST
   - se genera una vista resumida para el PO.
   - debe destacar siempre:
     BLOCKER
     HIGH
     cambios de arquitectura
     cambios de seguridad
     gastos
     credenciales
     producción
     desacuerdos no resueltos
     cambios de reglas previamente aprobadas.

7. PO / MERGE
   - el PO decide sobre los puntos que requieren su intervención.
   - main representa únicamente estado aprobado.
   - las rondas viven en branches separadas.

## Principios de control

- No existe votación "dos contra uno".
- Coincidencia entre auditores no equivale a verdad.
- La convergencia independiente se registra como señal, no como sentencia.
- El implementador tampoco puede descartar silenciosamente un finding.
- Los desacuerdos deben resolverse mediante evidencia, test o decisión PO.
- El Round Manager administra el protocolo; no decide qué opinión es correcta.
- El transporte de información puede automatizarse.
- Las decisiones relevantes no deben quedar ocultas al PO.

## Arquitectura técnica inicial

El sistema se divide en:

- Core determinístico reutilizable.
- Interfaz humana separada.
- Persistencia estructurada en Markdown + YAML.
- Git como historial y trazabilidad.
- Branch por ronda.
- Sin acceso automático a APIs comerciales.
- Sin merge automático a main.

## Seguridad inicial

- Nunca usar git add .
- Sólo versionar archivos explícitamente permitidos.
- No incluir AADO_PRIVATE.
- No guardar tokens, cookies o credenciales.
- La detección por patrones de secretos es sólo auxiliar.
- La allowlist de archivos es el control principal.
- No hay acciones destructivas ni publicación a producción.

## Estado de implementación

Primera etapa:
- crear el Core;
- crear rondas;
- guardar propuesta;
- implementar blind review;
- implementar cierre de fase ciega;
- implementar cross-review;
- implementar disposiciones del implementador;
- generar PO Digest;
- validar estado;
- recién después agregar publicación Git/GitHub.

La GUI se desarrollará después de validar el Core.
