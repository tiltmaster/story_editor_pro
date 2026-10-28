# Consumer rules shipped with the story_editor_pro AAR.
#
# This plugin bundles com.google.mediapipe:tasks-vision for on-device face
# tracking and selfie segmentation. Those AARs carry no consumer rules of their
# own, so without the keeps below every consuming application that minifies its
# release build silently loses AR: R8 renames the classes and members that
# MediaPipe's native layer resolves through JNI by name, FaceLandmarker
# construction then fails with NoSuchMethodError / NoClassDefFoundError, and the
# face lenses report themselves unavailable. Debug builds are unaffected, which
# is why this never reproduces locally or in CI.

# MediaPipe's framework classes are looked up from C++ through JNI by name, and
# packet callbacks are invoked on members that must keep their signatures.
-keep class com.google.mediapipe.** { *; }
-keep interface com.google.mediapipe.** { *; }
-dontwarn com.google.mediapipe.**

# MediaPipe graphs are configured with protobuf-javalite messages whose fields
# are read reflectively while the message is built.
-keepclassmembers class * extends com.google.protobuf.GeneratedMessageLite {
    <fields>;
}
-dontwarn com.google.protobuf.**

# The GPU and CPU delegates are loaded through JNI from the bundled runtime.
-keep class org.tensorflow.lite.** { *; }
-dontwarn org.tensorflow.lite.**

# AutoValue backs the Tasks option/result types that cross the JNI boundary.
-dontwarn com.google.auto.value.**
