// PAC file for the "personal" Firefox profile.
// Routes Tailscale traffic directly; everything else through Mullvad SOCKS5.

function FindProxyForURL(url, host) {
    // Tailscale IPs (100.64.0.0/10)
    if (isInNet(host, "100.64.0.0", "255.192.0.0")) {
        return "DIRECT";
    }

    // Tailscale MagicDNS
    if (shExpMatch(host, "*.ts.net")) {
        return "DIRECT";
    }

    // Localhost and private networks
    if (isPlainHostName(host) ||
        host === "localhost" ||
        host === "127.0.0.1" ||
        isInNet(host, "10.0.0.0", "255.0.0.0") ||
        isInNet(host, "172.16.0.0", "255.240.0.0") ||
        isInNet(host, "192.168.0.0", "255.255.0.0")) {
        return "DIRECT";
    }

    // Everything else through Mullvad
    return "SOCKS5 127.0.0.1:1081";
}
