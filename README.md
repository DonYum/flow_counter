# Android系统上，在wifi热点模式下，如何监控每个连接设备的实时网速？

## 问题描述

Android系统上，在wifi热点模式下，如何监控每个连接设备的实时网速？
接口返回：mac地址 + 实时网速

## 可行方案

### 修改传输层代码做统计

流量统计不止是根据MAC地址做统计，还需要考虑到通信协议。因此在数据链路层嵌入代码是不妥的，最合适的地方是传输层。
但是无论是数据链路层还是传输层代码，都位于内核空间，修改成本太大。
因此该方案不以考虑。

### 使用流量统计工具

由于需要在wifi热点模式下统计各个连接终端的实时网速，目前没有找到合适的工具可以直接使用。
PS：正在跟以前做AP路由器的同事探讨，目前没有结论。

### 使用siniffer工具做统计

snniffer工具，比如tmpdump，具有很灵活的抓包能力，不止可以分析协议，还可以按主机、IP、端口做过滤，而且具有灵活的输出方式。

因此可以考虑抓包后使用grep、awk等工具做分析，然后写入文件，供上层调用。

#### 具体实施方法

代码如下：

```sh
sudo tcpdump -i eno1 -e -n -q -tt | grep "IPv4" | awk '
BEGIN {
    # TODO：是否需要加载之前的流量统计信息？
    # configurations
    dbg = "true"                    # 设置为true之后会显示到stdout
    flush_freq = 1000               # 刷新结果的频率，目前使用包计数的方法。 TODO：改成时间周期统计方法。
    if_add_mac_header = "true"      # 是否把MAC header的长度计算到流量中
    dst_dir = "./"                  # 统计结果存放位置
    dst_by_station = dst_dir"flow_by_station.txt"       # 按照station统计到的结果
    dst_by_pair = dst_dir"flow_by_pair.txt"             # 按照pair(src > dst)统计到的结果

    if(dbg == "true") printf("Start>>>\n")
} {
    # init
    src = $2
    dst = substr($4, 0, 17)

    # filters
    # Ignore Broadcast.
    if(src == "ff:ff:ff:ff:ff:ff" || dst == "ff:ff:ff:ff:ff:ff") next

    count++
    pair = src" > "dst

    # Export flow info
    # TODO：改成时间周期统计方法。
    if(count % flush_freq == 0) {
        _cont = "station \t tx_bytes \t tx_packs \t rx_bytes \t rx_packs"
        print(_cont) > dst_by_station
        if(dbg == "true") printf(_cont"\n")
        for(x in flow_by_station) {
            for(y in flow_by_station[x]) _flow[y] = flow_by_station[x][y]
            _cont = x" "_flow["tx_bytes"]" "_flow["tx_packs"]" "_flow["rx_bytes"]" "_flow["rx_packs"]
            print(_cont) >> dst_by_station
            if(dbg == "true") printf(_cont"\n")
        }
        close(dst_by_station)      # fflush file

        _cont = "src > dst \t bytes \t packs"
        print(_cont) > dst_by_pair
        if(dbg == "true") printf(_cont"\n")
        for(x in flow_by_pair) {
            _cont = x" "flow_by_pair[x]["bytes"]" "flow_by_pair[x]["packs"]
            print _cont >> dst_by_pair
            if(dbg == "true") printf(_cont"\n")
        }
        close(dst_by_pair)      # fflush file
        if(dbg == "true") printf("\n")
    }

    # Whether consider MAC header length
    pack_len = $12
    if(if_add_mac_header == "true") pack_len = $12 + 66

    # calc flow by stations
    if(src in flow_by_station) {
        flow_by_station[src]["tx_bytes"] += pack_len
        flow_by_station[src]["tx_packs"] += 1
    } else {
        flow_by_station[src]["tx_bytes"] = pack_len
        flow_by_station[src]["tx_packs"] = 1
    }
    if(dst in flow_by_station) {
        flow_by_station[dst]["rx_bytes"] += pack_len
        flow_by_station[dst]["rx_packs"] += 1
        # next
    } else {
        flow_by_station[dst]["rx_bytes"] = pack_len
        flow_by_station[dst]["rx_packs"] = 1
    }

    # calc flow by pairs
    for(x in flow_by_pair) {
        if(pair == x) {
            flow_by_pair[pair]["bytes"] += pack_len
            flow_by_pair[pair]["packs"] += 1
            next
        }
    }
    flow_by_pair[pair]["bytes"] = pack_len
    flow_by_pair[pair]["packs"] = 1
} END {
    if(dbg == "true") printf("\nIPv4 total packet: %d\n", NR)
}'
```

**程序说明如下：**

- `tcpdump`：

**参数说明：**

> -i eno1: 指定网卡
> -e: 打印输出中包含数据包的数据链路层头部信息
> -n: 不进行DNS解析，加快显示速度
> -q: 以快速输出的方式运行，此选项仅显示数据包的协议概要信息，输出信息较短
> -tt: 使用时间戳标记。如果显示具体时间可以使用-tttt

**输出如下：**

