opkg update && cd /tmp/ && opkg download dnsmasq-full
opkg remove dnsmasq && opkg install dnsmasq-full --cache /tmp/
mv /etc/config/dhcp-opkg /etc/config/dhcp
opkg install jq shadowsocks-libev-ss-redir shadowsocks-libev-ss-rules luci-app-shadowsocks-libev stubby resolveip

# Enable DNS encryption
service dnsmasq stop
uci set dhcp.@dnsmasq[0].noresolv="1"
uci set dhcp.@dnsmasq[0].localuse="1"
uci -q delete dhcp.@dnsmasq[0].server
uci -q get stubby.global.listen_address \
| sed -e "s/\s/\n/g;s/@/#/g" \
| while read -r STUBBY_SERV
do uci add_list dhcp.@dnsmasq[0].server="${STUBBY_SERV}"
done
uci commit dhcp
service dnsmasq start		

##########  Create Bash app  ##########
# antiban R - Reload domain from list, Q - refresh 
# antiban ex.net - add new domen

mkdir /etc/antiban/
touch /etc/antiban/sites
uci set dhcp.dom="ipset"
uci add_list dhcp.dom.name="ss_rules_dst_forward"

cat << "EOF" > /etc/antiban/aniblock.sh
sitef="/etc/antiban/sites"
uci set dhcp.dom="ipset"

function add_d {
	uci add_list dhcp.dom.domain="$1"
	uci commit dhcp
}

# you can add here any your lists of domains
function load_list {
	curl https://reestr.rublacklist.net/api/v3/dpi/ |jq '.[].domains[]' |while read d; do
		d=$(echo $d |tr -d \")
		echo nftset=/$d/4#inet#fw4#ss_rules_dst_forward
	done > /tmp/dnsmasq.d/domains.lst
	
	cat $sitef |while read d; do
	echo nftset=/$d/4#inet#fw4#ss_rules_dst_forward
	done >> /tmp/dnsmasq.d/domains.lst
}

case $1 in
Q)
	load_list
;;
D)
	grep -x $2 $sitef | sed -i "/^$2/d" $sitef && sed -i '/'"'"$2"'"'/d' /etc/config/dhcp	
;;
R)	
	while ! $(nslookup www.google.com > /dev/null) ;do
		echo "not internet"
	done
	load_list
;;
'')
	echo "insert domen name for add to list antiban"
;;
*)
	while [ -n "$1" ]
	do
		resolveip -4 $1
			if [ $? -eq 0 ]; then
				add_d $1
				grep -x $1 $sitef > /dev/null || echo $1 >> $sitef
			else echo "bad address"
			fi
		shift
	done  
;;
esac
service dnsmasq restart
EOF

chmod +x /etc/antiban/aniblock.sh
ln -s /etc/antiban/aniblock.sh /bin/aniblock
sed -i '/exit 0/i aniblock R' /etc/rc.local
