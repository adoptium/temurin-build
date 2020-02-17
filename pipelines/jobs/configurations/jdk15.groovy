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

// 17:05
triggerSchedule="TZ=UTC\n05 17 * * *"

return this
