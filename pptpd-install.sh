#!/bin/bash

# pptpd server installer for Debian, Ubuntu.
# https://github.com/firildax/pptpd-install

function isRoot() {
	if [ "$EUID" -ne 0 ]; then
		return 1
	fi
}

function checkOS() {
	if [[ -e /etc/debian_version ]]; then
		OS="debian"
		source /etc/os-release

		if [[ $ID == "debian" || $ID == "raspbian" ]]; then
			if [[ $VERSION_ID -lt 9 ]]; then
				echo "⚠️ Your version of Debian is not supported."
				echo ""
				echo "However, if you're using Debian >= 9 or unstable/testing then you can continue, at your own risk."
				echo ""
				until [[ $CONTINUE =~ (y|n) ]]; do
					read -rp "Continue? [y/n]: " -e CONTINUE
				done
				if [[ $CONTINUE == "n" ]]; then
					exit 1
				fi
			fi
		elif [[ $ID == "ubuntu" ]]; then
			OS="ubuntu"
			MAJOR_UBUNTU_VERSION=$(echo "$VERSION_ID" | cut -d '.' -f1)
			if [[ $MAJOR_UBUNTU_VERSION -lt 16 ]]; then
				echo "⚠️ Your version of Ubuntu is not supported."
				echo ""
				echo "However, if you're using Ubuntu >= 16.04 or beta, then you can continue, at your own risk."
				echo ""
				until [[ $CONTINUE =~ (y|n) ]]; do
					read -rp "Continue? [y/n]: " -e CONTINUE
				done
				if [[ $CONTINUE == "n" ]]; then
					exit 1
				fi
			fi
		fi
	else
		echo "Looks like you aren't running this installer on a Debian, Ubuntu Linux system"
		exit 1
	fi
}

function initialCheck() {
	if ! isRoot; then
		echo "Sorry, you need to run this as root"
		exit 1
	fi

	checkOS
}

function installUnbound() {
	# If Unbound isn't installed, install it
	if [[ ! -e /etc/unbound/unbound.conf ]]; then

		if [[ $OS =~ (debian|ubuntu) ]]; then
			apt-get install -y unbound

			# Configuration
			echo 'interface: 10.0.0.1
access-control: 10.0.0.1/24 allow
hide-identity: yes
hide-version: yes
use-caps-for-id: yes
prefetch: yes' >>/etc/unbound/unbound.conf

		fi
	fi

	systemctl enable unbound
	systemctl restart unbound
}

