# OpenWRT
Confis for router

## ########  Filtering traffic with IP sets by DNS  ##########
https://openwrt.org/docs/guide-user/firewall/fw3_configurations/dns_ipset

uci -q delete dhcp.filter
uci set dhcp.filter="ipset"
uci add_list dhcp.filter.name="ss_rules_dst_forward"
uci add_list dhcp.filter.domain="2ip.ru"
uci commit dhcp

### Add domains
uci add_list dhcp.filter.domain="example.com"
### Remove domains
uci del_list dhcp.filter.domain="example.com"

### #######  Load domen list  ##########
nslookup www.google.com $@>/dev/null  || return 0
curl https://reestr.rublacklist.net/api/v3/dpi/ |jq '.[].domains[]' |while read d; do
	d=$(echo $d |tr -d \")
    echo nftset=/$d/4#inet#fw4#ss_rules_dst_forward
done > /tmp/dnsmasq.d/domains.lst
service dnsmasq restart

### #######  install stubby  ##########################
https://openwrt.org/docs/guide-user/services/dns/dot_dnsmasq_stubby
	
opkg update
opkg install stubby
 
### Enable DNS encryption
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
