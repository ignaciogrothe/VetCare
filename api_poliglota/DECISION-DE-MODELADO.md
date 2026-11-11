# Decisión de modelado — API Veterinaria

**Grupo:** Grothe, González · **Caso:** clínica veterinaria (usuarios, mascotas, citas, atenciones)

## 1. Qué dato queda en cada motor

| Dato o entidad | Motor | Razón |
|---|---|---|
| `usuarios` (dueños, veterinarios, recepción, admin) | MySQL | Estructura idéntica para todos; `email` único; el rol es un conjunto cerrado (`ENUM`). |
| `mascotas` | MySQL | Pertenecen a un dueño (`dueno_id` FK); se listan y filtran por dueño y especie. |
| `citas` | MySQL | Regla que no puede romperse: un veterinario no tiene dos citas agendadas a la misma hora. Cambian de estado (agendada → atendida/cancelada) con transiciones que deben ser atómicas. |
| `atenciones` con su receta (`medicamentos[]`) | MongoDB | Documento anidado que se lee siempre completo (diagnóstico, tratamiento y receta juntos) y cuya forma puede crecer. |

## 2. Por qué

1. **La regla de no doble agenda la hace cumplir el motor, no el código.** `citas` tiene una
   columna generada `bloque_agendado` (vale `fecha_hora` solo mientras la cita está agendada) y un
   índice único `(veterinario_id, bloque_agendado)`. Dos recepcionistas agendando el mismo bloque a
   la vez: una recibe 409 aunque ambas pasaran la verificación previa. Las citas canceladas no
   bloquean el horario. Esto no se puede expresar en un documento sin código adicional.
2. **Las atenciones son un objeto anidado que se consume como unidad.** Una atención contiene una
   lista de medicamentos de largo variable (`{medicamento, dosis, duracion_dias}`). En el modelo
   relacional eran dos tablas (`atenciones` y `recetas`) con un `DELETE` + `INSERT` en cada
   corrección. Ningún endpoint pide un medicamento suelto: E14, E15 y E16 leen y escriben la
   atención completa, así que el documento lo resuelve en una sola operación.
3. **Las atenciones son datos que se escriben y se leen casi siempre por una clave (`cita_id`).**
   Nunca se agregan ni se cruzan entre sí para informes; no necesitan `JOIN`. En cambio, `usuarios`,
   `mascotas` y `citas` sí se cruzan constantemente (la cita muestra nombre de mascota y de
   veterinario; el dueño ve solo sus citas).
4. **La estructura clínica es la que más probablemente cambie** (signos vitales, exámenes, vacunas por
   especie). En MongoDB se pueden agregar campos a nuevos documentos sin migrar el esquema; en MySQL
   cada dato nuevo pide `ALTER TABLE` o columnas casi siempre nulas.

## 3. Cómo se conectan los dos lados

* El documento de la colección `atenciones` guarda **`cita_id`**, que es el `citas.id` de MySQL.
  Un índice único sobre `cita_id` asegura una atención por cita.
* No hay datos duplicados entre motores: MySQL no guarda diagnóstico y Mongo no guarda nombres,
  fechas ni estado de la cita. Cada dato vive en un solo lugar.
* **Endpoint combinado:** `GET /api/mascotas/{id}/historial`.
  1. Consulta primero **MySQL** (mascota, dueño y citas), porque es quien dice si la mascota existe y
     si el usuario puede verla: si no, responde 404/403 sin tocar Mongo.
  2. Con los ids de las citas, hace **una** consulta a Mongo: `find({cita_id: {$in: ids}}, {_id: 0})`
     (filtro y proyección en el servidor, no se trae la colección para filtrar en Python).
  3. Une ambos resultados en una respuesta. Una cita sin documento devuelve `"atencion": null`, y
     un documento cuya cita no existe simplemente no aparece: la referencia rota no rompe la respuesta.

**¿Qué pasa si se borra la entidad referenciada?** La API no permite borrar citas, y `DELETE` de una
mascota responde 409 si tiene citas (además de la FK `ON DELETE RESTRICT`). Por eso no se pueden
dejar documentos huérfanos por la API; el historial igualmente tolera uno si apareciera por otra vía.

**Consistencia entre motores.** No existe una transacción que abarque MySQL y MongoDB. E14 se
ordena así: (1) `UPDATE citas SET estado='atendida' WHERE id=? AND estado='agendada'` en MySQL, que
actúa de guarda (solo una petición la gana; la otra recibe 409); (2) se inserta el documento en
Mongo; (3) si ese insert falla, se compensa devolviendo la cita a `agendada` y se responde 503. La
ventana de inconsistencia (caída del proceso entre el paso 1 y el 3) existe y es la limitación
conocida de repartir datos entre dos motores.

## 4. Qué se descartó

**Todo en MySQL** (el diseño original en Dart: tablas `atenciones` y `recetas`). Funcionaba, y
tenía la ventaja de una transacción única para la atención. Se descartó porque la receta es un
arreglo de largo variable que se lee y reemplaza como unidad (dos tablas y reescritura completa en
cada corrección) y porque el contenido clínico es la parte que más cambia; el costo es la
transacción entre motores descrita arriba, que aceptamos con compensación.

**Todo en MongoDB** (como una API de catálogo hecha antes en el curso). Se descartó porque perdería
la garantía de no doble agenda y las claves foráneas: la integridad referencial pasaría a depender
del código.

## 5. Lo que queda en cada lado, en una línea

* **MySQL:** lo que debe cumplir reglas siempre y se cruza con otros datos.
* **MongoDB:** lo que se escribe y se lee como un documento completo y puede cambiar de forma.
