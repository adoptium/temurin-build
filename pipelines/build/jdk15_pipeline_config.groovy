class Config {
  final Map<String, Map<String, ?>> buildConfigurations = [
          "x64Mac"    : [
                  "os"                  : 'mac',
                  "arch"                : 'x64',
                  "additionalNodeLabels": 'macos10.14',
                  "test"                : [
                          "nightly": false,
                          "release": ['sanity.openjdk', 'sanity.system', 'extended.system', 'sanity.perf']
                  ]
          ],

          "x64Linux"  : [
                  "os"                  : 'linux',
                  "arch"                : 'x64',
                  "additionalNodeLabels": 'centos6',
                  "test"                : [
                          "nightly": false,
                          "release": ['sanity.openjdk', 'sanity.system', 'extended.system', 'sanity.perf', 'sanity.external', 'special.functional']
                  ],
                  "configureArgs"        : '--disable-ccache'
          ],

          // Currently we have to be quite specific about which windows to use as not all of them have freetype installed
          "x64Windows": [
                  "os"                  : 'windows',
                  "arch"                : 'x64',
                  "additionalNodeLabels": [
                          "hotspot": 'win2012&&vs2017'
                  ],
                  "buildArgs" : [
                          "hotspot" : '--jvm-variant client,server'
                  ],
                  "test"                : [
                          "nightly": false,
                          "release": ['sanity.openjdk', 'sanity.perf', 'sanity.system', 'extended.system']
                  ]
          ],

          "s390xLinux"    : [
                  "os"                  : 'linux',
                  "arch"                : 's390x',
                  "test"                : [
                          "nightly": false,
                          "release": ['sanity.openjdk', 'sanity.system', 'extended.system', 'sanity.perf']
                  ],
                  "configureArgs"        : '--disable-ccache'
          ],

          "ppc64leLinux"    : [
                  "os"                  : 'linux',
                  "arch"                : 'ppc64le',
                  "test"                : [
                          "nightly": false,
                          "release": ['sanity.openjdk', 'sanity.system', 'extended.system', 'sanity.perf']
                  ],
                  "configureArgs"       : '--disable-ccache'

          ],

          "aarch64Linux"    : [
                  "os"                  : 'linux',
                  "arch"                : 'aarch64',
                  "additionalNodeLabels": 'centos7',
                  "test"                : [
                          "nightly": false,
                          "release": ['sanity.openjdk', 'sanity.system', 'extended.system', 'sanity.perf']
                  ]
          ],

  ]

  Map<String, Map<String, ?>> get() {
    this.buildConfigurations                       
  }

}

Config config = new Config()
return config.buildConfigurations