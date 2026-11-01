@ECHO OFF
PATH=A:\
SET TEMP=A:\
SET TMP=A:\
SET EXPAND=YES
SET DIRCMD=/O:N
ECHO.
ECHO W98SERIAL: moving the console to COM1 (9600 8N1). Type CTTY CON over
ECHO serial to bring it back to this screen and keyboard.
MODE COM1:9600,N,8,1
CTTY AUX
ECHO.
ECHO === W98SERIAL boot floppy (ThinkPad 755C), console on COM1 9600 8N1 ===
VER
ECHO Commands: CHK      check C:, BIOS geometry and reach probes (read only)
ECHO           UNFILL   delete C:\PROBE\HIFILL*.BIN (only if every probe passed)
ECHO           W98SETUP start the unattended Windows 98 SE Setup
ECHO           CTTY CON give the console back to the screen and keyboard
