# Candidata 1.0.9+30 — calendario del Inventario

Petición del 01/10/2026: añadir un calendario a la izquierda de la lupa para
seleccionar un día. Corrección explícita posterior: buscar **por día o por
palabras**, nunca ambos filtros a la vez.

## Uso y alcance

- Calendario junto a la lupa. Abre el selector estándar de Android/Flutter,
  localizado en español según la configuración existente de la app.
- Aceptar un día limpia y cierra la búsqueda por palabras. Abrir la lupa quita
  la fecha. Cancelar el calendario conserva el modo y la búsqueda previos.
- Se muestra el día elegido, incluido el año, con un botón para quitarlo y
  volver a todas las entradas. Un día vacío tiene una explicación breve.
- El calendario abarca desde la primera entrada hasta hoy; incluye fechas
  futuras ya guardadas y la selección activa si sus entradas se han borrado.
- Se compara el día, mes y año que aparecen en las tarjetas, sin cambiar
  fechas guardadas ni desplazar entradas UTC a un día distinto del visible.
- Solo se filtra la vista. Borradores, fotos, claves de las entradas, copias,
  restauraciones, cifrado, reflexiones y anuncios conservan el contrato de v29.
- En pantallas estrechas con letra grande se abre la entrada escrita respetando
  el tamaño solicitado. Se puede alternar al calendario: solo su cuadrícula se
  limita al 140 % para separar los siete días; al escribir vuelve el tamaño
  elegido. Se conserva la fecha al alternar. El Inventario mantiene su escala.

La base es el commit local `891cb32ef09a0511100c9abb466dc70e4968342e`.
Se conserva el APK de prueba v29. La nueva revisión usa versionCode 30.
Javi ha autorizado expresamente aplicar **todas las mejoras de v29 más este
calendario a la aplicación oficial y subirla a producción**, en este mismo
turno del 01/10/2026. El destino es `com.celsoriaapps.undiamas`, con la firma
de subida existente y `UDM_PREVIEW=false` mediante GitHub Actions. El envío
a revisión y la aprobación de Google se documentarán por separado.

## Validación

Comprobaciones locales terminadas el 01/10/2026:

- Suite completa: 532 pruebas correctas, 2 omitidas por la limitación de enlaces
  simbólicos de Windows, 0 fallos (`build/validation/tests-final-v30.txt`).
- Tras el ajuste visual final: 9 pruebas específicas del calendario correctas
  (`calendar-final-v30.txt`), incluida alternancia con conservación de fecha,
  modo escrito a 320×640 y teclado de 260 px, y resultado del Inventario al 200 %.
- Analizador: 0 errores; mismas 3 advertencias y 31 recomendaciones heredadas.
- 20 pruebas Python correctas de los verificadores independientes de artefactos
  y contenido (en `build/validation/verifier-tests-v30.txt`).
- Capturas reales de widgets con datos sintéticos inspeccionadas en claro,
  oscuro y letra grande. Se detectó y corrigió la recreación del estado del
  selector al alternar el modo accesible, sin relajar las pruebas.
- Código Android, permisos, modelos Hive, cifrado, restauración, dependencias,
  workflow y recursos originales idénticos a la base v28. El JSON de las 365
  reflexiones conserva SHA-256 `450f6b756d2d80a6375f06f5477bf00104e00642eb892d98aaae2905703bdd2b`.

Pendientes la compilación oficial, verificación de APK/AAB y envío a Play.
No se ha realizado una prueba nueva con teléfono o cuenta real de Drive;
las comprobaciones locales no equivalen a una validación en dispositivo.

## Archivos y comandos

- Interfaz y filtro: `lib/screens/journal_screen.dart`.
- Versión: `pubspec.yaml`.
- Pruebas de calendario: `test/journal_date_filter_test.dart`.
- `tool/local-v30.ps1 -Mode Test` ejecuta la suite.
- `tool/local-v30.ps1 -Mode Analyze` analiza el código.
- El workflow existente `.github/workflows/build-apk.yml` genera APK y AAB
  oficiales firmados y verificados desde el commit final de `main`.
- El modo `Build` de los scripts locales sigue siendo únicamente de pruebas;
  no se usa para publicar la aplicación oficial.

Se reutilizan carpeta y cachés de v29 para esta revisión incremental; el APK
anterior y sus comprobaciones permanecen disponibles en `dist`.
