@echo off

sc delete "GameAP Daemon"

netsh advfirewall firewall delete rule name=GameAP_Daemon

echo "Please delete GameAP Daemon directory manually if it needed"

timeout 10