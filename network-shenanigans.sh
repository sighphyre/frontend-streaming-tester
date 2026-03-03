#!/bin/bash
set -euo pipefail

SERVER_NS="server_ns"
CLIENT_NS="client_ns"

# Inter-namespace link
VETH_SERVER="veth_server"
VETH_CLIENT="veth_client"
SERVER_IP="10.1.1.1"
CLIENT_IP="10.1.1.2"

# Uplink (ns <-> host root netns) via NAT
UP_SERVER_NS="veth_srv_up"
UP_SERVER_HOST="veth_srv_host"
UP_CLIENT_NS="veth_cli_up"
UP_CLIENT_HOST="veth_cli_host"

UP_GW_IP="10.200.1.1"
UP_SERVER_IP="10.200.1.2"
UP_CLIENT_IP="10.200.1.3"
UP_NET_CIDR="10.200.1.0/24"

# Try to auto-detect host egress interface (can override by exporting HOST_IFACE)
HOST_IFACE="${HOST_IFACE:-$(ip route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}')}"

setup() {
  echo "Creating namespaces and virtual wire..."
  echo "Host egress iface: $HOST_IFACE"
  echo "Remember to run cleanup with '$0 cleanup' when done!"

  sudo ip netns add "$SERVER_NS" || true
  sudo ip netns add "$CLIENT_NS" || true

  # Server <-> Client veth
  sudo ip link add "$VETH_SERVER" type veth peer name "$VETH_CLIENT" || true
  sudo ip link set "$VETH_SERVER" netns "$SERVER_NS"
  sudo ip link set "$VETH_CLIENT" netns "$CLIENT_NS"

  sudo ip netns exec "$SERVER_NS" ip addr add "$SERVER_IP/24" dev "$VETH_SERVER"
  sudo ip netns exec "$SERVER_NS" ip link set "$VETH_SERVER" up
  sudo ip netns exec "$SERVER_NS" ip link set lo up

  sudo ip netns exec "$CLIENT_NS" ip addr add "$CLIENT_IP/24" dev "$VETH_CLIENT"
  sudo ip netns exec "$CLIENT_NS" ip link set "$VETH_CLIENT" up
  sudo ip netns exec "$CLIENT_NS" ip link set lo up

  # Add uplink veths (server_ns <-> host) and (client_ns <-> host)
  sudo ip link add "$UP_SERVER_HOST" type veth peer name "$UP_SERVER_NS" || true
  sudo ip link add "$UP_CLIENT_HOST" type veth peer name "$UP_CLIENT_NS" || true

  sudo ip link set "$UP_SERVER_NS" netns "$SERVER_NS"
  sudo ip link set "$UP_CLIENT_NS" netns "$CLIENT_NS"

  # Host side: gateway IP + bring up
  sudo ip addr add "$UP_GW_IP/24" dev "$UP_SERVER_HOST" 2>/dev/null || true
  sudo ip link set "$UP_SERVER_HOST" up
  sudo ip link set "$UP_CLIENT_HOST" up

  # Namespace side: IP + bring up + default route via host gateway
  sudo ip netns exec "$SERVER_NS" ip addr add "$UP_SERVER_IP/24" dev "$UP_SERVER_NS"
  sudo ip netns exec "$SERVER_NS" ip link set "$UP_SERVER_NS" up
  sudo ip netns exec "$SERVER_NS" ip route replace default via "$UP_GW_IP"

  sudo ip netns exec "$CLIENT_NS" ip addr add "$UP_CLIENT_IP/24" dev "$UP_CLIENT_NS"
  sudo ip netns exec "$CLIENT_NS" ip link set "$UP_CLIENT_NS" up
  sudo ip netns exec "$CLIENT_NS" ip route replace default via "$UP_GW_IP"

  # DNS: copy host resolv.conf into each namespace
  # (namespaces use /etc/resolv.conf from their own mount namespace; simplest is to write it)
  sudo mkdir -p /etc/netns/"$SERVER_NS" /etc/netns/"$CLIENT_NS"
  sudo cp /etc/resolv.conf /etc/netns/"$SERVER_NS"/resolv.conf
  sudo cp /etc/resolv.conf /etc/netns/"$CLIENT_NS"/resolv.conf

  # Enable IPv4 forwarding
  sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null

  # NAT for namespace uplink subnet
  # Avoid duplicates by checking rule existence first
  if ! sudo iptables -t nat -C POSTROUTING -s "$UP_NET_CIDR" -o "$HOST_IFACE" -j MASQUERADE 2>/dev/null; then
    sudo iptables -t nat -A POSTROUTING -s "$UP_NET_CIDR" -o "$HOST_IFACE" -j MASQUERADE
  fi

  if ! sudo iptables -C FORWARD -s "$UP_NET_CIDR" -j ACCEPT 2>/dev/null; then
    sudo iptables -A FORWARD -s "$UP_NET_CIDR" -j ACCEPT
  fi
  if ! sudo iptables -C FORWARD -d "$UP_NET_CIDR" -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null; then
    sudo iptables -A FORWARD -d "$UP_NET_CIDR" -m state --state ESTABLISHED,RELATED -j ACCEPT
  fi

  # Apply Traffic Control (your original shaping) on the server<->client link
  echo "Applying 'honesty' (1mbit, 100ms delay) to $SERVER_NS..."
  sudo ip netns exec "$SERVER_NS" tc qdisc replace dev "$VETH_SERVER" root tbf rate 1mbit burst 32k latency 100ms

  echo "Setup complete."
  echo "Server IP (SSE target):  $SERVER_IP"
  echo "Client IP:               $CLIENT_IP"
  echo "Server uplink:           $UP_SERVER_IP via $UP_GW_IP"
  echo "Client uplink:           $UP_CLIENT_IP via $UP_GW_IP"
}

cleanup() {
  echo "Cleaning up namespaces and links..."

  # Remove iptables rules (best-effort)
  sudo iptables -t nat -D POSTROUTING -s "$UP_NET_CIDR" -o "$HOST_IFACE" -j MASQUERADE 2>/dev/null || true
  sudo iptables -D FORWARD -s "$UP_NET_CIDR" -j ACCEPT 2>/dev/null || true
  sudo iptables -D FORWARD -d "$UP_NET_CIDR" -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true

  sudo ip link del "$UP_SERVER_HOST" 2>/dev/null || true
  sudo ip link del "$UP_CLIENT_HOST" 2>/dev/null || true

  sudo ip netns del "$SERVER_NS" 2>/dev/null || true
  sudo ip netns del "$CLIENT_NS" 2>/dev/null || true

  sudo rm -rf /etc/netns/"$SERVER_NS" /etc/netns/"$CLIENT_NS" 2>/dev/null || true

  echo "Cleanup complete."
}

case "${1:-}" in
  setup) setup ;;
  cleanup) cleanup ;;
  *) echo "Usage: $0 {setup|cleanup}" ;;
esac