# R8 keep rules — silence warnings about optional dependencies that MediaPipe
# (pulled in transitively by flutter_gemma + google_mlkit_translation) references
# only via annotations/reflection. These classes are not on the runtime classpath
# and are safe to ignore for our use case.

-dontwarn com.google.auto.value.extension.memoized.Memoized
-dontwarn com.google.mediapipe.proto.CalculatorProfileProto$CalculatorProfile
-dontwarn com.google.mediapipe.proto.GraphTemplateProto$CalculatorGraphTemplate

# Keep TensorFlow Lite / MediaPipe native bridges intact so they aren't shrunk
# out — flutter_gemma loads them dynamically.
-keep class com.google.mediapipe.** { *; }
-keep class org.tensorflow.lite.** { *; }
-dontwarn com.google.mediapipe.**
-dontwarn org.tensorflow.lite.**
