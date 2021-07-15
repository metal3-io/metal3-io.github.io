#!/bin/bash
# Description: This script generates markdown files for each release of Baremetal Operator in repository
# Generated markdown files should be stored under _posts/ for website rendering

TARGET='build'
mkdir -p build/artifacts || continue
mkdir -p _posts/releases || continue
[[ -e build/baremetal-operator ]] || git clone https://github.com/metal3-io/baremetal-operator.git build/baremetal-operator/
git -C build/baremetal-operator checkout master
git -C build/baremetal-operator pull --tags

releases() {
    git -C build/baremetal-operator tag | sort -rV | while read TAG; do
        echo "$TAG"
    done
}

features_for() {
    echo -e ""
    git -C build/baremetal-operator show $1 | grep Date: | head -n1 | sed "s/Date:\s\+/Released on: /"
    echo -e ""
    git -C build/baremetal-operator show $1 | sed -n "/changes$/,/Contributors/ p" | egrep "^- "
}

gen_changelog() {
    {
        for REL in $(releases); do
            FILENAME="changelog-$REL.markdown"
            cat <<EOF >$FILENAME
---
layout: post
author: 🤖🎸🤘
description: This article provides information about Baremetal Operator release $REL changes
navbar_active: Blogs
category: releases
comments: true
title: Baremetal Operator $REL
pub-date: July 23
pub-year: 2018
tags: [release notes, changelog]
---

EOF

            (
                echo -e "\n## $REL"
                features_for $REL
            ) >>"$FILENAME"
            daterelease=$(cat "$FILENAME" | grep "Released on" | cut -d ":" -f 2-)
            newdate=$(echo $daterelease | tr " " "\n" | grep -v "+" | tr "\n" " ")

            if $(LANG=C date --date="$newdate" '+%Y' >/dev/null 2>&1); then
                year=$(LANG=C date --date="$newdate" '+%Y')
                month=$(LANG=C date --date="$newdate" '+%m')
                monthname=$(LANG=C date --date="$newdate" '+%B')
                day=$(LANG=C date --date="$newdate" '+%d')
                NEWFILENAME="build/artifacts/$year-$month-$day-$FILENAME"
                mv $FILENAME $NEWFILENAME
                sed -i "s#^pub-date:.*#pub-date: $monthname $day#g" "$NEWFILENAME"
                sed -i "s#^pub-year:.*#pub-year: $year#g" "$NEWFILENAME"
            else
                rm ${FILENAME}
            fi
        done
    }
}

gen_changelog

for file in build/artifacts/*.markdown; do
    [ -f _posts/$(basename $file) ] || mv $file _posts/releases/
done
