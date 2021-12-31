# pptp-install

pptpd installer for Debian, Ubuntu.

This script will let you setup your own VPN server in just a few seconds.

You can also check out [openvpn-install](https://github.com/firildax/openvpn-install) or [wireguard-install](https://github.com/firildax/wireguard-install), a simple installer for a simpler, safer, faster and more modern VPN protocol.

## Usage

First, get the script and make it executable:

```bash
git clone https://github.com/firildax/pptpd-install.git
cd pptpd-install
chmod +x pptpd-install.sh
```

Then run it:

```sh
./pptpd-install.sh
```

You need to run the script as root.

The first time you run it, you'll have to follow the assistant and answer a few questions to setup your VPN server.

When pptpd is installed, you can run the script again, and you will get the choice to:

- Add a PAP client
- Add a CHAP client
- Remove a PAP client
- Remove a CHAP client
- Uninstall pptpd

In your /etc/ppp directory, you will have pap-secrets and chap-secrets files. These are the client authentication configuration files.

If the server is behind NAT, you can specify its endpoint with the `ENDPOINT` variable. If the endpoint is the public IP address which it is behind, you can use `ENDPOINT=$(curl -4 ifconfig.co)` (the script will default to this). The endpoint can be an IPv4 or a domain.

Other variables can be set depending on your choice (encryption, compression). You can search for them in the `installQuestions()` function of the script.

## Features

- Installs and configures a ready-to-use pptpd server
- Iptables rules and forwarding managed in a seamless way
- If needed, the script can cleanly remove pptpd, including configuration and iptables rules
- Variety of DNS resolvers to be pushed to the clients
- Choice to use a self-hosted resolver with Unbound (supports already existing Unbound installations)
- Unprivileged mode: run as `nobody`/`nogroup`
- Block DNS leaks on Windows 10

## Compatibility

The script supports these OS and architectures:

|                 | i386 | amd64 | armhf | arm64 |
| --------------- | ---- | ----- | ----- | ----- |
| Debian >= 9     | ✅   | ✅    | ✅    | ✅    |
| Ubuntu 16.04    | ✅   | ✅    | ❌    | ❌    |
| Ubuntu >= 18.04 | ✅   | ✅    | ✅    | ✅    |

To be noted:

- It should work on Debian 8+ and Ubuntu 16.04+. But versions not in the table above are not officially supported.
- The script requires `systemd`.
- The script is regularly tested against `amd64` only.

## Licence

This project is under the [MIT Licence](https://github.com/firildax/pptp-install/blob/master/LICENSE)
