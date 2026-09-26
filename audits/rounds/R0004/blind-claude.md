# R0004 — Blind Review — claude

Captured at: 2026-09-24T22:00:39-03:00
Phase: blind_review
Auditor: claude

---

LeÃ­ todo: el prompt.md, el RoundManagerCore.psm1 completo y los cuatro archivos de evidencia. Esta es mi auditorÃ­a independiente segÃºn las instrucciones del prompt, mÃ¡s el doble check de mis roles habituales.

AUDITORÃA TÃ‰CNICA â€” RoundManagerCore.psm1 / AADO-COMM-002

FINDING C-001
Severity: BLOCKER
Type: integrity
Evidence:
Set-AadoPODecision â€” el regex que detecta si ya existe una decisiÃ³n es:
'(?m)^\s{2}status:\s+pending\s*$'
Este patron matchea el campo status dentro de po_decision:, pero tambiÃ©n matchearÃ­a un campo status: en cualquier otra secciÃ³n del yaml que tenga la misma indentaciÃ³n de 2 espacios. Si en el futuro el schema agrega un campo status: pending a nivel de ronda o publicaciÃ³n, el guard deja de funcionar y permite sobrescritura silenciosa de una decisiÃ³n ya tomada.
Impact:
Una decisiÃ³n PO existente (APPROVED_FOR_MERGE) podrÃ­a ser sobrescrita si el yaml evoluciona y aparece otro campo status con igual indentaciÃ³n.
Recommendation:
El parser debe leer el yaml dentro del bloque po_decision: especÃ­ficamente, no buscar el patrÃ³n en todo el documento. Mismo problema existe en Save-AadoProposal con proposal: pending â€” aunque en ese caso el campo es mÃ¡s Ãºnico, el patrÃ³n es igualmente frÃ¡gil para un parser basado en regex sobre texto plano.

FINDING C-002
Severity: BLOCKER
Type: integrity
Evidence:
Set-AadoPublicationMetadata â€” el guard contra sobrescritura es:
if ($Yaml -match '(?m)^\s{2}branch:\s+(?!null\s*$).+$') {
    throw "Publication metadata already exists. Refusing silent overwrite."
}
Este guard verifica solo que branch no sea null. Pero los campos commit, pr_url, pr_number, mergeability y checked_at no tienen guards propios. Si branch ya fue escrito pero el proceso se interrumpiÃ³ antes de escribir commit, una segunda llamada a Set-AadoPublicationMetadata va a pasar el guard (porque branch no es null) y lanzar el throw, haciendo que sea imposible completar la operaciÃ³n parcialmente iniciada sin editar el yaml manualmente.
Impact:
Una interrupciÃ³n del proceso a mitad de Set-AadoPublicationMetadata (corte de red, reinicio del VPS) deja el round en estado parcialmente escrito sin forma de recuperaciÃ³n automÃ¡tica.
Recommendation:
El guard deberÃ­a verificar si commit es null ademÃ¡s de branch. Si branch existe pero commit es null, la funciÃ³n deberÃ­a poder continuar desde donde quedÃ³ en lugar de abortar.

FINDING C-003
Severity: HIGH
Type: bug
Evidence:
Get-AadoPhaseMemberStatus â€” la regex para detectar el inicio de secciÃ³n es:
"^\s{2}$Section`:\s*$"
Y la regex de salida de secciÃ³n es:
'^\s{2}[A-Za-z_]+:'
El problema: blind_review_closed: false tiene indentaciÃ³n de 2 espacios y matchea el patrÃ³n de salida de secciÃ³n. Si blind_review_closed aparece en el yaml antes de que se encuentre el miembro buscado dentro de blind_review:, la funciÃ³n terminarÃ­a antes de encontrarlo.
En el yaml generado por New-AadoRound, el orden es:
  blind_review:
    claude: pending
    gemini: pending
  blind_review_closed: false
Con este orden blind_review_closed aparece despuÃ©s de los miembros, entonces no rompe. Pero si alguien reorganiza el yaml o agrega campos, el parser falla silenciosamente devolviendo un throw "No se encontrÃ³".
Impact:
Fragil ante cualquier reordenamiento del yaml. El parser depende del orden fÃ­sico de las lÃ­neas, no de la estructura lÃ³gica.
Recommendation:
Usar un parser de yaml real (hay mÃ³dulos de PowerShell) o al menos documentar explÃ­citamente que el orden del yaml generado por New-AadoRound es un contrato y no puede modificarse manualmente.

FINDING C-004
Severity: HIGH
Type: integrity
Evidence:
Build-AadoPODigest â€” el parser de findings es:
if ($Line -match '^FINDING\s+(.+?)\s*$') {
    $CurrentFinding = $Matches[1].Trim()
}
if ($Line -match '^Disposition:\s*([A-Z_]+)\s*$') {
    ...
}
El parser no valida que entre un FINDING y su Disposition no aparezca otro FINDING. Si el implementador escribe:
FINDING H-001
FINDING H-002
Disposition: ACCEPTED
El resultado es que H-001 desaparece silenciosamente y H-002 queda con la disposiciÃ³n. No hay error, no hay alerta.
Impact:
Un finding puede perderse sin que el sistema lo detecte, produciendo un PO Digest que no refleja todos los hallazgos registrados.
Recommendation:
Si se detecta un nuevo FINDING mientras $CurrentFinding todavÃ­a no tiene disposiciÃ³n, lanzar un error: "FINDING H-001 has no Disposition before next FINDING".