function installQuestions() {
	echo "Welcome to the pptpd installer!"
	echo "The git repository is available at: https://github.com/firildax/pptpd-install"
	echo ""

	echo "I need to ask you a few questions before starting the setup."
	echo "You can leave the default options and just press enter if you are ok with them."
	echo ""
	echo "I need to know the IPv4 address of the network interface you want pptpd listening to."
	echo "Unless your server is behind NAT, it should be your public IPv4 address."

	# Detect public IPv4 address and pre-fill for the user
	IP=$(ip -4 addr | sed -ne 's|^.* inet \([^/]*\)/.* scope global.*$|\1|p' | head -1)

	if [[ -z $IP ]]; then
		# Detect public IPv6 address
		IP=$(ip -6 addr | sed -ne 's|^.* inet6 \([^/]*\)/.* scope global.*$|\1|p' | head -1)
	fi
	APPROVE_IP=${APPROVE_IP:-n}
	if [[ $APPROVE_IP =~ n ]]; then
		read -rp "IP address: " -e -i "$IP" IP
	fi
	# If $IP is a private IP address, the server must be behind NAT
	if echo "$IP" | grep -qE '^(10\.|172\.1[6789]\.|172\.2[0-9]\.|172\.3[01]\.|192\.168)'; then
		echo ""
		echo "It seems this server is behind NAT. What is its public IPv4 address or hostname?"
		echo "We need it for the clients to connect to the server."

		PUBLICIP=$(curl -s https://api.ipify.org)
		until [[ $ENDPOINT != "" ]]; do
			read -rp "Public IPv4 address or hostname: " -e -i "$PUBLICIP" ENDPOINT
		done
	fi

	echo ""
	echo "What DNS resolvers do you want to use with the VPN?"
	echo "   1) Current system resolvers (from /etc/resolv.conf)"
	echo "   2) Self-hosted DNS Resolver (Unbound)"
	echo "   3) Cloudflare (Anycast: worldwide)"
	echo "   4) Quad9 (Anycast: worldwide)"
	echo "   5) Quad9 uncensored (Anycast: worldwide)"
	echo "   6) FDN (France)"
	echo "   7) DNS.WATCH (Germany)"
	echo "   8) OpenDNS (Anycast: worldwide)"
	echo "   9) Google (Anycast: worldwide)"
	echo "   10) Yandex Basic (Russia)"
	echo "   11) AdGuard DNS (Anycast: worldwide)"
	echo "   12) NextDNS (Anycast: worldwide)"
	echo "   13) Custom"
	until [[ $DNS =~ ^[0-9]+$ ]] && [ "$DNS" -ge 1 ] && [ "$DNS" -le 13 ]; do
		read -rp "DNS [1-12]: " -e -i 11 DNS
		if [[ $DNS == 2 ]] && [[ -e /etc/unbound/unbound.conf ]]; then
			echo ""
			echo "Unbound is already installed."
			echo "You can allow the script to configure it in order to use it from your pptpd clients"
			echo "We will simply add a second server to /etc/unbound/unbound.conf for the pptpd subnet."
			echo "No changes are made to the current configuration."
			echo ""

			until [[ $CONTINUE =~ (y|n) ]]; do
				read -rp "Apply configuration changes to Unbound? [y/n]: " -e CONTINUE
			done
			if [[ $CONTINUE == "n" ]]; then
				# Break the loop and cleanup
				unset DNS
				unset CONTINUE
			fi
		elif [[ $DNS == "13" ]]; then
			until [[ $DNS1 =~ ^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$ ]]; do
				read -rp "Primary DNS: " -e DNS1
			done
			until [[ $DNS2 =~ ^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$ ]]; do
				read -rp "Secondary DNS (optional): " -e DNS2
				if [[ $DNS2 == "" ]]; then
					break
				fi
			done
		fi
	done
	
	echo ""
	echo "Okay, that was all I needed. We are ready to setup your pptpd server now."
	echo "You will be able to generate a client at the end of the installation."
	APPROVE_INSTALL=${APPROVE_INSTALL:-n}
	if [[ $APPROVE_INSTALL =~ n ]]; then
		read -n1 -r -p "Press any key to continue..."
	fi
}

function install_pptpd() {
	if [[ $AUTO_INSTALL == "y" ]]; then
		# Set default choices so that no questions will be asked.
		APPROVE_INSTALL=${APPROVE_INSTALL:-y}
		APPROVE_IP=${APPROVE_IP:-y}
		DNS=${DNS:-1}
		CLIENT=${CLIENT:-client}
		PASS=${PASS:-1}
		CONTINUE=${CONTINUE:-y}
		PUBLIC_IP=$(curl --retry 5 --retry-connrefused -4 https://ifconfig.co)
		ENDPOINT=${ENDPOINT:-$PUBLIC_IP}
	fi

	# Run setup questions first, and set other variales if auto-install
	installQuestions

	# Get the "public" interface from the default route
	NIC=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
	if [[ -z $NIC ]] && [[ $IPV6_SUPPORT == 'y' ]]; then
		NIC=$(ip -6 route show default | sed -ne 's/^default .* dev \([^ ]*\) .*$/\1/p')
	fi

	# $NIC can not be empty for script rm-pptpd-rules.sh
	if [[ -z $NIC ]]; then
		echo
		echo "Can not detect public interface."
		echo "This needs for setup MASQUERADE."
		until [[ $CONTINUE =~ (y|n) ]]; do
			read -rp "Continue? [y/n]: " -e CONTINUE
		done
		if [[ $CONTINUE == "n" ]]; then
			exit 1
		fi
	fi

	# If pptpd isn't installed yet, install it. This script is more-or-less
	# idempotent on multiple runs, but will only install pptpd from upstream
	# the first time.
	if [[ ! -e /etc/pptpd.conf ]]; then
		if [[ $OS =~ (debian|ubuntu) ]]; then
			apt-get update
			apt-get -y install pptpd
		fi
	fi

	# Find out if the machine uses nogroup or nobody for the permissionless group
	if grep -qs "^nogroup:" /etc/group; then
		NOGROUP=nogroup
	else
		NOGROUP=nobody
	fi

	# Preparing config files
	cp /etc/pptpd.conf /etc/pptpd.conf.orginal
	cp /etc/ppp/pptpd-options /etc/ppp/pptpd-options.orginal

	# Preparing authentication files
	cp /etc/ppp/pap-secrets /etc/ppp/pap-secrets.orginal
	cp /etc/ppp/chap-secrets /etc/ppp/chap-secrets.orginal
	touch /etc/ppp/pap-secrets
	touch /etc/ppp/chap-secrets

	# Generate pptpd.conf
	echo "connections 250" >>/etc/pptpd.conf
	echo "localip 192.168.68.1" >>/etc/pptpd.conf
	echo "remoteip 192.168.68.2-254" >>/etc/pptpd.conf

	# Generate /ect/ppp/pptpd-options
	echo ""
	echo "Just one more to GO!, Which encryption type preferring?"
	echo "   1) PAP"
	echo "   2) CHAP"
	echo "   3) MSCHAP"
	echo "   4) MSCHAPv2 with MPPE-128"
	echo ""
	until [[ $ENCRYPTION_TYPE =~ ^[1-4]$ ]]; do
		read -rp "Select an option [1-4]: " ENCRYPTION_TYPE
	done

	case $ENCRYPTION_TYPE in
	1)
		echo 'name pptpd
+pap' >/etc/ppp/pptpd-options
		;;
	2)
		echo 'name pptpd
refuse-pap
+chap' >/etc/ppp/pptpd-options
		;;
	3)
		echo 'name pptpd
