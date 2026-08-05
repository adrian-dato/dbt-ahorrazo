# intermediate/

Capa de reglas de negocio **compartidas por los 3 proyectos**. Nada acá es
específico de canibalización, top 300 o mayoristas — si un modelo termina
siéndolo, no va en esta carpeta.

## Estado

- **`int_clientes_normalizados`**, **`int_clientes_mapeo_limpio`**,
  **`int_clientes_limpio`** — código hecho (Fase 2), incluye correcciones
  encontradas perfilando datos reales (símbolos sueltos en los extremos,
  separadores no estándar, exclusión de clientes no identificables --
  ver comentarios en `int_clientes_mapeo_limpio.sql`). **Validación en
  curso, no confirmada todavía** — ver `../../PENDIENTES.md`. Corren en
  paralelo al proceso legacy, no reemplazan a `stg_clientes_mapeo`/
  `stg_clientes_limpio` como fuente de ningún mart hasta validar.
- **`int_ventas_elegibles`** — hecho (Fase 3). Unifica las 3
  implementaciones antes inconsistentes de las reglas de exclusión.
  Usa `stg_clientes_mapeo` (legacy), no `int_clientes_mapeo_limpio`
  todavía, por la misma razón de arriba. `fct_ventas_36m` (Canibalización)
  todavía no lo consume -- sigue con su copia propia ya testeada; migrarlo
  es limpieza pendiente, no bloqueante.

Ver `../../PENDIENTES.md` para la lista completa y accionable de qué
falta validar en cada fase.
