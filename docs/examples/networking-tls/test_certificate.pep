# A self-signed certificate for `localhost` and `127.0.0.1`, and its key,
# for this example only: the key is public, so never use it for anything
# else.

export test_certificate(): String {
    return "-----BEGIN CERTIFICATE-----
MIIBmzCCAUGgAwIBAgIURcyG8LECUkGDUQnq4wr2SyTfH8AwCgYIKoZIzj0EAwIw
FDESMBAGA1UEAwwJbG9jYWxob3N0MCAXDTI2MDkzMDE2MDQwNloYDzIxMjYwOTA2
MTYwNDA2WjAUMRIwEAYDVQQDDAlsb2NhbGhvc3QwWTATBgcqhkjOPQIBBggqhkjO
PQMBBwNCAAS6V7/9e1PZ6ah6/2Ej6VCR+fwGBGQ33SdVFy0ggLp4p0dlV9k0tvFT
yPJdkPr/sZ+5l02208ogHnk9sONf8/PVo28wbTAdBgNVHQ4EFgQUFl1HIAbN3VXx
j/en9RLR2QoN2PYwHwYDVR0jBBgwFoAUFl1HIAbN3VXxj/en9RLR2QoN2PYwGgYD
VR0RBBMwEYIJbG9jYWxob3N0hwR/AAABMA8GA1UdEwEB/wQFMAMBAf8wCgYIKoZI
zj0EAwIDSAAwRQIhAPw/RhZDgoHFZkEOEAzOQazJ4l3RoKVRNYS9XyrOkIceAiB3
IHZxDB0uoD4leOOsxQzN4uNXDZwjhLCJUHySFW9ctA==
-----END CERTIFICATE-----
";
}

export test_private_key(): String {
    return "-----BEGIN PRIVATE KEY-----
MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgZ9o1y2mmE2xdq/8M
DnvBSs61u+Getq5MzQ7gMuKHfZChRANCAAS6V7/9e1PZ6ah6/2Ej6VCR+fwGBGQ3
3SdVFy0ggLp4p0dlV9k0tvFTyPJdkPr/sZ+5l02208ogHnk9sONf8/PV
-----END PRIVATE KEY-----
";
}