FINDING C-005
Severity: HIGH
Type: security
Evidence:
Set-AadoPODecision â€” el guard de mergeability solo aplica para APPROVED_FOR_MERGE:
if ($Decision -eq "APPROVED_FOR_MERGE") {
    if ($MergeMatch.Groups[1].Value -ne "clean") {
        throw "Mergeability is not clean. Approval blocked."
    }
}
CHANGES_REQUESTED y REJECTED no verifican mergeability. Esto estÃ¡ bien para esos estados. Pero el campo mergeability puede ser "unknown" y aÃºn asÃ­ producir una decisiÃ³n vÃ¡lida de cualquier tipo. Si despuÃ©s alguien agrega un estado de decisiÃ³n futuro que sÃ­ deberÃ­a verificar mergeability, no hay ningÃºn mecanismo que lo recuerde.
Impact:
Bajo ahora, pero es un gap de diseÃ±o: la lÃ³gica de quÃ© estados requieren mergeability clean estÃ¡ hardcoded solo para APPROVED_FOR_MERGE sin documentaciÃ³n de que esa es una decisiÃ³n de diseÃ±o explÃ­cita.
Recommendation:
Agregar un comentario en el cÃ³digo que diga explÃ­citamente: "solo APPROVED_FOR_MERGE requiere mergeability clean; los demÃ¡s estados no tienen restricciÃ³n de mergeability por diseÃ±o". Eso convierte un gap implÃ­cito en una decisiÃ³n documentada.

FINDING C-006
Severity: MEDIUM
Type: integrity
Evidence:
Set-AadoPODecision â€” cuando la decisiÃ³n es CHANGES_REQUESTED o REJECTED, approved_commit permanece null en el yaml. Eso estÃ¡ correcto. Pero el po-decision.md generado contiene:
Published commit: <commit>
Ese campo existe en el archivo aunque no haya aprobaciÃ³n. Esto es correcto para trazabilidad. Sin embargo, el campo se llama "Published commit" en el md pero "approved_commit" en el yaml, y en el caso de no-aprobaciÃ³n el lector del md podrÃ­a interpretar "Published commit" como el commit aprobado, cuando en realidad es solo el commit que estaba publicado al momento de la decisiÃ³n.
Impact:
AmbigÃ¼edad en el registro de auditorÃ­a posterior. Un lector del po-decision.md de R0003 ve "Published commit: 1111..." y puede confundirlo con aprobaciÃ³n.
Recommendation:
Renombrar el campo en el md a "Commit at decision time:" para los casos de CHANGES_REQUESTED y REJECTED, diferenciÃ¡ndolo de "Approved commit:" que solo aparecerÃ­a en APPROVED_FOR_MERGE.

FINDING C-007
Severity: MEDIUM
Type: test-gap
Evidence:
R0003 usa como commit de prueba 1111111111111111111111111111111111111111. Ese commit no existe en ningÃºn repositorio real. La prueba valida que la funciÃ³n acepta 40 caracteres hexadecimales, pero no valida que el commit exista en el branch declarado en publication.branch.
Impact:
Es posible aprobar un commit fantasma. La funciÃ³n no hace ningÃºn git cat-file ni verificaciÃ³n de existencia del commit contra el repo local o remoto.
Recommendation:
Agregar como test-gap conocido: "Set-AadoPODecision no verifica que el commit exista en el repositorio". Si la intenciÃ³n es que esa verificaciÃ³n sea responsabilidad del caller (la GUI o el script de publicaciÃ³n), documentarlo explÃ­citamente en el mÃ³dulo.

FINDING C-008
Severity: MEDIUM
Type: architecture
Evidence:
Set-AadoPODecision recibe $ExpectedCommit como parÃ¡metro y lo compara contra el commit almacenado en el yaml. La funciÃ³n asume que el llamador sabe cuÃ¡l es el commit publicado y lo pasa explÃ­citamente. Pero si el llamador simplemente lee el commit del yaml y lo pasa como parÃ¡metro, la verificaciÃ³n es circular: siempre va a coincidir porque viene del mismo archivo.
Impact:
La verificaciÃ³n de commit solo tiene valor real si el PO ingresa el commit desde una fuente externa (lo que vio en GitHub, lo que recibiÃ³ por otro canal). Si la GUI pre-rellena el campo con el commit del yaml, la protecciÃ³n se convierte en burocracia sin valor.
Recommendation:
Documentar explÃ­citamente que $ExpectedCommit debe ser ingresado por el PO desde una fuente externa al yaml, nunca pre-rellenado automÃ¡ticamente por el sistema. Si la GUI lo pre-rellena, anular la verificaciÃ³n.

