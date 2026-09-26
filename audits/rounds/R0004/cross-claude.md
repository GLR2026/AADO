# R0004 — Cross Review — claude

Captured at: 2026-09-24T22:00:39-03:00
Phase: cross_review
Auditor: claude
Reviewed auditor: gemini

Allowed dispositions:
- AGREE
- DISAGREE
- PARTIAL
- NEW_FINDING
- CHANGED_POSITION

Rule:
Coincidence is not evidence.
A changed position should identify the evidence that caused the change.

---

LeÃ­ la respuesta de Gemini completa. AcÃ¡ van mis dos roles.

AUDITORÃA
1. Gemini no siguiÃ³ el formato obligatorio del prompt.md â€” esto es un BLOCKER de proceso
El prompt.md especifica un formato exacto para cada hallazgo:
FINDING <ID>
Severity: BLOCKER | HIGH | MEDIUM | LOW | OPPORTUNITY
Type: bug | security | integrity | architecture | test-gap | usability
Evidence: ...
Impact: ...
Recommendation: ...
Gemini no usÃ³ ese formato en ningÃºn momento. EntregÃ³ una secciÃ³n narrativa con bullets y cÃ³digo en lugar de findings estructurados. Esto tiene consecuencias concretas: Build-AadoPODigest no podrÃ­a parsear esta respuesta para extraer severidades, porque no hay ningÃºn FINDING <ID> ni Disposition: que el parser pueda detectar. Si el objetivo del paquete de auditorÃ­a es que el sistema procese las respuestas mecÃ¡nicamente, esta respuesta es inÃºtil para ese propÃ³sito.
2. El cÃ³digo PowerShell generado por Gemini tiene bugs que introducen en lugar de corregir
En Save-AADOBlindResponse hay una lÃ­nea rota:
$yaml = Get-Content $yamlPath -Raw$timestamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK'
Esas dos instrucciones estÃ¡n concatenadas en una sola lÃ­nea sin separador. PowerShell va a interpretar $timestamp como parte del argumento de Get-Content, lo que produce un error de sintaxis. Este bug no existÃ­a en el mÃ³dulo original que Gemini estaba auditando â€” fue introducido por Gemini al reescribirlo.
3. Gemini reescribiÃ³ el mÃ³dulo completo sin que nadie lo pidiera â€” viola el scope del prompt
El prompt pedÃ­a auditar RoundManagerCore.psm1 y reportar hallazgos. Gemini entregÃ³ una reescritura parcial del mÃ³dulo con nombres de funciones distintos (New-AADORound vs New-AadoRound), estructura de carpetas diferente (prefijos numÃ©ricos que ya fueron cuestionados en rondas anteriores) y un schema de yaml distinto (schema_version: "1.1" con comillas, campos nuevos como canonical_name, risk_level, etc.). Esta reescritura no fue pedida, no fue aprobada por el PO, y diverge de decisiones ya tomadas.
4. El hallazgo A de Gemini (SHA256 lock) es vÃ¡lido pero estÃ¡ incompleto en su implementaciÃ³n propuesta
La idea de registrar el SHA256 de los archivos de blind review en round.yaml al momento de captura es correcta y yo no la seÃ±alÃ©. Sin embargo, el cÃ³digo de Gemini calcula el hash despuÃ©s de aplicar IsReadOnly, lo cual estÃ¡ bien en orden. Pero la verificaciÃ³n del hash en Build-AadoPODigest no estÃ¡ implementada â€” el cÃ³digo de Build-AADOPODigest no lee los hashes del yaml ni los compara contra los archivos. El hallazgo existe; la soluciÃ³n propuesta no lo resuelve.
5. El hallazgo B (ExecutionPolicy) es un problema de deployment, no de cÃ³digo del mÃ³dulo
-ExecutionPolicy Bypass -Scope Process es correcto como recomendaciÃ³n operativa. Pero no pertenece dentro del mÃ³dulo .psm1 â€” pertenece en el script de arranque o en la documentaciÃ³n de instalaciÃ³n. Gemini lo presenta como algo que "el ejecutable principal debe invocar", lo cual es correcto, pero no seÃ±ala que el mÃ³dulo actual no tiene ningÃºn punto de entrada documentado para ese arranque.
6. El hallazgo C (ramas efÃ­meras) es real pero ya estaba en issues conocidos
La verificaciÃ³n de existencia de rama antes de git checkout -b es un gap real. EstÃ¡ implÃ­citamente cubierto en el Finding C-002 de mi auditorÃ­a anterior (recuperaciÃ³n de estado parcial). Gemini lo identifica de forma independiente, lo que sÃ­ es una convergencia legÃ­tima porque no vio mi respuesta en este caso â€” esto confirma que el hallazgo tiene peso real.
7. El hallazgo D (UTF-8 sin BOM) es correcto y el mÃ³dulo original ya lo implementa
Set-Content -Encoding UTF8 en PowerShell 5.x escribe UTF-8 con BOM. Set-Content -Encoding utf8 en PowerShell 7+ escribe sin BOM. El mÃ³dulo original ya usa -Encoding UTF8 en todas las funciones. Gemini seÃ±ala el problema pero no verifica si ya estÃ¡ resuelto en el cÃ³digo auditado â€” lo cual deberÃ­a ser el primer paso antes de reportar un hallazgo.
8. Build-AADOPODigest en el cÃ³digo de Gemini genera un digest vacÃ­o e inÃºtil
El digest generado por Gemini no parsea ningÃºn finding, no cuenta disposiciones, no extrae severidades. Tiene checkboxes hardcodeados y texto genÃ©rico. Si ese cÃ³digo reemplazara al original, el PO Digest dejarÃ­a de ser determinÃ­stico y mecÃ¡nico para convertirse en un template vacÃ­o. El mÃ³dulo original es significativamente mejor en esta funciÃ³n.

