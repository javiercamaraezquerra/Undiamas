# ─── flutter_local_notifications ( keep receivers & Gson helpers ) ───
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class com.dexterous.flutterlocalnotifications.serialization.** { *; }

# Evitar que R8 elimine anotaciones / genéricos (TypeToken)
-keepattributes Signature, *Annotation*, EnclosingMethod, InnerClasses

# ─── Gson ───
-keep class com.google.gson.** { *; }
-keep class com.google.gson.stream.** { *; }