FINDING C-009
Severity: LOW
Type: usability
Evidence:
New-AadoRound â€” el campo status: draft se escribe en el yaml pero ninguna funciÃ³n lo actualiza nunca. Todas las transiciones de estado se manejan por los campos individuales de cada fase (proposal: completed, blind_review_closed: true, etc.). El campo status de nivel raÃ­z queda siempre en draft incluso cuando la ronda estÃ¡ completamente cerrada y aprobada. R0002 y R0003 tienen status: draft aunque ambas tengan po_decision completada.
Impact:
El campo status en raÃ­z no es un tracker confiable del estado real de la ronda. Puede confundir a un lector o a AADO si en el futuro intenta filtrar rondas por estado.
Recommendation:
O bien actualizar status en cada transiciÃ³n relevante (draft â†’ in_progress â†’ approved/rejected), o documentar que status en raÃ­z es un campo reservado para uso futuro y que el estado real se deriva de los campos de fase.

CONSULTING
Mejoras adicionales:
A. El modelo de parser de yaml basado en regex es el mayor riesgo tÃ©cnico del mÃ³dulo
Todos los guards y lectores de estado usan regex sobre texto plano. Esto funciona mientras el yaml sea generado Ãºnicamente por New-AadoRound y nunca editado manualmente. Un mÃ³dulo de yaml real para PowerShell (powershell-yaml en PSGallery) eliminarÃ­a esta fragilidad de raÃ­z y harÃ­a el cÃ³digo mÃ¡s corto y mÃ¡s robusto. Vale la inversiÃ³n antes de que el sistema empiece a usarse en producciÃ³n.
B. No existe funciÃ³n Get-AadoRoundSummary
No hay forma de preguntar "Â¿en quÃ© estado estÃ¡ la ronda R0004?" sin leer el yaml manualmente. Una funciÃ³n que devuelva un objeto con el estado de cada fase serÃ­a inmediatamente Ãºtil para la GUI y para AADO como caller.
C. El mÃ³dulo no exporta Get-AadoRoundDirectory
La funciÃ³n existe y es Ãºtil externamente, pero no estÃ¡ en Export-ModuleMember. Si la GUI o un script externo necesita la ruta de una ronda, tiene que reconstruirla manualmente.
D. Tests que faltan:
Interrumpir Set-AadoPublicationMetadata despuÃ©s de escribir branch pero antes de escribir commit: verificar que el estado queda recuperable.
Pasar $ExpectedCommit distinto al commit del yaml: verificar que Set-AadoPODecision falla correctamente.
Build-AadoPODigest con un finding sin disposiciÃ³n: verificar que falla con error claro.
Build-AadoPODigest con dos findings consecutivos sin disposiciÃ³n entre ellos: verificar que detecta el gap.
Set-AadoPODecision con mergeability: unknown y APPROVED_FOR_MERGE: verificar que bloquea.
E. Duda que deberÃ­a resolverse antes del merge:
Â¿La funciÃ³n Set-AadoPublicationMetadata es llamada por la GUI despuÃ©s de que el push a GitHub fue exitoso, o antes? Si se llama antes del push y el push falla, el yaml queda con metadatos de publicaciÃ³n que apuntan a un commit/PR que no existe en GitHub todavÃ­a. El orden correcto es: push exitoso â†’ crear PR â†’ obtener PR number y URL â†’ llamar a Set-AadoPublicationMetadata. Si ese orden no estÃ¡ documentado y garantizado por el caller, hay un riesgo de inconsistencia.

DOBLE CHECK â€” Roles habituales auditor/consejero
Sobre el proceso de esta ronda:
Es la primera vez que recibo un paquete estructurado en lugar de un Word. La diferencia es inmediatamente visible: puedo leer el cÃ³digo exacto, los yamls reales y las decisiones del PO sin ambigÃ¼edad. El sistema ya funciona mejor que el circuito de Words anterior. Eso es evidencia de que AADO-COMM-001 tiene valor real.
ObservaciÃ³n de auditorÃ­a sobre los yamls de evidencia:
R0002 y R0003 tienen status: draft a pesar de tener po_decision completada (Finding C-009 arriba). Pero mÃ¡s importante: R0002 tiene updated_at: 2026-09-24T19:54:29-03:00 que coincide exactamente con decided_at. R0003 tiene updated_at: 2026-09-24T19:49:58-03:00 que coincide con created_at, lo cual sugiere que despuÃ©s de crear la ronda no se actualizÃ³ el timestamp en ninguna operaciÃ³n posterior. Eso indica que alguna funciÃ³n no estÃ¡ actualizando updated_at correctamente, o que R0003 fue creada y completada en el mismo segundo (improbable). Vale verificarlo.
Consejo sobre el siguiente paso:
Antes de usar este mÃ³dulo para rondas reales de auditorÃ­a, los findings C-001 y C-002 (BLOCKER) deberÃ­an estar resueltos. C-003 y C-004 (HIGH) son importantes pero no bloquean la operaciÃ³n bÃ¡sica si el yaml no se edita manualmente. El resto puede ir al backlog como deuda tÃ©cnica conocida.

------------