refuse-pap
refuse-chap
+mschap' >/etc/ppp/pptpd-options
		;;
	4)
		echo 'name pptpd
refuse-pap
refuse-chap
refuse-mschap
require-mschap-v2
require-mppe-128' >/etc/ppp/pptpd-options
		;;
	esac

	echo 'proxyarp
nodefaultroute
lock
nobsdcomp
novj
novjccomp
nologfd' >>/etc/ppp/pptpd-options

	# DNS resolvers
	case $DNS in
	1) # Current system resolvers
		# Locate the proper resolv.conf
		# Needed for systems running systemd-resolved
		if grep -q "127.0.0.53" "/etc/resolv.conf"; then
			RESOLVCONF='/run/systemd/resolve/resolv.conf'
		else
			RESOLVCONF='/etc/resolv.conf'
		fi
		;;
	2) # Self-hosted DNS resolver (Unbound)
		echo 'ms-dns 10.0.0.1' >>/etc/ppp/pptpd-options
		;;
	3) # Cloudflare
		echo 'ms-dns 1.0.0.1' >>/etc/ppp/pptpd-options
		echo 'ms-dns 1.1.1.1' >>/etc/ppp/pptpd-options
		;;
	4) # Quad9
		echo 'ms-dns 9.9.9.9' >>/etc/ppp/pptpd-options
		echo 'ms-dns 149.112.112.112' >>/etc/ppp/pptpd-options
		;;
	5) # Quad9 uncensored
		echo 'ms-dns 9.9.9.10' >>/etc/ppp/pptpd-options
		echo 'ms-dns 149.112.112.10' >>/etc/ppp/pptpd-options
		;;
	6) # FDN
		echo 'ms-dns 80.67.169.40' >>/etc/ppp/pptpd-options
		echo 'ms-dns 80.67.169.12' >>/etc/ppp/pptpd-options
		;;
	7) # DNS.WATCH
		echo 'ms-dns 84.200.69.80' >>/etc/ppp/pptpd-options
		echo 'ms-dns 84.200.70.40' >>/etc/ppp/pptpd-options
		;;
	8) # OpenDNS
		echo 'ms-dns 208.67.222.222' >>/etc/ppp/pptpd-options
		echo 'ms-dns 208.67.220.220' >>/etc/ppp/pptpd-options
		;;
	9) # Google
		echo 'ms-dns 8.8.8.8' >>/etc/ppp/pptpd-options
		echo 'ms-dns 8.8.4.4' >>/etc/ppp/pptpd-options
		;;
	10) # Yandex Basic
		echo 'ms-dns 77.88.8.8' >>/etc/ppp/pptpd-options
		echo 'ms-dns 77.88.8.1' >>/etc/ppp/pptpd-options
		;;
	11) # AdGuard DNS
		echo 'ms-dns 94.140.14.14' >>/etc/ppp/pptpd-options
		echo 'ms-dns 94.140.15.15' >>/etc/ppp/pptpd-options
		;;
	12) # NextDNS
		echo 'ms-dns 45.90.28.167' >>/etc/ppp/pptpd-options
		echo 'ms-dns 45.90.30.167' >>/etc/ppp/pptpd-options
		;;
	13) # Custom DNS
		echo "ms-dns $DNS1" >>/etc/ppp/pptpd-options
		if [[ $DNS2 != "" ]]; then
			echo "ms-dns $DNS2" >>/etc/ppp/pptpd-options
		fi
		;;
	esac

	# Enable routing
	echo 'net.ipv4.ip_forward=1' >/etc/sysctl.d/99-pptpd.conf

	# Apply sysctl rules
	sysctl --system

	# Finally, restart and enable pptpd #armin
	if [[ $OS == "ubuntu" ]] || [[ $OS == "debian" ]]; then
		# On Ubuntu 16.04, we use the package from the pptpd repo
		# This package uses a sysvinit service
		systemctl enable pptpd
		systemctl restart pptpd
	fi

	if [[ $DNS == 2 ]]; then
		installUnbound
	fi

	# Add iptables rules in two scripts
	mkdir -p /etc/iptables

	# Script to add rules
	echo "#!/bin/sh
