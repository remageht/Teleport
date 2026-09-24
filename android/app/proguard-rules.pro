# Release-правила: MLKit Vision & Text Recognition
# Исключить предупреждения для опциональных языковых скриптов (китайский, деванагари и т.д.)
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.internal.mlkit_**
-dontwarn com.google.android.gms.tasks.**

# Сохранить все классы MLKit и плагинов
-keep class com.google.mlkit.** { *; }
-keep interface com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }
-keep class com.google_mlkit_text_recognition.** { *; }
-keep class com.google_mlkit_commons.** { *; }
-keep class com.google.android.gms.tasks.** { *; }

# Сохранить аннотации и сигнатуры для рефлексии и DI
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod
