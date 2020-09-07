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
        "x32Windows"  : [
                "hotspot"
        ],
        "x64Windows"  : [
                "hotspot",
                "openj9"
        ],
        "x64WindowsXL": [
                "openj9"
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
        "s390xLinuxXL": [
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

// 20:26
triggerSchedule="TZ=UTC\n26 20 * * *"

return this
