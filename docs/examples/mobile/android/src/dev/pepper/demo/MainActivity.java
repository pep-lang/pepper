package dev.pepper.demo;

import android.app.Activity;
import android.os.Bundle;
import android.util.Log;
import android.widget.TextView;

// An Android activity that calls the Pepper library in ../greeter.pep
// through JNI: libgreeter.so holds the Pepper code and the JNI functions in
// jni.c that convert Java's types to the C ones greeter.h declares.
public class MainActivity extends Activity {
    static {
        System.loadLibrary("greeter");
    }

    static native String greet(String name);

    static native long fibonacci(int n);

    static native int countWords(String text);

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        String text = greet("Android")
            + "\nfibonacci(50) = " + fibonacci(50)
            + "\nwords: " + countWords("Pepper runs on Android");
        // What build.sh checks: the app reached Pepper at launch.
        for (String line : text.split("\n")) {
            Log.i("PepperDemo", line);
        }
        TextView view = new TextView(this);
        view.setText(text);
        view.setTextSize(20);
        view.setPadding(48, 48, 48, 48);
        setContentView(view);
    }
}
