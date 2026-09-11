# Un día más — candidata de producción 1.0.3+23

Esta actualización parte de la copia local 1.0.2+22 aprobada en el teléfono.
Conserva sus mejoras de bloqueo opcional, restauración, borrado del Inventario,
notificaciones y gráfica del Perfil, junto con el diseño original.

La distribución production utiliza com.celsoriaapps.undiamas y los nombres
originales Un Día Más / One More Day. Preview es una instalación independiente
para pruebas; no debe subirse a Google Play.

## Comprobaciones

Con Flutter 3.32.8 y el archivo pubspec.lock incluido:

```sh
flutter pub get --enforce-lockfile
flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings
flutter test --no-pub --reporter expanded
python3 -m unittest discover -s tool -p '*_test.py' -v
```

La suite Flutter contiene 265 pruebas aprobadas. El análisis no detecta errores;
mantiene 3 advertencias y 36 observaciones anteriores. También se han comprobado
4 escenarios visuales en claro/oscuro y con texto ampliado.
El verificador de artefactos supera sus 14 pruebas Python; la sintaxis del
workflow también está comprobada. Su ejecución en GitHub sigue pendiente.
La variante aislada de comprobación compila en release y pasa firma de pruebas,
API 36, tres arquitecturas y alineación de 16 KiB. Esto no acredita la firma
de producción ni una ejecución real en un teléfono.

## APK y AAB firmados

El workflow .github/workflows/build-apk.yml compila esta fuente y usa los cuatro
secretos de firma originales del repositorio. Exige el certificado de subida
verificado en Play y comprueba identidad, recursos y firmas de los artefactos.
No publica automáticamente en Google Play.

```sh
flutter build appbundle --release --flavor production --no-pub --dart-define=UDM_PREVIEW=false
flutter build apk --release --flavor production --no-pub --dart-define=UDM_PREVIEW=false
```

Esos comandos requieren la clave de subida original mediante android/key.properties.
Nunca debe usarse una clave de pruebas con el identificador de producción.

El [estado de preparación](docs/PRODUCCION-23.md) distingue las comprobaciones
realizadas de la firma, pruebas reales y publicación todavía pendientes.
La [política de privacidad](docs/privacy-policy.html) corresponde a la URL habitual
publicada en Google Sites.
