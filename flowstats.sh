#!/bin/bash

while :
do
  echo "" > /tmp/flow_by_station.txt;
  HW_ADDR=`cat /sys/class/net/$1/address`;
  # 清空ARP缓存
  arp -n | grep $1 | awk '{print "arp -d " $1}' | sh -x

  tcpdump -i $1 -e -n -q -tt -l | busybox awk '
  function ceil(x) {return int(x) + (x > int(x))};
  function ip_join(ip) {split(ip,res,"."); ip=res[1]"."res[2]"."res[3]"."res[4]; _len=length(ip); if(substr(ip,_len,1)==":") {ip=substr(ip,1,_len-1);} return ip};
  BEGIN {
    # configurations
    dbg = 1                   # dbg=0 or unset dbg to close debug mode
    dst_by_station = "/tmp/flow_by_station.txt"

    IP_PREFIX = "192.168"
    # IP_PREFIX = "10.60.242"
    PREFIX_LEN = length(IP_PREFIX)

    local_mac = "'$HW_ADDR'"
    printf("local mac is: "local_mac"\n")

    # Refresh frequence. ::second.
    flush_freq_time = '$2'
    pre_time = systime() + 2
    init_time = pre_time

    title_sta_statics[0] = "rt_rx_b"
    title_sta_statics[1] = "rt_rx_p"
    title_sta_statics[2] = "rt_tx_b"
    title_sta_statics[3] = "rt_tx_p"
    # title_sta_statics[4] = "rx_b"
    title_sta_statics[5] = "rx_p"
    # title_sta_statics[6] = "tx_b"
    title_sta_statics[7] = "tx_p"
    title_sta_statics[8] = "conn_time"
    title_sta_statics[9] = "zero_time"
    for(x in title_sta_statics) title_sta = title_sta"\t"title_sta_statics[x]

    zero_time_th = 35     # If there are `zero_time_th` sconds not receive packs, remove this station.

    printf("Start>>>"pre_time", flush_freq_time="flush_freq_time"\n")
  };
  {
    # init
    src = $2
    dst = substr($4, 1, 17)

    # Whether consider MAC header length
    pack_len = $7

    # Filters
    ignore = 0
    if($5 != "IPv4,") ignore = 1

    target_mac[0] = src
    target_mac[1] = dst
    for(x in target_mac) {
      _mac = target_mac[x]
      if(_mac == "ff:ff:ff:ff:ff:ff") ignore = 1
      if(_mac == "00:00:00:00:00:00") ignore = 1
      # if(substr(_mac, 1, 5) == "aa:aa") ignore = 1
    }

    # Process ARP
    if($5 == "ARP," && $8 == "Reply" && substr($9, 1, PREFIX_LEN) == IP_PREFIX) {
      _mac = substr($11, 1, 17)
      stations[$9] = _mac
      print "---> ARP: " $9" @ "_mac
    }

    # calc flow by stations
    if(ignore == 0) {
      s_ip = ip_join($8)
      d_ip = ip_join($10)

      # 更新统计
      if(substr(d_ip, 1, PREFIX_LEN) == IP_PREFIX) {
        # if(!(d_ip in stations)) {
        if(!flow_by_station[d_ip",conn_time"]) {
          # stations[d_ip] = 0
          print "Add Sta: "d_ip
          for(y in title_sta_statics) {
            _y = title_sta_statics[y]
            flow_by_station[d_ip","_y] = 0
          }
          flow_by_station[d_ip",conn_time"] = systime()
        }
        flow_by_station[d_ip",rt_rx_b"] += pack_len
        flow_by_station[d_ip",rt_rx_p"] += 1
        # flow_by_station[d_ip",rx_b"] += pack_len
        flow_by_station[d_ip",rx_p"] += 1
      }

      if(substr(s_ip, 1, PREFIX_LEN) == IP_PREFIX) {
        if(!flow_by_station[s_ip",conn_time"]) {
          # stations[s_ip] = 0
          print "Add Sta: "s_ip
          for(y in title_sta_statics) {
            _y = title_sta_statics[y]
            flow_by_station[s_ip","_y] = 0
          }
          flow_by_station[s_ip",conn_time"] = systime()
        }
        flow_by_station[s_ip",rt_tx_b"] += pack_len
        flow_by_station[s_ip",rt_tx_p"] += 1
        # flow_by_station[s_ip",tx_b"] += pack_len
        flow_by_station[s_ip",tx_p"] += 1
      }
    }

    # Export flow info
    time_past = systime() - pre_time
    if(time_past >= flush_freq_time) {
      time_cur = systime()
      pre_time = time_cur
      _cont = "station     	   \tip_addr    "title_sta
      print(_cont) > dst_by_station
      if(dbg) printf(_cont"\n")
      for(ip in stations) {
        mac = stations[ip]
        if(mac == local_mac) continue
        if(mac == 0) continue
        if(!flow_by_station[ip",conn_time"]) continue
        _cont = mac"\t"ip
        for(y in title_sta_statics) {
          _y = title_sta_statics[y]
          val = flow_by_station[ip","_y]
          if(_y == "conn_time") val = time_cur - val
          else if(_y == "rt_rx_b" || _y == "rt_rx_p" || _y == "rt_tx_b" || _y == "rt_tx_p") val = ceil(val / time_past)

          _cont = _cont"\t"val
        }

        print(_cont) >> dst_by_station
        if(dbg) printf(_cont"\n")

        if(flow_by_station[ip",rt_rx_p"]+flow_by_station[ip",rt_tx_p"] == 0) flow_by_station[ip",zero_time"] += time_past
        else flow_by_station[ip",zero_time"] = 0

        flow_by_station[ip",rt_rx_b"] = 0
        flow_by_station[ip",rt_rx_p"] = 0
        flow_by_station[ip",rt_tx_b"] = 0
        flow_by_station[ip",rt_tx_p"] = 0

        if(flow_by_station[ip",zero_time"] >= zero_time_th) {
          delete stations[ip]
          delete flow_by_station[ip",conn_time"]
        }
      }
      close(dst_by_station);
      # fflush("");
      fflush("/tmp/flow_by_station.txt");

      if(dbg) printf("\n")
    }
  };
  END {
    printf("\nIPv4 total packet: %d\n", NR)
  }'

  sleep 5;
done
