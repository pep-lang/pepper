package dev.pepper.demo;

import android.app.Activity;
import android.os.Bundle;
import android.util.Log;
import android.widget.TextView;
import pepper.greeter.Greeter;
import pepper.greeter.Tally;

// An Android activity that calls the Pepper library in ../greeter.pep
// through the Java class `--lib aar` generates, pepper.greeter.Greeter,
// whose JNI functions are in the .aar's libgreeter.so.
public class MainActivity extends Activity {
    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        // Native code cannot find the app's folders: hand them to Pepper
        // first, for os.app_directories() and io.Directory.temp().
        Greeter.pepperSetAppDirectories(getFilesDir().getPath(), getCacheDir().getPath());
        long total;
        try (Tally tally = Greeter.tallyNew()) {
            Greeter.tallyAdd(tally, 3);
            total = Greeter.tallyAdd(tally, 4);
        }
        String text = Greeter.greet("Android")
            + "\nfibonacci(50) = " + Greeter.fibonacci(50)
            + "\nwords: " + Greeter.countWords("Pepper runs on Android")
            + "\neven: " + Greeter.isEven(10) + ", half: " + Greeter.half(2.5) + ", tally: " + total
            // A string crosses as UTF-8, not JNI's modified UTF-8.
            + "\nutf8: " + Greeter.greet("caf\u00e9 \uD83C\uDF36").equals("Hello, caf\u00e9 \uD83C\uDF36, from Pepper")
            // A file in the cache folder, written and read by Pepper.
            + "\nnote: " + Greeter.saveNote("kept in the cache");
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
