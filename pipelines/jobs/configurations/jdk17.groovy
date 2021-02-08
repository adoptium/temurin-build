targetConfigurations = [
        "x64Mac"      : [
                "hotspot",
                "openj9"
        ],
        "x64MacXL"    : [
                "openj9"
        ],
        "x64Linux"    : [
                "hotspot",
                "openj9"
        ],
        "x64LinuxXL"  : [
                "openj9"
        ],
        "x64AlpineLinux" : [
                "hotspot"
        ],
        "x64Windows"  : [
                "hotspot",
                "openj9"
        ],
        "x64WindowsXL": [
                "openj9"
        ],
        "x32Windows"  : [
                "hotspot"
        ],
        "ppc64Aix"    : [
                "hotspot",
                "openj9"
        ],
        "ppc64leLinux": [
                "hotspot",
                "openj9"
        ],
        "ppc64leLinuxXL": [
                "openj9"
        ],
        "s390xLinux"  : [
                "hotspot",
                "openj9"
        ],
        "s390xLinuxXL"  : [
                "openj9"
        ],
        "aarch64Linux": [
                "hotspot",
                "openj9"
        ],
        "aarch64LinuxXL": [
                "openj9"
        ],
        "arm32Linux"  : [
                "hotspot"
        ]
]

// 03:30 Wed, Fri
triggerSchedule_nightly="TZ=UTC\n30 03 * * 3,5"
// 12:05 Sun
triggerSchedule_weekly="TZ=UTC\n05 12 * * 7"

// scmReferences to use for weekly release build
weekly_release_scmReferences=[
        "hotspot"        : "",
        "openj9"         : "",
        "corretto"       : "",
        "dragonwell"     : ""
]

return this
