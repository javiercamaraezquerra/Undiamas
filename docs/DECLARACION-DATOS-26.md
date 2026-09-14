# Declaración de datos para 1.0.6+26

Revisada el 14 de septiembre de 2026 para la publicación autorizada.

## Política pública

Publicada y comprobada en https://sites.google.com/view/undiamas-privacy:
versión 1.0.6, 14 de septiembre de 2026. Las ocho secciones son accesibles;
la primera y la última se comprobaron visualmente. El texto corresponde a
`docs/privacy-policy.html` y al archivo HTML de la raíz.

Describe fotos optimizadas y cifradas localmente, selección mediante el
sistema, archivos temporales, borradores, copia opcional v2 en Drive,
compatibilidad JSON anterior y eliminación de adjuntos. No declara cifrado
propio de extremo a extremo para Drive. Se conservan audiencia, publicidad,
contacto y URL.

## Cambios guardados en Play Console

La consola confirmó «Cambio guardado»; el envío a revisión se realizará junto
con la nueva versión. Guardar esta declaración no equivale a publicarla.

| Tipo | Recogida | Compartido | Opcional | Temporal | Finalidad |
| --- | --- | --- | --- | --- | --- |
| Fotos, añadido | Sí | No | Sí | No | Funcionalidad |
| Otro contenido generado por el usuario, añadido | Sí | No | Sí | No | Funcionalidad |
| Información sanitaria, unificada con el mismo flujo | Sí | No | Sí | No | Funcionalidad |

La recogida refleja el envío fuera del dispositivo cuando el usuario activa
Drive. «No compartido» aplica la excepción de transferencia autorizada por
el usuario, no significa que el archivo nunca llegue a Google. El contenido
del Inventario no se utiliza para segmentar publicidad.

Las notas libres encajan expresamente en «Otro contenido generado por el
usuario»; Salud se mantiene para el ánimo, la sustancia y la recuperación.
Se comprobó también el código de la versión 1.0.1+15, commit
`40b344efcddc57888cbdc5d48986b208e1ce4d4a`, aún en el canal Alpha: sus salidas
de estos datos son la copia privada en Drive, activada tras «Permitir»;
su `AdRequest()` no incluye datos de salud. Esto permite aplicar la misma
excepción al conjunto de versiones distribuidas.

Se conservan las declaraciones existentes de IDs de usuario, ubicación
aproximada, diagnósticos, interacciones e IDs de dispositivo, incluyendo las
finalidades publicitarias de AdMob. Diagnósticos ya cubre la información de
rendimiento descrita por el SDK; no se añadieron categorías especulativas.
Se mantienen cifrado en tránsito, solicitud de eliminación y acceso mediante
una cuenta Google existente para Drive. No se modificó la audiencia.

## Fuentes

- https://support.google.com/googleplay/android-developer/answer/10787469
- https://developers.google.com/admob/android/privacy/play-data-disclosure

La declaración se basa en los flujos del código y las definiciones de Google;
su aceptación final corresponde a la revisión de Play.