iptables -t nat -A POSTROUTING -o $NIC -j MASQUERADE
iptables --table nat --append POSTROUTING --out-interface ppp0 -j MASQUERADE
iptables -I INPUT -s 192.168.68.0/24 -i ppp0 -j ACCEPT
iptables --append FORWARD --in-interface $NIC -j ACCEPT" >/etc/iptables/add-pptpd-rules.sh

	# Script to remove rules
	echo "#!/bin/sh
iptables -D POSTROUTING -o $NIC -j MASQUERADE
iptables -D INPUT -s 192.168.68.0/24 -i ppp0 -j ACCEPT" >/etc/iptables/rm-pptpd-rules.sh

	chmod +x /etc/iptables/add-pptpd-rules.sh
	chmod +x /etc/iptables/rm-pptpd-rules.sh

	# Handle the rules via a systemd script
	echo "[Unit]
Description=iptables rules for pptpd
Before=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/etc/iptables/add-pptpd-rules.sh
ExecStop=/etc/iptables/rm-pptpd-rules.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target" >/etc/systemd/system/iptables-pptpd.service

	# Enable service and apply rules
	systemctl daemon-reload
	systemctl enable iptables-pptpd
	systemctl start iptables-pptpd

	# If the server is behind a NAT, use the correct IP address for the clients to connect to
	if [[ $ENDPOINT != "" ]]; then
		IP=$ENDPOINT
	fi

	# Generate the custom in pap-secrets and chap-secrest file
	echo ""
	echo "If you want to add clients, you simply need to run this script another time!"
	echo ""
}

function newClientPAP() {
	echo ""
	echo "Tell me a name for the client."
	echo "The name must consist of alphanumeric character. It may also include an underscore or a dash."

	until [[ $CLIENT =~ ^[a-zA-Z0-9_-]+$ ]]; do
		read -rp "PAP Client name: " -e CLIENT
	done

	echo ""
	echo "Choose Password for PAP CLIENT name: [$CLIENT]"

	until [[ $PASS =~ ^[a-zA-Z0-9_-]+$ ]]; do
		read -rp "PAP Client pass: " -e PASS
	done

	echo "$CLIENT pptpd $PASS *" >>/etc/ppp/pap-secrets

	echo ""
	echo "Client $CLIENT added."
	
	exit 0
}

function newClientCHAP() {
	echo ""
	echo "Tell me a name for the client."
	echo "The name must consist of alphanumeric character. It may also include an underscore or a dash."

	until [[ $CLIENT =~ ^[a-zA-Z0-9_-]+$ ]]; do
		read -rp "CHAP Client name: " -e CLIENT
	done

	echo ""
	echo "Choose Password for CHAP CLIENT name: [$CLIENT]"

	until [[ $PASS =~ ^[a-zA-Z0-9_-]+$ ]]; do
		read -rp "CHAP Client pass: " -e PASS
	done

	echo "$CLIENT pptpd $PASS *" >>/etc/ppp/chap-secrets

	echo ""
	echo "Client $CLIENT added."
	
	exit 0
}

function revokeClientPAP() {
	NUMBEROFCLIENTS=$(tail -n +1 /etc/ppp/pap-secrets | grep -c " ")
	if [[ $NUMBEROFCLIENTS == '0' ]]; then
		echo ""
		echo "You have no existing clients!"
		exit 1
	fi

	echo ""
	echo "Select the existing PAP client you want to revoke"
	tail -n +1 /etc/ppp/pap-secrets | grep " " | cut -d ' ' -f 1 | nl -s ') '
	until [[ $CLIENTNUMBER -ge 1 && $CLIENTNUMBER -le $NUMBEROFCLIENTS ]]; do
		if [[ $CLIENTNUMBER == '1' ]]; then
			read -rp "Select one client [1]: " CLIENTNUMBER
		else
			read -rp "Select one client [1-$NUMBEROFCLIENTS]: " CLIENTNUMBER
		fi
	done
	CLIENT=$(sed -i "$CLIENTNUMBER"d /etc/ppp/pap-secrets)

	echo ""
	echo "PAP client revoked."
}

