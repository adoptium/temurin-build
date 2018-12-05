# Security files for OpenJDK

### This repository contains the cacerts file used with OpenJDK

#### Steps we use to create the cacerts file

1. Download the following Perl script: https://raw.githubusercontent.com/curl/curl/master/lib/mk-ca-bundle.pl

2. Download the following Java application: https://github.com/use-sparingly/keyutil/releases/download/0.4.0/keyutil-0.4.0.jar (source available at https://github.com/use-sparingly/keyutil)

3. Run the provided `GenerateCertsFile.sh` script with: `bash ./GenerateCertsFile.sh` - this will use the above files assuming they're located in the same directory as the script

4. Use the cacerts provided: it must be in the `jdk/jre/lib/security` or `jdk/lib/security`folder
