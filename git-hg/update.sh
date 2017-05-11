#!/bin/bash

echo "Common defs"

# shellcheck disable=SC1091
. import-common.sh

echo "Enter hg"

cd hg || exit 1

# shellcheck disable=SC2034
bpaths=(ls -d -1 */*)

for bpath in "$@bpaths"
do

pushd "$bpath/root"
echo "Update $bpath -> (root)"
git hg fetch "http://hg.openjdk.java.net/$bpath"
git hg pull "http://hg.openjdk.java.net/$bpath"
popd

for m in "$@submodules"
do
    pushd "$bpath/$m"
    echo "Update $bpath -> $m"
    git hg fetch "http://hg.openjdk.java.net/$bpath/$m"
    git hg pull "http://hg.openjdk.java.net/$bpath/$m"
    popd
done

echo "Exit hg"
echo "Enter combined"

cd ../combined || exit 1

echo "Check out $bpath"

git checkout master || exit 1

echo "Fetch (root)"

git fetch imports/"$bpath"/root || exit 1

echo "Merge (root)"

git merge imports/"$bpath"/root/master -m "Merge from (root)" --no-ff || exit 1

for m in "$@submodules"
do
    echo "Fetch '$m'"
    git fetch imports/"$bpath"/"$m" || exit 1

    echo "Merge '$m'"
    git subtree merge --prefix="$m" imports/"$bpath"/"$m"/master -m "Merge from '$m'" || exit 1
done

echo "Push"

git push github master --tags

cd ../hg || exit 1

done
