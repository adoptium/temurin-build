targetConfigurations = [
        "x64Mac"        : [	"hotspot",	"openj9"					],
        "x64MacXL"      : [			"openj9"					],
        "x64Linux"      : [	"hotspot",	"openj9",	"dragonwell",	"corretto"	],
        "x64Windows"    : [	"hotspot",	"openj9",	"dragonwell"			],
        "x64WindowsXL"  : [			"openj9"					],
        "x32Windows"    : [	"hotspot"							],
        "ppc64Aix"      : [	"hotspot",	"openj9"					],
        "ppc64leLinux"  : [	"hotspot",	"openj9"					],
        "s390xLinux"    : [	"hotspot",	"openj9"					],
        "aarch64Linux"  : [	"hotspot",	"openj9",	"dragonwell"			],
        "arm32Linux"    : [	"hotspot"							],
        "x64LinuxXL"    : [			"openj9"					],
        "s390xLinuxXL"  : [			"openj9"					],
        "ppc64leLinuxXL": [			"openj9"					],
        "aarch64LinuxXL": [			"openj9"					],
        "riscv64Linux"  : [			"openj9"					]
]

// 18:05 Tue, Thur
triggerSchedule_nightly="TZ=UTC\n05 18 * * 2,4"
// 17:05 Sat
triggerSchedule_weekly="TZ=UTC\n05 17 * * 6"

// scmReferences to use for weekly release build
weekly_release_scmReferences=[
        "hotspot"        : "",
        "openj9"         : "",
        "corretto"       : "",
        "dragonwell"     : ""
]

return this
