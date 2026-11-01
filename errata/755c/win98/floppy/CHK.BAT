@ECHO OFF
ECHO.
ECHO === CHK 1/5: which disk is C:  (expect: Volume in drive C is WIN98SE) ===
VOL C:
ECHO === CHK 2/5: C:\ and the setup files (expect SETUP.EXE, MSBATCH.INF) ===
DIR C:\ /A
DIR C:\WIN98\SETUP.EXE
DIR C:\WIN98\MSBATCH.INF
ECHO === CHK 3/5: memory ===
MEM
ECHO === CHK 4/5: BIOS disks (INT 13h AH=08 for 80h, 81h; AH=41 for 81h) ===
DEBUG < A:\GEO.SCR
ECHO === CHK 5/5: BIOS reach probes on C: ===
CALL A:\PROBE.BAT
ECHO === CHK done ===
