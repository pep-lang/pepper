import process;
import [Signal] from process;

main(): int {
    var stop = process.signals([Signal.Interrupt, Signal.Terminate]);
    # Serve until Ctrl-C or a request to terminate arrives: here, for at most
    # a tenth of a second.
    var signal = stop.receive_for(100);
    if (signal.is_ok()) {
        print("shutting down cleanly");
    }
    # Closing the channel gives the signals back their default action.
    stop.close();
    return 0;
}
