W98SERIAL boot floppy for the ThinkPad 755C (Windows 98 SE boot disk,
console on COM1 9600 8N1). Built by errata/755c/win98/mk-win98-floppy.sh
from the El Torito image of the Win98 SE CD. See errata/755c/WIN98-INSTALL.md.

CHK       VOL C:, DIR of the setup files, MEM, BIOS geometry, reach probes
PROBE     the reach probes only
UNFILL    delete C:\PROBE\HIFILL*.BIN (only after every probe passed)
W98SETUP  SETUP.EXE C:\WIN98\MSBATCH.INF /IS /IQ /IE /IM /IR /IV /NF
SYS.COM   fallback only: SYS C: if C: will not boot after Setup
