@ECHO OFF
REM Each probe file holds one line "W98PROBE Pnnnn ..." placed (from Linux)
REM at disk offset nnnn MiB of the slave card. A probe passes when FIND
REM prints that line under the file name. A file name with no line under it,
REM or a read error, means the BIOS did not reach that offset.
IF NOT EXIST C:\PROBE\P0400.TXT GOTO NONE
FIND "W98PROBE" C:\PROBE\P0400.TXT
FIND "W98PROBE" C:\PROBE\P0500.TXT
FIND "W98PROBE" C:\PROBE\P0520.TXT
FIND "W98PROBE" C:\PROBE\P1024.TXT
FIND "W98PROBE" C:\PROBE\P2040.TXT
GOTO END
:NONE
ECHO No probe files in C:\PROBE (mk-probes.sh not run).
:END
