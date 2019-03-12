@echo off

IF NOT EXIST c:\gameap\. (
	echo "Creating c:\gameap\daemon"
	mkdir c:\gameap\daemon
	
	echo "Creating c:\gameap\daemon\log"
	mkdir c:\gameap\daemon\log
	
	echo "Creating c:\gameap\daemon\log"
	mkdir c:\gameap\steamcmd
)

REM xcopy /s %cd% c:\gameap\daemon\
for %%i in (*) do move "%%i" c:\gameap\daemon\

sc create "GameAP Daemon" start= auto binpath= c:\gameap\daemon\gameap-daemon.exe
sc failure "GameAP Daemon" reset= 600 actions= run/5000/reboot/800

netsh advfirewall firewall add rule name=GameAP_Daemon dir=in action=allow protocol=TCP localport=31717

c:\gameap\daemon\curl.exe http://packages.gameap.ru/windows/steamcmd.exe --output c:\gameap\steamcmd\steamcmd.exe

exit 0