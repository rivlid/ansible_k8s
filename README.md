# Example BGP config for Bird
```nginx
filter k8s_services {
        if net ~ [ 192.168.253.0/24{32,32} ] then accept;
        reject;
}
template bgp k8s_peers {
        local as 64512;
        import filter k8s_services;
        export none;
        import limit 20 action block;
}
protocol bgp k8s_w00 from k8s_peers { neighbor 10.69.0.10 as 64513; }
protocol bgp k8s_w01 from k8s_peers { neighbor 10.69.0.11 as 64513; }
protocol bgp k8s_w02 from k8s_peers { neighbor 10.69.0.12 as 64513; }
protocol bgp k8s_w03 from k8s_peers { neighbor 10.69.0.20 as 64513; }
protocol bgp k8s_w04 from k8s_peers { neighbor 10.69.0.21 as 64513; }
protocol bgp k8s_w05 from k8s_peers { neighbor 10.69.0.22 as 64513; }
```