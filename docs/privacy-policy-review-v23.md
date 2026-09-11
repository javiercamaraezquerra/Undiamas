# Revisión de política de privacidad — 11 de septiembre de 2026

Política preparada para **Un día más / CelsoriaApps**, contacto **undiamasapp@gmail.com**, URL existente **https://sites.google.com/view/undiamas-privacy**. `docs/privacy-policy.html` y `privacy‑policy.html` contienen el mismo texto. No se ha publicado desde esta subtarea.

## Correspondencia con la candidata

- `lib/services/inventory_storage.dart:14` abre las cajas cifradas de inicio e Inventario; `lib/services/encryption_service.dart` guarda la clave mediante almacenamiento seguro. Las preferencias de `SharedPreferences` no tienen ese cifrado adicional. El modelo Post está registrado, pero no hay flujo de publicaciones activo que justifique describir una comunidad.
- `lib/services/drive_backup_service.dart:230` exporta `udm` y las entradas con texto, ánimo y fecha; no exporta favoritos, preferencias de notificaciones ni bloqueo. `uploadBackup` transmite JSON en memoria sin cifrado propio de extremo a extremo. La copia se guarda en `appDataFolder`.
- `lib/screens/profile_screen.dart:552` intenta borrar Drive sólo si reconoce sesión conectada. En 1.0.3 el fallo remoto interrumpe antes del borrado local. Sin sesión, puede quedar una copia remota. Reiniciar el contador conserva el Inventario. La política diferencia estas acciones y no promete eliminación remota por desinstalar.
- `lib/services/app_lock_controller.dart:291` permite credencial del dispositivo y recibe el resultado, no huella/PIN. No hay `FLAG_SECURE`; la política no promete ocultar Recientes ni evitar capturas.
- `lib/widgets/ad_banner.dart:78` utiliza `AdRequest()` sin texto, ánimo ni sustancia como segmentación. El acceso a opciones UMP depende de `privacyOptionsRequired`. No hay mediación configurada según la comprobación de la raíz en AdMob.
- Audiencia de Play confirmada por la raíz: 13–15, 16–17 y 18+. Se conserva 13+ sin inventar ausencia de tratamiento de datos de menores ni un selector de edad.
- El texto advierte que bloqueo, borrado individual, revisión de restauración y opciones publicitarias se incorporan en **1.0.3**; conserva el aviso de apoyo personal que no sustituye tratamiento/asesoramiento médico o psicológico.

## Declaraciones de Play que deben revisarse

**AdMob:** la guía Android respalda ubicación aproximada por IP, interacciones, diagnóstico/rendimiento e identificadores para publicidad, medición y prevención de fraude. Recomiendo añadir ubicación aproximada a la selección actual aunque no exista permiso GPS. Esa guía no identifica expresamente la subcategoría «registros de fallos»; no la añadiría sólo extrapolando iOS. El plugin instalado es `google_mobile_ads 5.3.1`, con SDK Android **23.6.0** y UMP **3.1.0**; la guía pública describe la versión más reciente, por lo que no constituye una auditoría completa de esa versión antigua. [Guía oficial del SDK Android](https://developers.google.com/admob/android/privacy/play-data-disclosure).

**Drive:** el contenido sanitario sale del dispositivo al activar la copia; sigue siendo recogida opcional y no aplica la excepción de cifrado de extremo a extremo. Google exceptúa de «compartido» ciertas transferencias iniciadas por el usuario o consentidas mediante aviso destacado. El switch y el diálogo de autorización dan fundamento para evaluar esa excepción, pero antes de cambiar la declaración hay que revisar también las versiones aún distribuidas. El aviso debería dejar claro qué contenido se copia. La política debe describir Drive incluso si corresponde la excepción del formulario. [Definiciones oficiales de Seguridad de los datos](https://support.google.com/googleplay/android-developer/answer/10787469).

Además de información sanitaria, revisar si el texto libre del Inventario debe figurar como «otro contenido generado por usuarios», y los datos realmente transmitidos por Google Sign-In como identidad/correo; no declarar cada campo de un objeto sólo porque el SDK lo exponga localmente. Confirmar la declaración de anuncios, el mecanismo de solicitud de borrado y que la respuesta de cifrado en tránsito cubra todos los flujos activos. No se han modificado declaraciones de Play desde esta subtarea.

## Límites de publicación y verificación

Las fuentes oficiales enlazadas en el HTML son la [carpeta de datos de Drive](https://developers.google.com/workspace/drive/api/guides/appdata), la [política de Google](https://policies.google.com/privacy), la guía del SDK Android y la [integración UMP](https://developers.google.com/admob/flutter/privacy). No se ha inventado un plazo de retención, un alojamiento geográfico ni una garantía de no compartir con proveedores.

El HTML no tiene scripts, fuentes remotas ni imágenes; usa una columna adaptable y enlaces legibles. Verificación local con Chrome aislado y datos públicos del documento, sin sesión del usuario: anchos 390, 320 con fuente raíz al 200%, y 900 píxeles. Informe y capturas en `build/validation/privacy-policy/`; estos renders no prueban la altura del iframe final de Google Sites. Tras insertar el HTML, comprobar allí que el apartado de borrado completo resulte visible y navegable.
