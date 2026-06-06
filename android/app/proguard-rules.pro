# Retrofit + OkHttp
-dontwarn okhttp3.**
-dontwarn retrofit2.**
-keep class retrofit2.** { *; }
-keepattributes Signature
-keepattributes Exceptions

# Gson data models
-keep class com.torn.bountyhunter.data.** { *; }

# Keep enums
-keepclassmembers enum * { *; }
