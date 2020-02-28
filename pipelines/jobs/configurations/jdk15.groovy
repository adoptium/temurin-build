targetConfigurations = [
        "x64Mac"      : [
                "hotspot"
        ],
        "x64Linux"    : [
                "hotspot"
        ],
        "x64Windows"  : [
                "hotspot"
        ],
        "ppc64Aix"    : [
                "hotspot",
                "openj9"
        ],
        "ppc64leLinux": [
                "hotspot"
        ],
        "s390xLinux"  : [
                "hotspot"
        ],
        "aarch64Linux": [
                "hotspot"
        ]
]

// 03:30
triggerSchedule="TZ=UTC\n30 03 * * *"

return this
