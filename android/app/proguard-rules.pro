# ───────── flutter_local_notifications ─────────
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class com.dexterous.flutterlocalnotifications.serialization.** { *; }

# ───────── Gson (evitar pérdida de genéricos) ─────────
-keep class com.google.gson.stream.** { *; }
-keep class com.google.gson.** { *; }

# Conservar firmas genéricas y anotaciones
-keepattributes Signature, *Annotation*, EnclosingMethod, InnerClasses
