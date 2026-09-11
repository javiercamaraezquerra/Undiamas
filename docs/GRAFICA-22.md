# Gráfica de Perfil — candidata 1.0.2+22

Parte de la prueba 1.0.2+21 aceptada por Javi, conservada en su carpeta.
Esta revisión implementa la propuesta visual aprobada para la gráfica del
Perfil. El resultado de compilación y pruebas se documenta en [VALIDACION-22.md](VALIDACION-22.md).

## Comportamiento

- Periodos de 7 días, 30 días y todo el historial; se abre con 30 días.
- Cada punto conserva el ánimo y la fecha de una entrada. Los periodos cortos
  incluyen hoy y los 6/29 días naturales anteriores, en la zona del dispositivo.
- Eje horizontal proporcional al calendario y a la hora dentro de cada día.
  Los cambios de horario de verano se tratan como días naturales completos.
- Los tramos se separan al haber días intermedios sin entradas. No hay medias,
  relleno de días ausentes, suavizado ni clasificación del progreso personal.
- Tocar un punto abre la consulta de sus entradas; «Ver entradas» permite
  seleccionar de forma precisa cuando hay muchos puntos o se usa lector de pantalla.
- Las entradas del mismo instante siguen siendo entradas independientes.
- La consulta muestra fecha, hora, ánimo y texto, sin editar ni guardar nada.
- Borrado, restauración o indisponibilidad del Inventario invalidan la ficha
  abierta para evitar que reaparezcan datos que ya no están vigentes.
- Una entrada se representa con un punto. Un periodo vacío muestra un mensaje.
- Fechas futuras guardadas por un reloj mal ajustado permanecen en «Todo»;
  los periodos actuales no las incluyen si corresponden a un día posterior a hoy.

## Conservación e integración

No cambia el formato Hive ni sus adaptadores, las claves de cifrado, las copias
de Drive, los textos del Inventario, las reflexiones, los anuncios o el bloqueo.
El detalle utiliza el Navigator ya protegido por AppLockGate. La consulta de
datos escucha tanto la caja como el estado de las operaciones de restauración.
No se cambia la instalación de producción ni se publica esta candidata.

La separación entre fechas usa días de calendario, no bloques de 24 horas:
[DateTime.difference explica la diferencia durante cambios de horario](https://api.dart.dev/dart-core/DateTime/difference.html).
Controles y panel de lectura deben admitir tamaños grandes de texto y acceso
sin depender de tocar un punto pequeño, siguiendo las
[recomendaciones de accesibilidad de Flutter](https://docs.flutter.dev/ui/accessibility).

## Revisión en el móvil

Instalar el APK 22 sobre «Un día más · Privacidad» sin desinstalar la prueba 21.
Usar entradas ficticias para comprobar filtros, puntos próximos, lectura larga,
borrado individual y regreso al Perfil. Revisar también claro/oscuro y el tamaño
de texto aumentado desde los ajustes del móvil.
Salir con una ficha abierta y volver con el bloqueo activo debe exigir
autenticación. La versión de Google Play conserva sus datos por separado.
