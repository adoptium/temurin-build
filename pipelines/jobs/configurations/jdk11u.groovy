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
                "openj9",
                "corretto"
        ],
        "x64Windows"  : [
                "hotspot",
                "openj9"
        ],
        "x64WindowsXL"  : [
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
        "s390xLinux"  : [
                "hotspot",
                "openj9"
        ],
        "aarch64Linux": [
                "hotspot",
                "openj9"
        ],
        "arm32Linux"  : [
                "hotspot"
        ],
        "x64LinuxXL"     : [
                "openj9"
        ],
        "s390xLinuxXL"     : [
                "openj9"
        ],
        "ppc64leLinuxXL"     : [
                "openj9"
        ],
        "aarch64LinuxXL": [
                "openj9"
        ]
]

// 23:30
triggerSchedule="TZ=UTC\n30 23 * * *"

return this
