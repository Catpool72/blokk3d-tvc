#!/bin/sh
# Build: tables -> asm -> CAS.   PROFILE=1 ./build.sh  for the measuring build.
set -e
cd "$(dirname "$0")"
SJ=${SJASMPLUS:-/root/sjasmplus/sjasmplus}
python3 gen.py tables.inc
python3 title.py title.inc title_preview.png
build() {   # $1 = kimeneti nev, tovabbi: definiciok
  OUT=$1; shift
  $SJ --nologo "$@" --sym=$OUT.sym --lst=$OUT.lst blokk.asm
  [ "$OUT" = blokk ] || mv blokk.bin $OUT.bin
  python3 mkcas.py $OUT.bin $OUT.cas
}
if [ -n "$PROFILE" ]; then
  build blokk_prof -DPROFILE
  build blokk64p_prof -DPROFILE -DPLUS
else
  build blokk            # TVC 64K
  build blokk64p -DPLUS  # TVC 64+
fi
