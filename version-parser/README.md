# Python Version Parser for openjdk

## usage:

```bash
python version-parser.py <path_to_java> <adopt_build_number>
# e.g the following command returns something like 8, 0, 202, 08, None, 8.0.202+08.1
python version-parse.py /usr/bin/java 1
```

#### Simple usage with bash:

```bash
#!/bin/bash
RESULT=$(python version-parser.py /usr/bin/java 1)
IFS=', ' read -r -a result <<< "$RESULT"
major="${result[0]}" # 8
minor="${result[1]}" # 0
security="${result[2]}" # 202
build="${result[3]}" # 08
opt="${result[4]}" # None or 201903130451
semver="${result[5]}" # 8.0.202+08.1
version="${result[6]}" # 1.8.0_202-b08
```

## testing:
```bash
./test-version-parser.sh
```
