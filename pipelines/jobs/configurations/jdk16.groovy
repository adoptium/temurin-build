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
        "aarch64Windows" : [
                "hotspot"
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

// 23:30 Mon, Wed, Fri
triggerSchedule_nightly="TZ=UTC\n30 23 * * 1,3,5"
// 04:30 Sun
triggerSchedule_weekly="TZ=UTC\n30 04 * * 7"

return this
