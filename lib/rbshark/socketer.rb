# frozen_string_literal: true

require 'socket'
require 'rbshark/analyzer'
require 'rbshark/printer'
require 'rbshark/resource/type'

module Rbshark
  class Socketer
    def initialize(options, pcap = nil)
      @options = options
      @pcap = pcap
    end

    def start
      socket = Socket.open(Socket::AF_PACKET, Socket::SOCK_RAW, Rbshark::ETH_P_ALL)
      if @options.key?('interface')
        ifreq = []
        ifreq.push(@options['interface'])
        ifreq = ifreq.dup.pack('a' + Rbshark::IFREQ_SIZE.to_s)
        socket.ioctl(Rbshark::SIOCGIFINDEX, ifreq)
        if_num = ifreq[Socket::IFNAMSIZ, Rbshark::IFINDEX_SIZE]

        socket.bind(sockaddr_ll(if_num))
      end
      bind(socket)
    end

    def sockaddr_ll(ifnum)
      sll = [Socket::AF_PACKET].pack('s')
      sll << [Rbshark::ETH_P_ALL].pack('s')
      sll << ifnum
      sll << ('\x00' * (Rbshark::SOCKADDR_LL_SIZE - sll.length))
    end

    def bind(socket)
      end_time = Time.now + @options['time'] if @options.key?('time')
      while true
        # パケットを受信しないとループが回らないため、終了時間を過ぎてもパケットを受信しないと終了しない
        if @options.key?('time')
          break if Time.now > end_time
        end

        # パケットの取得部分
        mesg = socket.recvfrom(1024*8)
        # pcap用のタイムスタンプを取得
        ts = Time.now
        # パケットのデータはrecvfromだと[0]に該当するので分離させる
        frame = mesg[0]
        ether_header = Rbshark::EthernetAnalyzer.new(frame)
        printer = Rbshark::Printer.new
        @pcap.dump_packet(frame, ts) if @options['write']
        printer.print_ethernet(ether_header)

        case ether_header.check_protocol_type
        when 'ARP'
          arp_header = Rbshark::ARPAnalyzer.new(frame, ether_header.return_byte)
          printer.print_arp(arp_header)
        when 'IP'
          ip_header = Rbshark::IPAnalyzer.new(frame, ether_header.return_byte)
          printer.print_ip(ip_header)
          case ip_header.check_protocol_type
          when 'ICMP'
            icmp = Rbshark::ICMPAnalyzer.new(frame, ip_header.return_byte)
            printer.print_icmp(icmp)
          when 'TCP'
            tcp = Rbshark::TCPAnalyzer.new(frame, ip_header.return_byte)
            printer.print_tcp(tcp)
          when 'UDP'
            udp = Rbshark::UDPAnalyzer.new(frame, ip_header.return_byte)
            printer.print_udp(udp)
          end
          # when 'IPv6'
          # ipv6_header = IPV6Analyzer.new(frame, ether_header.return_byte)
          # print_ip(ipv6_header)
        end
      end
    end
  end
end
