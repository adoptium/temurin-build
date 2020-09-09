# Security files for OpenJDK

## CA Certificates

The cacerts file that OpenJDK maintains lacks a number of CA certificates that are present in common browsers. As a result, users of OpenJDK cannot connect to servers with Java that they can connect to with their browsers. This causes confusion and [support requests][support-issues]. 

In May 2020, [we reached out to OpenJDK to discuss this situation][jdk-dev-thread], but no consensus was reached. Consequently, the [AdoptOpenJDK TSC decided to deviate from OpenJDK and distribute a custom trust store][tsc-decision] based on [Mozilla's list of trusted CA certificates][mozilla-certdata] which is also used by many Linux distributions.

If you want to build OpenJDK with the original cacerts file, set `--custom-cacerts=false`.

### Process

The `cacerts` file is build as part of the regular JDK build from source. The reason is that vetting blobs in PR is difficult. Because `certdata.txt` cannot be converted directly into a Java Key Store, we do it in multiple steps:

1. Convert `certdata.txt` in a PEM file (`ca-bundle.crt`) with [mk-ca-bundle.pl][mk-ca-bundle.pl].
2. Split `ca-bundle.crt` into individual certificates and import them with `keytool` into a new `cacerts` file.

To generate a new `cacerts` file, run:

    $ ./mk-cacerts.sh

If anybody ever plans to replace `mk-ca-bundle.pl`, be sure to read [Can I use Mozilla's set of CA certificates?][can-i-use-mozilla].

### Updating the List of Certificates

Every time Mozilla updates the list of CA certificates, we have to update our copy of `certdata.txt`. Whether it needs to be updated can be checked on [curl's website][curl-ca-extract]. If it needs updating, the process looks as follows:

1. Download the [current version of certdata.txt][mozilla-certdata].
2. Replace the existing file in `security`.
3. Open a pull request to get it merged.

The updated list will be picked up during the next build.

### License

The resulting cacerts file is licensed under the terms of the [source file][mozilla-certdata], the Mozilla Public License, v.2.0.

## Future Work

* Create a GitHub bot that checks whether `certdata.txt` needs updating and automatically creates a PR.

 [support-issues]: https://github.com/AdoptOpenJDK/openjdk-support/issues/13
 [jdk-dev-thread]: https://mail.openjdk.java.net/pipermail/jdk-dev/2020-May/004305.html
 [tsc-decision]: https://github.com/AdoptOpenJDK/openjdk-support/issues/13#issuecomment-635400251
 [mozilla-certdata]: https://hg.mozilla.org/releases/mozilla-release/raw-file/default/security/nss/lib/ckfw/builtins/certdata.txt
 [mk-ca-bundle.pl]: https://curl.haxx.se/docs/mk-ca-bundle.html
 [curl-ca-extract]: https://curl.haxx.se/docs/caextract.html
 [can-i-use-mozilla]: https://wiki.mozilla.org/CA/FAQ#Can_I_use_Mozilla.27s_set_of_CA_certificates.3F
