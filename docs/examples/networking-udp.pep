import io;

main(): int {
    var loopback = io.SocketAddress(io.IpAddress.loopback_v4(), 0);
    var sender = io.UdpSocket.bind(loopback).value();
    var receiver = io.UdpSocket.bind(loopback).value();

    var datagram = Array<u8>();
    datagram.append(1);
    datagram.append(2);
    datagram.append(3);
    sender.send_to(datagram, receiver.local_address().value());

    # One receive takes one whole datagram and says who sent it.
    var buffer = Array<u8>();
    var (count, from) = receiver.receive_from(buffer, 1500).value();
    assert(count == 3 && buffer[2] == 3, "the datagram arrived whole");
    assert(from == sender.local_address().value(), "from the sender");
    return 0;
}