function revokeClientCHAP() {
	NUMBEROFCLIENTS=$(tail -n +1 /etc/ppp/chap-secrets | grep -c " ")
	if [[ $NUMBEROFCLIENTS == '0' ]]; then
		echo ""
		echo "You have no existing clients!"
		exit 1
	fi

	echo ""
	echo "Select the existing CHAP client you want to revoke"
	tail -n +1 /etc/ppp/chap-secrets | grep " " | cut -d ' ' -f 1 | nl -s ') '
	until [[ $CLIENTNUMBER -ge 1 && $CLIENTNUMBER -le $NUMBEROFCLIENTS ]]; do
		if [[ $CLIENTNUMBER == '1' ]]; then
			read -rp "Select one client [1]: " CLIENTNUMBER
		else
			read -rp "Select one client [1-$NUMBEROFCLIENTS]: " CLIENTNUMBER
		fi
	done
	CLIENT=$(sed -i "$CLIENTNUMBER"d /etc/ppp/chap-secrets)

	echo ""
	echo "CHAP client revoked."
}

function removeUnbound() {
	# Remove pptpd-related config
	sed -i '/include: \/etc\/unbound\/pptpd.conf/d' /etc/unbound/unbound.conf
	rm /etc/unbound/pptpd.conf

	until [[ $REMOVE_UNBOUND =~ (y|n) ]]; do
		echo ""
		echo "If you were already using Unbound before installing pptpd, I removed the configuration related to pptpd."
		read -rp "Do you want to completely remove Unbound? [y/n]: " -e REMOVE_UNBOUND
	done

	if [[ $REMOVE_UNBOUND == 'y' ]]; then
		# Stop Unbound
		systemctl stop unbound

		if [[ $OS =~ (debian|ubuntu) ]]; then
			apt-get remove --purge -y unbound
		fi

		rm -rf /etc/unbound/

		echo ""
		echo "Unbound removed!"
	else
		systemctl restart unbound
		echo ""
		echo "Unbound wasn't removed."
	fi
}

function remove_pptpd() {
	echo ""
	read -rp "Do you really want to remove pptpd server? [y/n]: " -e -i n REMOVE
	if [[ $REMOVE == 'y' ]]; then

		# Stop pptpd
		if [[ $OS == "ubuntu" ]] || [[ $OS == "debian" ]]; then
			systemctl disable pptpd
			systemctl stop pptpd
		fi

		# Remove the iptables rules related to the script
		systemctl stop iptables-pptpd
		# Cleanup
		systemctl disable iptables-pptpd
		rm /etc/systemd/system/iptables-pptpd.service
		systemctl daemon-reload
		rm /etc/iptables/add-pptpd-rules.sh
		rm /etc/iptables/rm-pptpd-rules.sh
		apt purge pptpd -y

		# Unbound
		if [[ -e /etc/unbound/pptpd.conf ]]; then
			removeUnbound
		fi
		echo ""
		echo "pptpd removed!"
	else
		echo ""
		echo "Removal aborted!"
	fi
}

function manageMenu() {
	echo "Welcome to pptpd-install!"
	echo "The git repository is available at: https://github.com/firildax/pptpd-install"
	echo ""
	echo "It looks like pptpd is already installed."
	echo ""
	echo "What do you want to do?"
	echo "   1) Add a new user[PAP]"
	echo "   2) Add a new user[CHAP]"
	echo "   3) Revoke existing PAP user"
	echo "   4) Revoke existing CHAP user"
	echo "   5) Remove pptpd"
	echo "   6) Exit"
	until [[ $MENU_OPTION =~ ^[1-6]$ ]]; do
		read -rp "Select an option [1-6]: " MENU_OPTION
	done

	case $MENU_OPTION in
	1)
		newClientPAP
		;;
	2)
		newClientCHAP
		;;
	3)
		revokeClientPAP
		;;
	4)
		revokeClientCHAP
		;;
	5)
		remove_pptpd
		;;
	6)
		exit 0
		;;
	esac
}

# Check for root, TUN, OS...
initialCheck

# Check if pptpd is already installed
if [[ -e /etc/pptpd.conf && $AUTO_INSTALL != "y" ]]; then
	manageMenu
else
	install_pptpd
fi
