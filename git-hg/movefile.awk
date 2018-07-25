#!/bin/awk -f
{
    regex="\t" module "/"
    where = match($0, regex);
    if(where != 0) {
      print $0
    }
    else {
      print $1 "\t" module "/" $2
    }
}