CONSEJERÃA
1. El hallazgo de SHA256 lock de Gemini deberÃ­a incorporarse al mÃ³dulo original
A pesar de todos los problemas de la respuesta, el SHA256 lock es el Ãºnico hallazgo genuinamente nuevo respecto a mi auditorÃ­a. La implementaciÃ³n correcta serÃ­a:
En Save-AadoBlindResponse: calcular SHA256 del archivo guardado y escribirlo en el yaml bajo blind_review.claude.sha256 y blind_review.gemini.sha256.
En Close-AadoBlindPhase o en Save-AadoCrossReview: verificar que el SHA256 actual del archivo coincide con el registrado. Si no coincide, bloquear y reportar "Blind review file integrity check failed".
Eso cubre exactamente el riesgo de alteraciÃ³n post-captura sin depender de IsReadOnly.
2. El fallo de formato de Gemini deberÃ­a usarse para mejorar el prompt.md
Gemini ignorÃ³ el formato obligatorio a pesar de estar en prompt.md. Eso puede pasar por tres razones: el prompt no era suficientemente enfÃ¡tico, el modelo priorizÃ³ "ser Ãºtil" sobre "seguir instrucciones", o recibiÃ³ contexto adicional que sesgÃ³ su respuesta. El prompt.md deberÃ­a tener una secciÃ³n de penalizaciÃ³n explÃ­cita: "Respuestas que no usen el formato FINDING/Severity/Type/Evidence/Impact/Recommendation serÃ¡n rechazadas automÃ¡ticamente y la ronda se marcarÃ¡ como invÃ¡lida para ese auditor." Eso convierte el formato en un requisito con consecuencia, no solo una instrucciÃ³n.
3. La divergencia de nombres de funciones entre versiones es un riesgo real
El mÃ³dulo original usa Save-AadoBlindResponse. Gemini propone Save-AADOBlindResponse. En PowerShell los nombres de funciÃ³n son case-insensitive, asÃ­ que tÃ©cnicamente no rompen. Pero en documentaciÃ³n, en llamadas desde scripts externos, y especialmente cuando AADO sea el caller, la inconsistencia genera confusiÃ³n. El mÃ³dulo deberÃ­a tener un estÃ¡ndar de nomenclatura documentado: Verb-AadoNoun con capitalizaciÃ³n exacta, y cualquier propuesta de cambio deberÃ­a tratarse como cambio de interfaz pÃºblica.
4. Esta ronda es evidencia de que el sistema necesita validaciÃ³n de formato antes de aceptar una respuesta
Save-AadoBlindResponse actualmente acepta cualquier string como $Content. Si el Round Manager tuviera una validaciÃ³n mÃ­nima de formato â€” al menos verificar que el contenido contiene al menos una lÃ­nea que matchee ^FINDING\s+ â€” habrÃ­a rechazado la respuesta de Gemini en el momento de carga en lugar de dejar que el problema llegue hasta el PO Digest. Una validaciÃ³n asÃ­ no garantiza calidad, pero sÃ­ garantiza parseabilidad.

Resumen ejecutivo

