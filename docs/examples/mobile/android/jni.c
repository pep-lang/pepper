// The JNI layer between MainActivity and the Pepper library: each function
// converts Java's types to the C ones greeter.h declares and back.
#include <jni.h>
#include <string.h>

#include "greeter.h"

JNIEXPORT jstring JNICALL
Java_dev_pepper_demo_MainActivity_greet(JNIEnv* env, jclass cls, jstring name) {
    // GetStringUTFChars is modified UTF-8, which matches UTF-8 for every
    // character outside U+0000 and the supplementary planes.
    const char* bytes = (*env)->GetStringUTFChars(env, name, NULL);
    char* result = greet(bytes, strlen(bytes));
    (*env)->ReleaseStringUTFChars(env, name, bytes);
    jstring greeting = (*env)->NewStringUTF(env, result);
    pepper_string_free(result);
    return greeting;
}

JNIEXPORT jlong JNICALL
Java_dev_pepper_demo_MainActivity_fibonacci(JNIEnv* env, jclass cls, jint n) {
    return fibonacci(n);
}

JNIEXPORT jint JNICALL
Java_dev_pepper_demo_MainActivity_countWords(JNIEnv* env, jclass cls, jstring text) {
    const char* bytes = (*env)->GetStringUTFChars(env, text, NULL);
    int32_t count = count_words(bytes, strlen(bytes));
    (*env)->ReleaseStringUTFChars(env, text, bytes);
    return count;
}
