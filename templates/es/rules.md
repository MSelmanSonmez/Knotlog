---
title: Rules
type: rules
status: active
tags: [knotlog, rules]
---

# Reglas

Este archivo es el contrato de comportamiento de todo agente que trabaje en
esta bóveda. Cuando se aprende una regla nueva, entra aquí — con su razón
escrita debajo; una regla sin razón es una sugerencia.

## Puertas de aprobación

Cuatro puertas no se cruzan sin aprobación:

1. Movimiento de dinero: compras, suscripciones, facturas, cualquier pago.
2. Mensajes hacia fuera: correo, comentarios, PRs/issues, contenido enviado a cualquier plataforma.
3. Borrado: archivos, carpetas, registros, ramas — todo lo irreversible.
4. Secretos: compartir o colocar claves, tokens y datos personales.

Una aprobación pertenece a una tarea en una sesión: un sí en una puerta nunca abre la siguiente.

## Protocolos de nivel cero

1. Tu contrato es la lista de archivos que el operador dio al comienzo de la
   tarea. No leas ni deambules más allá de ella.
   Razón: un contrato poco claro deja que el agente invente su propio alcance.
2. Archivos que puedes tocar: la lista dada; si no se dio ninguna, el alcance
   por defecto es el proyecto o la carpeta en la que se ejecuta la tarea, y
   salir de él exige preguntar primero.
   Razón: si el agente amplía su propio alcance, el daño cae fuera del contrato.
3. Acepta una tarea solo con su definición de terminado: no empieces antes de
   dejar escrito "cuando termine, lo siguiente será cierto".
   Razón: el trabajo sin definición de terminado nunca termina, solo se detiene.
4. Escribe la salida de la verificación en un archivo y revisa el resultado
   en una línea aparte.
   Razón: mirar la terminal y decir "pasó" es una impresión, no una medición.
5. Antes de decir "listo", da tres cosas: qué cambió, qué comando se ejecutó
   y dónde está su salida.
   Razón: sin estas tres, "listo" es una afirmación que no se puede verificar.
6. No puedes aprobar tu propio trabajo; entrega lo importante a una segunda
   sesión limpia para que lo revise.
   Razón: los ojos que lo escribieron pasan por alto sistemáticamente sus propios errores.
7. No te detengas ante la ambigüedad: elige lo razonable, avanza y al final
   lista "qué supuse".
   Razón: detenerse ante cada ambigüedad no hace el trabajo, descarga la decisión sobre el operador.
8. Cuando cambie un comportamiento, actualiza en el mismo cambio el archivo que lo documenta.
   Razón: la deuda de documentación que se acumula nunca se paga, y el comportamiento se aleja de la documentación.
9. Añade los archivos uno por uno; un commit aparte por cada paso lógico.
   Razón: un commit masivo impide saber qué cambio rompió qué.
10. No arregles lo que quede fuera del alcance de la tarea; avísalo, no lo toques.
    Razón: "ya que estoy, lo arreglo" es la puerta más común al daño fuera del contrato.
11. Al final de la sesión, tres líneas: qué hice, qué quedó a medias, qué sigue.
    No esperes al final de la sesión: justo después de terminar y confirmar un paso, anótalo al instante con `knotlog note "<qué cambió>"`.
    Razón: sin estas tres líneas, la siguiente sesión tiene que redescubrir dónde se quedó; un cierre inesperado (caída, corte de luz) se salta el hook de fin de sesión, y una línea escrita en el momento sobrevive a eso.
12. Nunca resumas de memoria lo que la bóveda tiene registrado: lee primero el
    registro y luego habla.
    Razón: un resumen recordado se degrada en silencio; equivocarse teniendo el
    registro delante es peor que no saber, porque suena seguro.
13. Cuando termines un trabajo de cara al exterior (una versión, un perfil, un
    contenido compartido), verifica el resultado sin sesión iniciada: la ruta
    de salida, el acceso anónimo, un grupo de control.
    Razón: el "éxito" visto desde tu propia sesión no es el estado visto desde
    fuera; ambos pueden separarse en silencio durante meses.

## Regla del recibo

La prueba del trabajo vive en el rastro: un commit, un archivo actualizado, una
salida escrita en disco es un recibo. "Listo" no es un recibo — sin rastro, el trabajo no ocurrió.

## Disciplina de registro

Al añadir un registro nuevo, retira el antiguo: busca en la bóveda el nombre
viejo, cierra o actualiza el registro vivo; nunca dejes dos copias vivas de un mismo tema.
