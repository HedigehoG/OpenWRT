opkg update && cd /tmp/ && opkg download dnsmasq-full
opkg remove dnsmasq && opkg install dnsmasq-full --cache /tmp/
mv /etc/config/dhcp-opkg /etc/config/dhcp
#install shadowsocks and some apps for automated, stubby - DNS DoH, jq - for json, curl - by itself
opkg install shadowsocks-libev-ss-redir shadowsocks-libev-ss-rules luci-app-shadowsocks-libev stubby jq curl

# Enable DNS DoH encryption
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

# Setup ipsets https://openwrt.org/docs/guide-user/base-system/dhcp#ip_sets
uci set dhcp.ss_rules="ipset"
uci add_list dhcp.ss_rules.name="ss_rules_dst_forward"
uci add_list dhcp.ss_rules.name="ss_rules6_dst_forward"
uci add_list dhcp.ss_rules.domain="linkedin.com"
uci commit dhcp

##########  Create Bash app  ##########
# antiban R - Reload domain from list, Q - refresh
# antiban ex.net - add new domen, antiban D ex.net -del from list

mkdir /etc/antiban/
touch /etc/antiban/sites

cat << "EOF" > /etc/antiban/aniblock.sh
sitef="/etc/antiban/sites"
dnslistrule="/tmp/dnsmasq.d/domains.lst"

uci set dhcp.dom="ipset"

function add_d {
	uci add_list dhcp.ss_rules.domain="$1"
	uci commit dhcp
}

# you can add here any your lists of domains
function load_list {
	if [ -z $1 ]
 	then 
		curl https://reestr.rublacklist.net/api/v3/dpi/ |jq '.[].domains[]' |while read d; do
			d=$(echo $d |tr -d \")
			echo nftset=/$d/4#inet#fw4#ss_rules_dst_forward
		done > dnslistrule
	fi
 
	cat $sitef |while read d; do
	echo nftset=/$d/4#inet#fw4#ss_rules_dst_forward
	done >> $dnslistrule
}

case $1 in
C)
	cat /dev/null > $dnslistrule
 	nft flush set inet fw4 ss_rules_dst_forward
  	echo 'Cleaned'
;;

Q)
	load_list only
;;
D)
	grep -x $2 $sitef | sed -i "/^$2/d" $sitef && sed -i '/'"'"$2"'"'/d' /etc/config/dhcp && sed -i '/'$2'/d' $dnslistrule
 	nft flush set inet fw4 ss_rules_dst_forward
  	echo "$2    Removed"
;;
R)	
	while ! $(nslookup www.google.com > /dev/null) ;do
		echo "not internet"
	done
	load_list
;;
'')
	echo "insert domen name for add to list antiban, R -reload, Q -load from custom list only, D ex.net -remove /n C -clear list rules"
 	exit 0
;;
*)
	while [ -n "$1" ]
	do
		if ! grep -x $1 $sitef; then
			if resolveip -4 $1; then
				echo $1 >> $sitef
				add_d $1				
			else echo "bad address"
			fi
		else echo "Exist \"$1\" in sites"
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
