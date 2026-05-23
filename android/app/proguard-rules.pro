-keep class com.follow.clask.models.**{ *; }
-keep class com.follow.clask.services.**{ *; }
-keep class com.follow.clask.plugins.**{ *; }
-keep class com.follow.clask.extensions.**{ *; }
-keep class com.follow.clask.GlobalState { *; }

-keepclassmembers class * {
    native <methods>;
}

-keep class * extends java.lang.reflect.** { *; }

-dontwarn javax.annotation.**
-dontwarn com.google.gson.**
-dontwarn org.smali.**

-keepattributes *Annotation*
-keepattributes Signature
-keepattributes Exceptions

-keep class kotlin.Metadata { *; }
-keep class kotlin.Unit { *; }
-keep class kotlin.coroutines.Continuation { *; }

-dontwarn kotlinx.coroutines.**
