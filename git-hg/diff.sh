#!/bin/bash
version=$1

#cleanup
rm -rf openjdk-git openjdk-hg

git clone -b master "https://github.com/AdoptOpenJDK/openjdk-$version.git" openjdk-git || exit 1
hg clone "http://hg.openjdk.java.net/$version/$version" openjdk-hg || exit 1

cd openjdk-hg
bash get_source.sh
cd -

diffNum=`diff -rq openjdk-git openjdk-hg -x '.git' -x '.hg' -x '.hgtags' | grep 'only in' | wc -l`

if [ $diffNum -gt 0 ]; then
  echo "ERROR - THE DIFF HAS DETECTED UNKNOWN FILES"
  diff -rq openjdk-git openjdk-hg -x '.git' -x '.hg' -x '.hgtags' | grep 'only in' || exit 1
  exit 1
fi

# get latest git tag

cd openjdk-git
gitTag=`git describe --abbrev=0 --tags` || exit 1
cd -

cd openjdk-hg
hgTag=`hg log -r "." --template "{latesttag}\n"` || exit 1
cd -

if [ $gitTag == $hgTag ]; then
  echo "Tags are in sync"
else
  echo "ERROR - THE TAGS ARE NOT IN SYNC"
  exit 1
fi