```csv
1555148383.759326 02:42:ac:11:00:02 > 02:42:aa:bd:a5:2c, IPv4, length 66: 172.17.0.2.41634 > 10.60.242.105.6379: tcp 0
1555148383.759546 02:42:ac:11:00:02 > 02:42:aa:bd:a5:2c, IPv4, length 841: 172.17.0.2.60034 > 10.60.242.105.6379: tcp 775
1555148383.759546 02:42:ac:11:00:02 > 02:42:aa:bd:a5:2c, IPv4, length 841: 172.17.0.2.60260 > 10.60.242.105.6379: tcp 775
1555148383.759638 02:42:aa:bd:a5:2c > 02:42:ac:11:00:02, IPv4, length 70: 10.60.242.105.6379 > 172.17.0.2.60034: tcp 4
1555148383.759657 02:42:ac:11:00:02 > 02:42:aa:bd:a5:2c, IPv4, length 66: 172.17.0.2.60034 > 10.60.242.105.6379: tcp 0
1555148383.759671 02:42:aa:bd:a5:2c > 02:42:ac:11:00:02, IPv4, length 70: 10.60.242.105.6379 > 172.17.0.2.60260: tcp 4
1555148383.759683 02:42:ac:11:00:02 > 02:42:aa:bd:a5:2c, IPv4, length 66: 172.17.0.2.60260 > 10.60.242.105.6379: tcp 0
1555148383.759697 02:42:aa:bd:a5:2c > 02:42:ac:11:00:02, IPv4, length 1674: 10.60.242.105.6379 > 172.17.0.2.59746: tcp 1608
1555148383.759704 02:42:ac:11:00:02 > 02:42:aa:bd:a5:2c, IPv4, length 66: 172.17.0.2.59746 > 10.60.242.105.6379: tcp 0
1555148383.759717 02:42:aa:bd:a5:2c > 02:42:ac:11:00:02, IPv4, length 1674: 10.60.242.105.6379 > 172.17.0.2.60028: tcp 1608
```

- `grep`：过滤IP数据

- `awk`：

**awk脚本的逻辑大致如下：**

1. 在BEGIN代码块中配置环境；
2. 在代码主体中按行做统计，然后在恰当的时机（比如传输1000个数据包之后）记录统计信息。

**统计结果输出：**

`flow_by_station.txt`：按照station统计到的结果。格式如下：

```csv
station          tx_bytes        tx_packs        rx_bytes        rx_packs
0c:c4:7a:85:38:12 2244 34 894820 9333
d0:94:66:43:f4:5a 1239872 5022 909166 9484
ac:1f:6b:13:b6:3e 3411523 30665 3914813 17195
0c:c4:7a:cb:22:d2 3411523 30665 66 1
01:00:5e:6f:70:0c 3411523 30665 9042 137
74:1f:4a:a0:85:2a 184925 2087 675951 2132
9c:b6:54:0c:96:6c 1098 9 1746 15
d0:94:66:43:e7:7d 1241446 5033 910322 9498
0c:c4:7a:b5:14:ee 2244 34 910322 9498
0c:c4:7a:85:3b:92 2244 34 910322 9498
ac:1f:6b:13:c3:fa 2244 34 66 1
0c:c4:7a:85:38:1c 2310 35 66 1
d0:94:66:43:ea:d1 1247604 5046 914338 9536
```

`flow_by_pair.txt`：按照pair(src > dst)统计到的结果。格式如下：

```csv
src > dst        bytes   packs
0c:c4:7a:85:38:1c > 01:00:5e:6f:70:0c 2310 35
ac:1f:6b:13:b6:3e > 9c:b6:54:0c:96:6c 1746 15
0c:c4:7a:85:3b:92 > 01:00:5e:6f:70:0c 2244 34
74:1f:4a:a0:85:2a > ac:1f:6b:13:c3:fa 66 1
9c:b6:54:0c:96:6c > ac:1f:6b:13:b6:3e 1098 9
ac:1f:6b:13:b6:3e > d0:94:66:43:e7:7d 910322 9498
0c:c4:7a:b5:14:ee > 01:00:5e:6f:70:0c 2244 34
ac:1f:6b:13:b6:3e > 74:1f:4a:a0:85:2a 675951 2132
74:1f:4a:a0:85:2a > ac:1f:6b:13:b6:3e 184793 2085
74:1f:4a:a0:85:2a > 0c:c4:7a:cb:22:d2 66 1
d0:94:66:43:ea:d1 > ac:1f:6b:13:b6:3e 1247604 5046
ac:1f:6b:13:b6:3e > d0:94:66:43:ea:d1 914338 9536
0c:c4:7a:85:38:12 > 01:00:5e:6f:70:0c 2244 34
d0:94:66:43:f4:5a > ac:1f:6b:13:b6:3e 1239872 5022
ac:1f:6b:13:b6:3e > d0:94:66:43:f4:5a 909166 9484
d0:94:66:43:e7:7d > ac:1f:6b:13:b6:3e 1241446 5033
```

#### TODO：

- 目前的统计周期是传输1000个数据包之后刷新统计结果，可以改成按时间周期统计方法。
- 目前在CentOS上测试OK，下一步需要在Android系统上测试。

#### 一些疑虑

- 使用负载过重

    tcmpdump抓包工具本身是很轻量的，网上有实测，普通使用模式下CPU占用在4%左右。我们在使用的时候抓包数据不落地，只会在固定时间间隔将统计结果写入文件，所以CPU占用会更低。

## 主要参考资料：

《tcpdump内容抓取和基于IP统计流量》：https://www.computerworld.com/article/2904085/how-to-monitor-wi-fi-traffic-on-android-devices.html
