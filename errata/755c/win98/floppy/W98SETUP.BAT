@ECHO OFF
IF NOT EXIST C:\WIN98\SETUP.EXE GOTO NOSRC
IF NOT EXIST C:\WIN98\MSBATCH.INF GOTO NOINF
IF EXIST C:\PROBE\HIFILL0.BIN ECHO NOTE: HIFILL files present, Setup only gets the space below 504 MiB.
ECHO Starting Windows 98 SE Setup, unattended (C:\WIN98\MSBATCH.INF).
ECHO The console now goes back to the 755C screen: serial output ends here.
ECHO Take the floppy out once the Setup screen appears.
SET TEMP=C:\
SET TMP=C:\
C:
CD \WIN98
CTTY CON
SETUP.EXE C:\WIN98\MSBATCH.INF /IS /IQ /IE /IM /IR /IV /NF
GOTO END
:NOSRC
ECHO C:\WIN98\SETUP.EXE not found. Run CHK.
GOTO END
:NOINF
ECHO C:\WIN98\MSBATCH.INF not found.
:END
