@ECHO OFF
REM Run only after CHK showed all five probes. Frees the space past 504 MiB.
IF NOT EXIST C:\PROBE\HIFILL0.BIN GOTO NONE
ECHO Deleting C:\PROBE\HIFILL*.BIN (FAT writes only, at the start of C:) ...
DEL C:\PROBE\HIFILL?.BIN
DIR C:\PROBE
GOTO END
:NONE
ECHO No HIFILL files in C:\PROBE.
:END
