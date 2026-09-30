import async;

# Every value the select can return: one case per channel.
enum Event {
    Line(text: String),
    Reading(value: long),
    Stop,
}

const lines = async.Channel<String>();
const readings = async.Channel<long>();
const stop = async.Channel<bool>();

read_lines() {
    lines.send("first");
    lines.send("second");
    lines.close();
}

read_sensor() {
    var i: long = 1;
    while (i <= 3) {
        readings.send(i * 10);
        i = i + 1;
    }
    readings.close();
}

main(): int {
    var select = async.Select<Event>();
    select.receive(lines, (text: String): Event => Event.Line(text));
    select.receive(readings, (value: long): Event => Event.Reading(value));
    select.receive(stop, (unused: bool): Event => Event.Stop);

    var threads = [async.Thread.spawn(read_lines), async.Thread.spawn(read_sensor)];
    var text = 0;
    var total: long = 0;
    var running = true;
    while (running) {
        match (select.wait()) {
            Ok(event) => {
                match (event) {
                    Line(line) => {
                        text = text + 1;
                    }
                    Reading(value) => {
                        total = total + value;
                    }
                    Stop => {
                        running = false;
                    }
                }
            }
            Err(error) => {
                # Every channel is closed and empty (`stop` included, below).
                running = false;
            }
        }
        if (text == 2 && total == 60) {
            stop.close();
        }
    }
    for (var thread in threads) {
        thread.join();
    }
    assert(text == 2 && total == 60, "every value arrived once");
    return 0;
}
